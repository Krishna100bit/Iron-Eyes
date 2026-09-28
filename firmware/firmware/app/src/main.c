/*
 * src/main.c
 *
 * IRONLOOP — Smart Barbell Velocity Tracker Firmware
 * Seeed XIAO nRF52840 Sense (Onboard LSM6DS3TR-C IMU, I2C, BLE, RGB LED, Battery ADC, Button)
 *
 * Boot sequence:
 *   1. Check & log RESETREAS register (Power-On, Wake from Sleep, Pin Reset, Brownout)
 *   2. Initialize RGB LED indicators & Battery SAADC monitor
 *   3. Initialize Physical Button & Sleep/Wake state machine
 *   4. Start BLE Advertising IMMEDIATELY (non-blocking early visibility)
 *   5. Enable IMU power rail (P1.08) and initialize I2C0 & LSM6DS3TR-C driver
 *   6. Main thread yields indefinitely — background ISRs/timers drive all operations
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/logging/log.h>
#include <hal/nrf_power.h>

#include "drivers/imu.h"
#include "drivers/battery.h"
#include "drivers/led_indicator.h"
#include "drivers/button.h"
#include "ble/ble_service.h"
#include "app/session_lite.h"

LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);

/* ---------------------------------------------------------------------------
 * Devicetree lookups
 * -------------------------------------------------------------------------*/

/*
 * I2C bus for the onboard LSM6DS3TR-C IMU.
 * On Seeed XIAO nRF52840 Sense the IMU is wired to i2c0 (SDA=P0.07, SCL=P0.27).
 */
#define I2C_NODE DT_NODELABEL(i2c0)
static const struct device *i2c_dev = DEVICE_DT_GET(I2C_NODE);

/* IMU Power rail on Seeed Sense: GPIO P1.08 */
#define IMU_PWR_PORT_NODE DT_NODELABEL(gpio1)
#define IMU_PWR_PIN       8

static const struct device *gpio1_dev = DEVICE_DT_GET(IMU_PWR_PORT_NODE);

/* Boot counter tracked across resets (if RAM retained) */
static int boot_counter = 0;

/* ---------------------------------------------------------------------------
 * Reset Reason Diagnostic Logger
 * -------------------------------------------------------------------------*/
static void log_reset_reason(void)
{
    uint32_t reas = nrf_power_resetreas_get(NRF_POWER);

    LOG_INF("-------------------------------------------------");
    LOG_INF("  SoC Reset Reason Register (RESETREAS: 0x%08X)", reas);

    if (reas == 0) {
        LOG_INF("  >> Clean Power-On Reset (POR)");
    } else {
        if (reas & NRF_POWER_RESETREAS_RESETPIN_MASK) {
            LOG_INF("  >> Pin Reset (hardware reset button pressed)");
        }
        if (reas & NRF_POWER_RESETREAS_DOG_MASK) {
            LOG_WRN("  >> Watchdog Timeout Reset");
        }
        if (reas & NRF_POWER_RESETREAS_SREQ_MASK) {
            LOG_INF("  >> Software Reset (AIRCR)");
        }
        if (reas & NRF_POWER_RESETREAS_LOCKUP_MASK) {
            LOG_ERR("  >> CPU Lockup Reset");
        }
        if (reas & NRF_POWER_RESETREAS_OFF_MASK) {
            LOG_INF("  >> [WAKE] Wake-up from SYSTEM OFF Sleep mode (Button press)");
        }
        if (reas & NRF_POWER_RESETREAS_LPCOMP_MASK) {
            LOG_INF("  >> Wake-up from LPCOMP");
        }
        if (reas & NRF_POWER_RESETREAS_DIF_MASK) {
            LOG_INF("  >> Debug interface wake-up");
        }
    }
    LOG_INF("-------------------------------------------------");

    /* Clear the register after reading to capture subsequent resets cleanly */
    nrf_power_resetreas_clear(NRF_POWER, reas);
}

