#ifndef DRIVERS_LED_INDICATOR_H_
#define DRIVERS_LED_INDICATOR_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LED_STATE_ADVERTISING = 0,  /* Boot / advertising, not connected: slow BLUE blink (100ms on, 1900ms off) */
    LED_STATE_CONNECTED,        /* BLE connected, not yet calibrated: solid/fast-blinking CYAN (Blue+Green) */
    LED_STATE_CALIBRATING,      /* Calibrating: blinking YELLOW/AMBER (Red+Green) for calibration duration */
    LED_STATE_STREAMING,        /* Ready / actively streaming, session active: solid / breathing GREEN */
    LED_STATE_OFF               /* Asleep / powered down: fully OFF (save power) */
} led_state_t;

/* Backward compatibility aliases */
#define LED_STATE_IDLE LED_STATE_ADVERTISING

/**
 * @brief Initialize the onboard RGB LEDs and the background pattern timer engine.
 * @return 0 on success, negative error code on failure.
 */
int led_indicator_init(void);

/**
 * @brief Set the active LED state pattern.
 * @param state The high-level LED state.
 */
void led_set_state(led_state_t state);

/**
 * @brief Get the currently set LED state pattern.
 */
led_state_t led_get_state(void);

/**
 * @brief Update low-battery indicator overlay.
 * @param is_low true if battery is low, triggering high-priority RED blink overlay.
 */
void led_set_low_battery(bool is_low);

#ifdef __cplusplus
}
#endif

#endif /* DRIVERS_LED_INDICATOR_H_ */
