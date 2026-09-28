#include "session.h"
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include "../drivers/imu.h"
#include "../drivers/battery.h"
#include "../drivers/led_indicator.h"
#include "../ble/ble_service.h"
#include "../sensor/fifo.h"

LOG_MODULE_REGISTER(session, LOG_LEVEL_INF);

static const struct device *imu_i2c_dev = NULL;
static imu_calibration_t calibration_data;
static imu_fifo_t imu_fifo;

static uint8_t status_flags = 0;
static uint16_t stream_seq_num = 0;
static bool is_session_running = false;

/* 100 Hz sampling timer */
static struct k_timer sample_timer;
static struct k_work sample_work;

/* Periodic battery check (every 5 seconds) */
static struct k_work_delayable battery_work;

static void sample_work_handler(struct k_work *work)
{
    session_sample_tick();
}

static void sample_timer_handler(struct k_timer *timer_id)
{
    k_work_submit(&sample_work);
}

static void battery_work_handler(struct k_work *work)
{
    uint16_t mv = battery_read_mv();
    bool low = battery_is_low();

    if (low) {
        status_flags |= STATUS_FLAG_LOW_BATT;
    } else {
        status_flags &= ~STATUS_FLAG_LOW_BATT;
    }

    led_set_low_battery(low);
    LOG_DBG("Periodic battery check: %u mV (low=%d)", mv, low);

    k_work_reschedule(&battery_work, K_SECONDS(5));
}

int session_init(const struct device *i2c_device)
{
    imu_i2c_dev = i2c_device;
    imu_calibration_init(&calibration_data);
    imu_fifo_init(&imu_fifo);

    status_flags = 0;
    stream_seq_num = 0;
    is_session_running = false;

    k_timer_init(&sample_timer, sample_timer_handler, NULL);
    k_work_init(&sample_work, sample_work_handler);
    k_work_init_delayable(&battery_work, battery_work_handler);

    /* Start periodic battery monitor */
    k_work_reschedule(&battery_work, K_SECONDS(1));

    LOG_INF("Session manager initialized");
    return 0;
}

uint8_t session_get_status_byte(void)
{
    uint8_t s = status_flags;
    if (battery_is_low()) {
        s |= STATUS_FLAG_LOW_BATT;
    }
    if (is_session_running) {
        s |= STATUS_FLAG_SESSION_ACTIVE;
    }
    if (calibration_data.is_calibrated) {
        s |= STATUS_FLAG_CALIBRATED;
    }
    return s;
}

const imu_calibration_t *session_get_calibration(void)
{
    return &calibration_data;
}

static void send_status_ack(uint8_t ack_cmd)
{
    ble_status_packet_t status_pkt;
    status_pkt.device_status = session_get_status_byte();
    status_pkt.battery_mv = battery_read_mv();
    status_pkt.last_command_ack = ack_cmd;

    ble_service_notify_status(&status_pkt);
    LOG_INF("Status sent: status=0x%02X, batt=%u mV, ack=0x%02X",
            status_pkt.device_status, status_pkt.battery_mv, ack_cmd);
}

