/*
 * src/app/session_lite.h
 *
 * IronLoop Session Manager — Lite version (no battery, no button, no LEDs).
 * Designed for USB-powered bench testing over BLE.
 *
 * Features:
 *   - Auto-starts streaming when BLE central subscribes to Stream characteristic
 *   - Also supports CMD_START_SESSION / CMD_STOP_SESSION / CMD_CALIBRATE commands
 *   - 100 Hz IMU sampling → batched into 5-sample packets → BLE notify at 20 Hz
 *   - 3-second stationary calibration (gyro bias removal)
 *   - Sensor fault detection & status reporting
 */

#ifndef IRONLOOP_APP_SESSION_LITE_H
#define IRONLOOP_APP_SESSION_LITE_H

#include <stdint.h>
#include <stdbool.h>
#include <zephyr/device.h>
#include "../ble/ble_protocol.h"
#include "../sensor/calibration.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Initialize the lite session manager and bind IMU device.
 */
int session_lite_init(const struct device *i2c_device);

/**
 * @brief Set or clear the sensor fault status bit.
 */
void session_lite_set_sensor_fault(bool fault);

/**
 * @brief Unified command dispatcher (called by BLE GATT Command write).
 *
 * Commands:
 *   - CMD_START_SESSION (0x01): Run 3s calibration → start 100 Hz streaming
 *   - CMD_STOP_SESSION  (0x02): Stop streaming
 *   - CMD_CALIBRATE     (0x03): Standalone calibration
 *   - CMD_PING          (0x04): Send immediate status notification
 */
void session_lite_handle_command(uint8_t cmd);

/**
 * @brief Called every 10ms (100 Hz) during active session.
 *        Reads IMU, pushes to FIFO, sends BLE notify when batch is full.
 */
void session_lite_sample_tick(void);

/**
 * @brief Handle BLE connection / disconnection transitions.
 */
void session_lite_on_ble_connection_changed(bool connected);

/**
 * @brief Handle stream characteristic subscription changes.
 *        Auto-starts streaming when subscribed (for simple test clients).
 */
void session_lite_on_stream_subscribed(bool subscribed);

/**
 * @brief Get current 8-bit status bitfield.
 */
uint8_t session_lite_get_status_byte(void);

#ifdef __cplusplus
}
#endif

#endif /* IRONLOOP_APP_SESSION_LITE_H */
