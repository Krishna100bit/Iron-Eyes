/*
 * src/app/state_machine.c
 *
 * State machine implementation.
 */

#include "state_machine.h"
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(state_machine, LOG_LEVEL_INF);

void state_machine_init(app_state_t *app)
{
    if (app) {
        app->state = DEV_STATE_IDLE;
        app->is_calibrated = false;
        app->is_low_battery = false;
        app->battery_mv = 4150; /* 4.15V nominal USB/LiPo */
    }
}

uint8_t state_machine_get_status_byte(const app_state_t *app)
{
    if (!app) return 0;

    uint8_t status = 0;
    if (app->is_calibrated) {
        status |= STATUS_FLAG_CALIBRATED;
    }
    if (app->is_low_battery) {
        status |= STATUS_FLAG_LOW_BATT;
    }
    if (app->state == DEV_STATE_SESSION_ACTIVE) {
        status |= STATUS_FLAG_SESSION_ACTIVE;
    }
    if (app->state == DEV_STATE_CALIBRATING) {
        status |= STATUS_FLAG_CALIBRATING;
    }
    return status;
}

void state_machine_set_state(app_state_t *app, device_state_t new_state)
{
    if (!app || app->state == new_state) {
        return;
    }

    LOG_INF("State Transition: [%s] -> [%s]",
            state_machine_state_str(app->state),
            state_machine_state_str(new_state));

    app->state = new_state;
}

const char* state_machine_state_str(device_state_t state)
{
    switch (state) {
    case DEV_STATE_IDLE:           return "IDLE";
    case DEV_STATE_READY:          return "READY";
    case DEV_STATE_CALIBRATING:    return "CALIBRATING";
    case DEV_STATE_SESSION_ACTIVE: return "SESSION_ACTIVE";
    default:                       return "UNKNOWN";
    }
}
