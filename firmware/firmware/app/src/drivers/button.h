#ifndef DRIVERS_BUTTON_H_
#define DRIVERS_BUTTON_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Button timing configurations */
#define BUTTON_DEBOUNCE_MS          40
#define BUTTON_LONG_PRESS_MS        1500
#define BLE_CONNECT_TIMEOUT_MS      300000  /* 5 minutes auto-sleep if no BLE connection */

typedef void (*button_event_callback_t)(bool is_long_press);

/**
 * @brief Initialize the physical button GPIO, interrupts, and power management.
 * @return 0 on success, negative error code on failure.
 */
int button_init(void);

/**
 * @brief Register handler for button events.
 */
void button_register_callback(button_event_callback_t cb);

/**
 * @brief Put SoC into System OFF deep sleep mode with button GPIO configured as wake-up source.
 */
void button_enter_sleep(void);

/**
 * @brief Notify button manager that BLE connection state has changed.
 *        Resets or stops the auto-sleep inactivity timer.
 */
void button_notify_ble_connected(bool connected);

/**
 * @brief Notify button manager that a training session has started or stopped.
 */
void button_notify_session_state(bool session_active);

#ifdef __cplusplus
}
#endif

#endif /* DRIVERS_BUTTON_H_ */
