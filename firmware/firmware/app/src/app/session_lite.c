/*
 * src/app/session_lite.c
 *
 * IronLoop Session Manager
 * Connects IMU acquisition, BLE communication, LED state transitions,
 * battery monitoring, and physical button sleep/wake handling.
 */

#include "session_lite.h"
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include "../drivers/imu.h"
#include "../drivers/battery.h"
#include "../drivers/led_indicator.h"
#include "../drivers/button.h"
#include "../ble/ble_service.h"
#include "../sensor/fifo.h"

LOG_MODULE_REGISTER(session_lite, LOG_LEVEL_INF);

static const struct device *imu_i2c_dev = NULL;
static imu_calibration_t calibration_data;
static imu_fifo_t imu_fifo;

static uint8_t status_flags = 0;
static uint16_t stream_seq_num = 0;
static bool is_session_running = false;
static bool has_sensor_fault = false;

/* Forward declarations */
static void stop_streaming(void);
static void send_status_ack(uint8_t ack_cmd);

/* 100 Hz sampling timer + work item */
static struct k_timer sample_timer;
static struct k_work sample_work;

/* Periodic battery check work */
static struct k_work_delayable battery_work;

/* ── Timer / Work handlers ────────────────────────────────────────────── */

static void sample_work_handler(struct k_work *work)
{
    session_lite_sample_tick();
}

static void sample_timer_handler(struct k_timer *timer_id)
{
    k_work_submit(&sample_work);
}

static void battery_work_handler(struct k_work *work)
{
    uint16_t mv = battery_sample_tick();
    bool critical = battery_is_critical();
    bool low = battery_is_low();

    if (critical) {
        LOG_ERR("=================================================================");
        LOG_ERR("  CRITICAL BATTERY: %u mV <= %u mV!", mv, BATTERY_CRITICAL_THRESHOLD_MV);
        LOG_ERR("  Shutting down immediately to protect 300mAh LiPo cell from damage!");
        LOG_ERR("=================================================================");

        if (is_session_running) {
            stop_streaming();
        }

        status_flags |= STATUS_FLAG_LOW_BATT;
        send_status_ack(0xFF); /* Send final status notification */
        k_msleep(100);

        button_enter_sleep();
        return;
    }

    if (low) {
        status_flags |= STATUS_FLAG_LOW_BATT;
    } else {
        status_flags &= ~STATUS_FLAG_LOW_BATT;
    }

    led_set_low_battery(low);
    LOG_DBG("Periodic battery check: %u mV (low=%d)", mv, low);

    k_work_reschedule(&battery_work, K_SECONDS(BATTERY_SAMPLE_INTERVAL_SEC));
}

/* ── Start / Stop streaming ───────────────────────────────────────────── */

static void start_streaming(void)
{
    if (is_session_running) {
        return; /* Already running */
    }

    imu_fifo_reset(&imu_fifo);
    stream_seq_num = 0;
    is_session_running = true;
    status_flags |= STATUS_FLAG_SESSION_ACTIVE;

    button_notify_session_state(true);
    led_set_state(LED_STATE_STREAMING);

    k_timer_start(&sample_timer, K_MSEC(10), K_MSEC(10)); /* 100 Hz */
    LOG_INF(">>> SESSION ACTIVE: 100 Hz IMU streaming started!");
}

static void stop_streaming(void)
{
    if (!is_session_running) {
        return; /* Already stopped */
    }

    k_timer_stop(&sample_timer);
    is_session_running = false;
    status_flags &= ~STATUS_FLAG_SESSION_ACTIVE;

    button_notify_session_state(false);

    if (ble_service_is_connected()) {
        led_set_state(LED_STATE_CONNECTED);
    } else {
        led_set_state(LED_STATE_ADVERTISING);
    }

    LOG_INF(">>> SESSION STOPPED: IMU streaming halted.");
}

/* ── Status notification helper ───────────────────────────────────────── */