/* ---------------------------------------------------------------------------
 * Main Initialization Sequence
 * -------------------------------------------------------------------------*/
int main(void)
{
    int ret;
    boot_counter++;

    /* 1. Diagnostic Boot Banner right at top of main() */
    LOG_INF("=================================================");
    LOG_INF("  IRONLOOP — Smart Barbell Velocity Tracker");
    LOG_INF("  Target : Seeed XIAO nRF52840 Sense");
    LOG_INF("  Boot # : %d | Uptime: %lld ms", boot_counter, k_uptime_get());
    LOG_INF("  Build  : %s %s", __DATE__, __TIME__);
    LOG_INF("=================================================");

    /* 2. Check and log last reset reason */
    log_reset_reason();

    /* 3. Initialize RGB LED Indicators */
    led_indicator_init();
    led_set_state(LED_STATE_ADVERTISING);

    /* 4. Initialize Battery Monitor */
    battery_init();
    uint16_t init_batt = battery_read_mv();
    LOG_INF("Battery level at boot: %u mV (Low threshold: %u mV)", init_batt, BATTERY_LOW_THRESHOLD_MV);

    /* 5. Initialize Physical Button & Sleep/Wake State Machine */
    button_init();

    /* 6. Initialize Session Manager */
    ret = session_lite_init(i2c_dev);
    if (ret != 0) {
        LOG_ERR("Session manager init failed: %d", ret);
    }

    /* 7. Initialize BLE Stack & GATT Service — Make device discoverable immediately */
    LOG_INF("Starting BLE stack & advertising...");
    ret = ble_service_init(session_lite_handle_command,
                           session_lite_on_ble_connection_changed,
                           session_lite_on_stream_subscribed);
    if (ret != 0) {
        LOG_ERR("BLE service init failed (Zephyr err %d)", ret);
    } else {
        LOG_INF("BLE Advertising started successfully — device: \"%s\"", CONFIG_BT_DEVICE_NAME);
        LOG_INF("Waiting for BLE central connection (auto-sleep window: %d ms)...", BLE_CONNECT_TIMEOUT_MS);
    }

    /* 8. Power on IMU Sensor Rail (P1.08) */
    if (device_is_ready(gpio1_dev)) {
        ret = gpio_pin_configure(gpio1_dev, IMU_PWR_PIN, GPIO_OUTPUT_ACTIVE);
        if (ret == 0) {
            gpio_pin_set(gpio1_dev, IMU_PWR_PIN, 1);
            LOG_INF("IMU power rail (P1.08) enabled [OK]");
        } else {
            LOG_WRN("Failed to configure IMU power pin: %d", ret);
        }
    } else {
        LOG_WRN("GPIO1 controller not ready for IMU power rail");
    }

    /* Allow IMU power rail and internal oscillator to stabilize */
    k_msleep(30);

    /* 9. Initialize I2C Bus & LSM6DS3TR-C IMU Driver */
    if (!device_is_ready(i2c_dev)) {
        LOG_ERR("I2C device '%s' not ready! (check board definition)", i2c_dev->name);
        session_lite_set_sensor_fault(true);
    } else {
        LOG_INF("I2C bus '%s' ready", i2c_dev->name);
        ret = imu_init(i2c_dev);
        if (ret != 0) {
            LOG_ERR("LSM6DS3TR-C IMU init FAILED (err %d)", ret);
            LOG_ERR("Check: is the board a 'Sense' variant with onboard IMU?");
            session_lite_set_sensor_fault(true);
        } else {
            LOG_INF("LSM6DS3TR-C IMU online and verified [OK]");
            session_lite_set_sensor_fault(false);
        }
    }

    LOG_INF("System ready. Running main event loop...");

    /* 10. Main thread yields indefinitely — BLE ISRs and timers drive ops */
    while (1) {
        k_sleep(K_FOREVER);
    }

    return 0;
}
