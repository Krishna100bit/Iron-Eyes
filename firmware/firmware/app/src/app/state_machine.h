/*
 * src/app/state_machine.h
 *
 * IronLoop device state machine.
 */

#ifndef IRONLOOP_APP_STATE_MACHINE_H
#define IRONLOOP_APP_STATE_MACHINE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Device states */
typedef enum {
    DEV_STATE_IDLE           = 0,
    DEV_STATE_READY          = 1,
    DEV_STATE_CALIBRATING    = 2,
    DEV_STATE_SESSION_ACTIVE = 3,
} device_state_t;

/* Status bitfield (Byte 9 in batched packet) */
#define STATUS_FLAG_CALIBRATED       (1 << 0)  /* Bit 0 */
#define STATUS_FLAG_LOW_BATT         (1 << 1)  /* Bit 1 */
#define STATUS_FLAG_SESSION_ACTIVE   (1 << 2)  /* Bit 2 */
#define STATUS_FLAG_CALIBRATING      (1 << 3)  /* Bit 3 */

/* Commands received over BLE Command Characteristic */
#define CMD_START_SESSION   0x01
#define CMD_STOP_SESSION    0x02
#define CMD_CALIBRATE       0x03
#define CMD_SET_ODR         0x04
#define CMD_PING            0x05

typedef struct {
    device_state_t state;
    bool           is_calibrated;
    bool           is_low_battery;
    uint16_t       battery_mv;
} app_state_t;

/**
 * @brief Initialize device state machine.
 */
void state_machine_init(app_state_t *app);

/**
 * @brief Get current status bitfield.
 */
uint8_t state_machine_get_status_byte(const app_state_t *app);

/**
 * @brief Set device state.
 */
void state_machine_set_state(app_state_t *app, device_state_t new_state);

/**
 * @brief Get string description of current state.
 */
const char* state_machine_state_str(device_state_t state);

#ifdef __cplusplus
}
#endif
#endif /* IRONLOOP_APP_STATE_MACHINE_H */