static void send_status_ack(uint8_t ack_cmd)
{
    ble_status_packet_t status_pkt;
    status_pkt.device_status = session_lite_get_status_byte();
    status_pkt.battery_mv = battery_read_mv();
    status_pkt.last_command_ack = ack_cmd;

    ble_service_notify_status(&status_pkt);
    LOG_INF("Status sent: status=0x%02X, batt=%u mV, ack=0x%02X",
            status_pkt.device_status, status_pkt.battery_mv, ack_cmd);
}

/* ── Physical Button Event Handler ────────────────────────────────────── */

static void on_button_event(bool is_long_press)
{
    LOG_INF("Button event received: %s press", is_long_press ? "LONG (>1.5s)" : "SHORT (<1.5s)");

    if (is_session_running) {
        /* While session is active: short or long press -> stop session and power down to SLEEP */
        LOG_INF("Session is active: Button press -> STOPPING session and entering SLEEP...");
        stop_streaming();
        send_status_ack(CMD_STOP_SESSION);
        k_msleep(100);
        button_enter_sleep();
    } else {
        /* While awake and NOT mid-session: long press -> trigger CALIBRATE */
        if (is_long_press) {
            LOG_INF("Not mid-session: Long press -> Triggering CALIBRATION!");
            session_lite_handle_command(CMD_CALIBRATE);
        } else {
            LOG_INF("Not mid-session: Short press ignored (hold >1.5s to calibrate)");
        }
    }
}

/* ── Public API ───────────────────────────────────────────────────────── */

int session_lite_init(const struct device *i2c_device)
{
    imu_i2c_dev = i2c_device;
    imu_calibration_init(&calibration_data);
    imu_fifo_init(&imu_fifo);

    status_flags = 0;
    stream_seq_num = 0;
    is_session_running = false;
    has_sensor_fault = false;

    k_timer_init(&sample_timer, sample_timer_handler, NULL);
    k_work_init(&sample_work, sample_work_handler);
    k_work_init_delayable(&battery_work, battery_work_handler);

    /* Register physical button event callback */
    button_register_callback(on_button_event);

    /* Start periodic battery monitor */
    k_work_reschedule(&battery_work, K_SECONDS(1));

    LOG_INF("Session manager initialized with LED, battery, and button support");
    return 0;
}

void session_lite_set_sensor_fault(bool fault)
{
    has_sensor_fault = fault;
    if (fault) {
        status_flags |= STATUS_FLAG_SENSOR_FAULT;
    } else {
        status_flags &= ~STATUS_FLAG_SENSOR_FAULT;
    }
}

uint8_t session_lite_get_status_byte(void)
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
    if (has_sensor_fault) {
        s |= STATUS_FLAG_SENSOR_FAULT;
    }
    return s;
}

