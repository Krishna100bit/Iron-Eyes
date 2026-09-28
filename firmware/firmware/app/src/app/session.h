#ifndef APP_SESSION_H_
#define APP_SESSION_H_

#include <stdint.h>
#include <stdbool.h>
#include <zephyr/device.h>
#include "../ble/ble_protocol.h"
#include "../sensor/calibration.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Initialize the session manager and bind IMU device.
 */
int session_init(const struct device *i2c_device);

/**
 * @brief Unified command dispatcher (called by BLE GATT Command write and future button handler).
 *
 * Implements the Auto-Calibrate-On-Start Flow:
 * - CMD_START_SESSION (0x01): Runs 3s stationary calibration -> sets Calibrated bit ->
 *                             sends Status notification -> sets Session Active bit ->
 *                             starts 100 Hz sampling and batched streaming.
 * - CMD_STOP_SESSION (0x02): Stops streaming, clears Session Active bit, sends Status ack.
 * - CMD_CALIBRATE (0x03): Runs standalone calibration, sends Status ack.
 * - CMD_PING (0x04): Sends immediate Status notification with ack = 0x04.
 */
void session_handle_command(uint8_t cmd);

/**
 * @brief Called every 10ms (100 Hz) during active session to sample IMU and stream batches.
 */
void session_sample_tick(void);

/**
 * @brief Handle BLE connection / disconnection transitions.
 */
void session_on_ble_connection_changed(bool connected);

/**
 * @brief Get current 8-bit status bitfield.
 */
uint8_t session_get_status_byte(void);

/**
 * @brief Get reference to current calibration data.
 */
const imu_calibration_t *session_get_calibration(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_SESSION_H_ */