void session_handle_command(uint8_t cmd)
{
    LOG_INF("Processing command: 0x%02X", cmd);

    switch (cmd) {
    case CMD_START_SESSION: {
        /*
         * === AUTO-CALIBRATE-ON-START FLOW ===
         * 1. Assume stationary device on barbell.
         * 2. Set LED to solid calibrating.
         * 3. Run 3s calibration to compute gyro bias and gravity vector.
         * 4. Set calibrated status flag and send Status ack.
         * 5. Set session_active, transition LED to streaming heartbeat, start 100 Hz streaming.
         */
        LOG_INF(">>> AUTO-CALIBRATE-ON-START: Initiating 3s baseline calibration...");
        led_set_state(LED_STATE_CALIBRATING);

        int ret = imu_calibration_run(imu_i2c_dev, &calibration_data);
        if (ret == 0) {
            status_flags |= STATUS_FLAG_CALIBRATED;
            LOG_INF("Auto-calibration SUCCESS: Gyro bias=[%.2f, %.2f, %.2f] dps",
                    (double)calibration_data.gyro_bias_dps[0],
                    (double)calibration_data.gyro_bias_dps[1],
                    (double)calibration_data.gyro_bias_dps[2]);
        } else {
            LOG_WRN("Auto-calibration completed with warning/retry code: %d", ret);
        }

        /* Send status notification confirming calibration completed */
        send_status_ack(CMD_START_SESSION);

        /* Reset FIFO and start streaming */
        imu_fifo_reset(&imu_fifo);
        is_session_running = true;
        status_flags |= STATUS_FLAG_SESSION_ACTIVE;

        led_set_state(LED_STATE_STREAMING);
        k_timer_start(&sample_timer, K_MSEC(10), K_MSEC(10)); /* 100 Hz */
        LOG_INF(">>> SESSION ACTIVE: 100 Hz batched streaming started!");
        break;
    }

    case CMD_STOP_SESSION: {
        LOG_INF(">>> STOP_SESSION: Stopping IMU streaming.");
        k_timer_stop(&sample_timer);
        is_session_running = false;
        status_flags &= ~STATUS_FLAG_SESSION_ACTIVE;

        if (ble_service_is_connected()) {
            led_set_state(LED_STATE_CONNECTED);
        } else {
            led_set_state(LED_STATE_IDLE);
        }

        send_status_ack(CMD_STOP_SESSION);
        break;
    }

    case CMD_CALIBRATE: {
        LOG_INF(">>> Standalone CALIBRATE requested: Running 3s calibration...");
        bool was_running = is_session_running;
        if (was_running) {
            k_timer_stop(&sample_timer);
        }

        led_set_state(LED_STATE_CALIBRATING);
        int ret = imu_calibration_run(imu_i2c_dev, &calibration_data);
        if (ret == 0) {
            status_flags |= STATUS_FLAG_CALIBRATED;
        }

        send_status_ack(CMD_CALIBRATE);

        if (was_running) {
            imu_fifo_reset(&imu_fifo);
            led_set_state(LED_STATE_STREAMING);
            k_timer_start(&sample_timer, K_MSEC(10), K_MSEC(10));
        } else {
            led_set_state(ble_service_is_connected() ? LED_STATE_CONNECTED : LED_STATE_IDLE);
        }
        break;
    }

    case CMD_PING: {
        LOG_INF(">>> PING command received: Sending status heartbeat.");
        send_status_ack(CMD_PING);
        break;
    }

    default:
        LOG_WRN("Unknown command received: 0x%02X", cmd);
        send_status_ack(cmd);
        break;
    }
}

void session_sample_tick(void)
{
    if (!imu_i2c_dev || !is_session_running) {
        return;
    }

    imu_sample_t s;
    int ret = imu_read(imu_i2c_dev, &s);
    if (ret != 0) {
        LOG_WRN("IMU sample read failed (%d)", ret);
        return;
    }

    /* Subtract calibrated gyro bias */
    imu_calibration_apply(&calibration_data, &s);

    uint32_t ts_ms = (uint32_t)k_uptime_get_32();
    imu_batch_t batch;

    if (imu_fifo_push(&imu_fifo, &s, ts_ms, &batch)) {
        /* 5 samples ready -> build and notify 78-byte packet */
        ble_stream_packet_t pkt;
        pkt.protocol_version = BLE_PROTOCOL_VERSION;
        pkt.packet_type = BLE_PACKET_TYPE_IMU_BATCH;
        pkt.sequence_number = stream_seq_num++;
        pkt.base_timestamp_ms = batch.base_timestamp_ms;
        pkt.sample_count = batch.count;
        pkt.device_status = session_get_status_byte();
        pkt.battery_mv = battery_read_mv();

        for (int i = 0; i < BLE_SAMPLES_PER_BATCH; i++) {
            pkt.samples[i].ax = batch.samples[i].ax;
            pkt.samples[i].ay = batch.samples[i].ay;
            pkt.samples[i].az = batch.samples[i].az;
            pkt.samples[i].gx = batch.samples[i].gx;
            pkt.samples[i].gy = batch.samples[i].gy;
            pkt.samples[i].gz = batch.samples[i].gz;
            pkt.samples[i].dt_ms = batch.samples[i].dt_ms;
        }

        ble_protocol_encode_stream_packet(&pkt);
        ble_service_notify_stream(&pkt);
    }
}

void session_on_ble_connection_changed(bool connected)
{
    if (connected) {
        LOG_INF("BLE Central Connected. Device READY.");
        if (is_session_running) {
            led_set_state(LED_STATE_STREAMING);
        } else {
            led_set_state(LED_STATE_CONNECTED);
        }
        /* Send initial status upon connection */
        send_status_ack(0x00);
    } else {
        LOG_INF("BLE Central Disconnected. Stopping active session if running.");
        if (is_session_running) {
            k_timer_stop(&sample_timer);
            is_session_running = false;
            status_flags &= ~STATUS_FLAG_SESSION_ACTIVE;
        }
        led_set_state(LED_STATE_IDLE);
    }
}