void session_lite_handle_command(uint8_t cmd)
{
    LOG_INF("Processing command: 0x%02X", cmd);

    switch (cmd) {
    case CMD_START_SESSION: {
        /*
         * Auto-Calibrate-On-Start Flow:
         * 1. Set LED to blinking YELLOW/AMBER (calibrating)
         * 2. Run 3s stationary calibration
         * 3. Set CALIBRATED flag & notify Status
         * 4. Transition LED to solid GREEN, start 100 Hz streaming
         */
        if (has_sensor_fault || !imu_i2c_dev) {
            LOG_ERR("Cannot start session: Sensor fault flag is active!");
            send_status_ack(CMD_START_SESSION);
            return;
        }

        LOG_INF(">>> AUTO-CALIBRATE-ON-START: Running 3s calibration...");
        LOG_INF(">>> KEEP BARBELL COMPLETELY STILL!");
        led_set_state(LED_STATE_CALIBRATING);

        int ret = imu_calibration_run(imu_i2c_dev, &calibration_data);
        if (ret == 0) {
            status_flags |= STATUS_FLAG_CALIBRATED;
            LOG_INF("Calibration SUCCESS: gyro_bias=[%.2f, %.2f, %.2f] dps",
                    (double)calibration_data.gyro_bias_dps[0],
                    (double)calibration_data.gyro_bias_dps[1],
                    (double)calibration_data.gyro_bias_dps[2]);
        } else {
            LOG_WRN("Calibration completed with warning: %d", ret);
        }

        send_status_ack(CMD_START_SESSION);
        start_streaming();
        break;
    }

    case CMD_STOP_SESSION: {
        LOG_INF(">>> STOP_SESSION: Stopping IMU streaming.");
        stop_streaming();
        send_status_ack(CMD_STOP_SESSION);
        break;
    }

    case CMD_CALIBRATE: {
        if (has_sensor_fault || !imu_i2c_dev) {
            LOG_ERR("Cannot calibrate: Sensor fault flag is active!");
            send_status_ack(CMD_CALIBRATE);
            return;
        }

        LOG_INF(">>> Standalone CALIBRATE: Running 3s calibration...");
        bool was_running = is_session_running;
        if (was_running) {
            stop_streaming();
        }

        led_set_state(LED_STATE_CALIBRATING);
        int ret = imu_calibration_run(imu_i2c_dev, &calibration_data);
        if (ret == 0) {
            status_flags |= STATUS_FLAG_CALIBRATED;
        }

        send_status_ack(CMD_CALIBRATE);

        if (was_running) {
            start_streaming();
        } else {
            led_set_state(ble_service_is_connected() ? LED_STATE_CONNECTED : LED_STATE_ADVERTISING);
        }
        break;
    }

    case CMD_PING: {
        LOG_INF(">>> PING: Sending status heartbeat.");
        send_status_ack(CMD_PING);
        break;
    }

    default:
        LOG_WRN("Unknown command: 0x%02X", cmd);
        send_status_ack(cmd);
        break;
    }
}

void session_lite_sample_tick(void)
{
    if (!imu_i2c_dev || !is_session_running || has_sensor_fault) {
        return;
    }

    imu_sample_t s;
    int ret = imu_read(imu_i2c_dev, &s);
    if (ret != 0) {
        LOG_WRN("IMU read failed (%d)", ret);
        return;
    }

    /* Apply calibration if available (gyro bias subtraction) */
    imu_calibration_apply(&calibration_data, &s);

    uint32_t ts_ms = (uint32_t)k_uptime_get_32();
    imu_batch_t batch;

    if (imu_fifo_push(&imu_fifo, &s, ts_ms, &batch)) {
        /* 5 samples ready → build 78-byte packet and BLE notify */
        ble_stream_packet_t pkt;
        pkt.protocol_version = BLE_PROTOCOL_VERSION;
        pkt.packet_type = BLE_PACKET_TYPE_IMU_BATCH;
        pkt.sequence_number = stream_seq_num++;
        pkt.base_timestamp_ms = batch.base_timestamp_ms;
        pkt.sample_count = batch.count;
        pkt.device_status = session_lite_get_status_byte();
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
        int err = ble_service_notify_stream(&pkt);
        if (err && err != -EACCES) {
            LOG_WRN("BLE notify failed: %d", err);
        }
    }
}

void session_lite_on_ble_connection_changed(bool connected)
{
    button_notify_ble_connected(connected);

    if (connected) {
        LOG_INF("BLE Central Connected — device READY.");
        if (is_session_running) {
            led_set_state(LED_STATE_STREAMING);
        } else {
            led_set_state(LED_STATE_CONNECTED);
        }
        /* Send initial status */
        send_status_ack(0x00);
    } else {
        LOG_INF("BLE Central Disconnected — stopping active session if running.");
        stop_streaming();
        led_set_state(LED_STATE_ADVERTISING);
    }
}

void session_lite_on_stream_subscribed(bool subscribed)
{
    if (subscribed) {
        LOG_INF("Stream notifications ENABLED by central.");
        if (!is_session_running && !has_sensor_fault) {
            LOG_INF(">>> AUTO-START: Beginning raw IMU streaming...");
            start_streaming();
        }
    } else {
        LOG_INF("Stream notifications DISABLED by central.");
        stop_streaming();
    }
}
