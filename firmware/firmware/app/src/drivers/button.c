#include "button.h"
#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/poweroff.h>
#include <hal/nrf_gpio.h>
#include <hal/nrf_power.h>
#include "led_indicator.h"

LOG_MODULE_REGISTER(button, LOG_LEVEL_INF);

/* Devicetree lookup for button on sw0 */
static const struct gpio_dt_spec button_spec = GPIO_DT_SPEC_GET_OR(DT_ALIAS(sw0), gpios, {0});

/* Default fallback pin: P0.02 (D0 on XIAO) */
#define BUTTON_FALLBACK_PIN 2

static struct gpio_callback button_cb_data;
static button_event_callback_t app_callback = NULL;

static int64_t press_start_time_ms = 0;
static bool is_pressed = false;
static bool is_ble_connected = false;
static bool is_session_active = false;

/* Work items and timer for debouncing and long-press / auto-sleep */
static struct k_work_delayable debounce_work;
static struct k_work_delayable auto_sleep_work;

/* ── System OFF Low-Power Mode ────────────────────────────────────────────── */
void button_enter_sleep(void)
{
    LOG_INF("=================================================");
    LOG_INF("  Entering SYSTEM OFF Deep Sleep...");
    LOG_INF("  Press button on D0 (P0.02) to wake up.");
    LOG_INF("=================================================");

    /* Ensure all LEDs are fully OFF */
    led_set_state(LED_STATE_OFF);
    k_msleep(50);

    /* Configure button pin (P0.02) as SENSE LOW wake-up source before entering sleep */
    nrf_gpio_cfg_input(
        NRF_GPIO_PIN_MAP(0, BUTTON_FALLBACK_PIN),
        NRF_GPIO_PIN_PULLUP
    );
    nrf_gpio_cfg_sense_set(
        NRF_GPIO_PIN_MAP(0, BUTTON_FALLBACK_PIN),
        NRF_GPIO_PIN_SENSE_LOW
    );

    /* Flush log buffer */
    k_msleep(20);

    /* Enter System OFF */
    sys_poweroff();

    /* Fallback if sys_poweroff returns */
    nrf_power_system_off(NRF_POWER);
    while (1) {
        /* Spin until power cuts */
    }
}

/* ── Auto-Sleep Inactivity Timer Handler ─────────────────────────────────── */
static void auto_sleep_work_handler(struct k_work *work)
{
    if (!is_ble_connected && !is_session_active) {
        LOG_INF("BLE connection window timed out (%d ms) with no central. Entering auto-sleep.", BLE_CONNECT_TIMEOUT_MS);
        button_enter_sleep();
    }
}

/* ── Button Debounce Work Handler ────────────────────────────────────────── */
static void debounce_work_handler(struct k_work *work)
{
    int pin_val = 0;
    if (button_spec.port && device_is_ready(button_spec.port)) {
        pin_val = gpio_pin_get_dt(&button_spec);
    } else {
        pin_val = nrf_gpio_pin_read(NRF_GPIO_PIN_MAP(0, BUTTON_FALLBACK_PIN)) == 0 ? 1 : 0;
    }

    int64_t now = k_uptime_get();

    if (pin_val > 0) {
        /* Button is still held down */
        if (!is_pressed) {
            is_pressed = true;
            press_start_time_ms = now;
            LOG_DBG("Button pressed down");
        }
    } else {
        /* Button was released */
        if (is_pressed) {
            is_pressed = false;
            int64_t duration = now - press_start_time_ms;
            LOG_INF("Button released after %lld ms", duration);

            bool is_long_press = (duration >= BUTTON_LONG_PRESS_MS);

            if (app_callback) {
                app_callback(is_long_press);
            }
        }
    }
}

/* ── Button ISR ───────────────────────────────────────────────────────────── */
static void button_pressed_isr(const struct device *dev, struct gpio_callback *cb, uint32_t pins)
{
    /* Reschedule debounce handler */
    k_work_reschedule(&debounce_work, K_MSEC(BUTTON_DEBOUNCE_MS));
}

/* ── Public API ───────────────────────────────────────────────────────────── */
int button_init(void)
{
    int ret = 0;

    k_work_init_delayable(&debounce_work, debounce_work_handler);
    k_work_init_delayable(&auto_sleep_work, auto_sleep_work_handler);

    if (button_spec.port && device_is_ready(button_spec.port)) {
        ret = gpio_pin_configure_dt(&button_spec, GPIO_INPUT | GPIO_PULL_UP);
        if (ret < 0) {
            LOG_WRN("Failed to configure button pin via DT: %d", ret);
        } else {
            ret = gpio_pin_interrupt_configure_dt(&button_spec, GPIO_INT_EDGE_BOTH);
            if (ret < 0) {
                LOG_WRN("Failed to configure button interrupt: %d", ret);
            } else {
                gpio_init_callback(&button_cb_data, button_pressed_isr, BIT(button_spec.pin));
                gpio_add_callback(button_spec.port, &button_cb_data);
                LOG_INF("Button initialized on pin %d via devicetree", button_spec.pin);
            }
        }
    } else {
        /* Direct NRF GPIO fallback configuration on P0.02 */
        nrf_gpio_cfg_input(
            NRF_GPIO_PIN_MAP(0, BUTTON_FALLBACK_PIN),
            NRF_GPIO_PIN_PULLUP
        );
        LOG_INF("Button initialized on fallback pin P0.02 (D0)");
    }

    /* Start auto-sleep timer: 5 minutes if no BLE connection */
    k_work_reschedule(&auto_sleep_work, K_MSEC(BLE_CONNECT_TIMEOUT_MS));

    return 0;
}

void button_register_callback(button_event_callback_t cb)
{
    app_callback = cb;
}

void button_notify_ble_connected(bool connected)
{
    is_ble_connected = connected;
    if (connected) {
        /* Cancel auto-sleep timer while central is actively connected */
        k_work_cancel_delayable(&auto_sleep_work);
        LOG_INF("BLE connected: Auto-sleep timer paused");
    } else {
        /* Central disconnected: restart 5-minute auto-sleep countdown */
        if (!is_session_active) {
            k_work_reschedule(&auto_sleep_work, K_MSEC(BLE_CONNECT_TIMEOUT_MS));
            LOG_INF("BLE disconnected: Auto-sleep timer reset to %d ms", BLE_CONNECT_TIMEOUT_MS);
        }
    }
}

void button_notify_session_state(bool session_active)
{
    is_session_active = session_active;
    if (session_active) {
        k_work_cancel_delayable(&auto_sleep_work);
    } else if (!is_ble_connected) {
        k_work_reschedule(&auto_sleep_work, K_MSEC(BLE_CONNECT_TIMEOUT_MS));
    }
}
