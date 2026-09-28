#include "led_indicator.h"
#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(led_indicator, LOG_LEVEL_INF);

/* Devicetree aliases for onboard RGB LEDs */
static const struct gpio_dt_spec led_red   = GPIO_DT_SPEC_GET_OR(DT_ALIAS(led0), gpios, {0});
static const struct gpio_dt_spec led_green = GPIO_DT_SPEC_GET_OR(DT_ALIAS(led1), gpios, {0});
static const struct gpio_dt_spec led_blue  = GPIO_DT_SPEC_GET_OR(DT_ALIAS(led2), gpios, {0});

static led_state_t current_state = LED_STATE_ADVERTISING;
static bool current_low_battery = false;
static uint32_t pattern_tick = 0;

/* Timer for non-blocking LED pattern engine (runs at 50ms tick resolution) */
static struct k_timer led_timer;

static void set_led_output(const struct gpio_dt_spec *spec, int value)
{
    if (spec->port && device_is_ready(spec->port)) {
        gpio_pin_set_dt(spec, value);
    }
}

static void led_timer_handler(struct k_timer *timer_id)
{
    pattern_tick++;

    bool red_on = false;
    bool green_on = false;
    bool blue_on = false;

    switch (current_state) {
    case LED_STATE_ADVERTISING: {
        /* Boot / advertising, no BLE connection yet: slow BLUE blink (100ms on, 1900ms off = 40 ticks) */
        uint32_t step = pattern_tick % 40;
        if (step < 2) { /* 100 ms */
            blue_on = true;
        }
        break;
    }

    case LED_STATE_CONNECTED: {
        /* BLE connected, not yet calibrated: fast-blinking CYAN (Blue + Green, 100ms on, 150ms off = 5 ticks) */
        uint32_t step = pattern_tick % 5;
        if (step < 2) {
            blue_on = true;
            green_on = true;
        }
        break;
    }

    case LED_STATE_CALIBRATING: {
        /* Calibrating: fast blinking YELLOW/AMBER (Red + Green, 100ms on, 100ms off = 4 ticks) */
        uint32_t step = pattern_tick % 4;
        if (step < 2) {
            red_on = true;
            green_on = true;
        }
        break;
    }

    case LED_STATE_STREAMING: {
        /* Ready / actively streaming, session active: solid GREEN */
        green_on = true;
        break;
    }

    case LED_STATE_OFF:
    default:
        /* Asleep / powered down: fully OFF */
        break;
    }

    /* Low battery overlay: high-priority blinking RED flash every 2 seconds (100ms on, 1900ms off) */
    if (current_low_battery) {
        uint32_t low_step = pattern_tick % 40;
        if (low_step < 2) {
            /* Override with solid RED during the warning window */
            red_on = true;
            green_on = false;
            blue_on = false;
        }
    }

    set_led_output(&led_red, red_on ? 1 : 0);
    set_led_output(&led_green, green_on ? 1 : 0);
    set_led_output(&led_blue, blue_on ? 1 : 0);
}

int led_indicator_init(void)
{
    int ret;

    if (led_red.port && device_is_ready(led_red.port)) {
        ret = gpio_pin_configure_dt(&led_red, GPIO_OUTPUT_INACTIVE);
        if (ret < 0) {
            LOG_WRN("Failed to config red LED: %d", ret);
        }
    }

    if (led_green.port && device_is_ready(led_green.port)) {
        ret = gpio_pin_configure_dt(&led_green, GPIO_OUTPUT_INACTIVE);
        if (ret < 0) {
            LOG_WRN("Failed to config green LED: %d", ret);
        }
    }

    if (led_blue.port && device_is_ready(led_blue.port)) {
        ret = gpio_pin_configure_dt(&led_blue, GPIO_OUTPUT_INACTIVE);
        if (ret < 0) {
            LOG_WRN("Failed to config blue LED: %d", ret);
        }
    }

    k_timer_init(&led_timer, led_timer_handler, NULL);
    k_timer_start(&led_timer, K_MSEC(50), K_MSEC(50));

    LOG_INF("RGB LED indicator initialized (Red:led0, Green:led1, Blue:led2)");
    return 0;
}

void led_set_state(led_state_t state)
{
    if (current_state != state) {
        current_state = state;
        pattern_tick = 0; /* Reset pattern phase */
        LOG_DBG("LED state -> %d", state);
    }
}

led_state_t led_get_state(void)
{
    return current_state;
}

void led_set_low_battery(bool is_low)
{
    current_low_battery = is_low;
}
