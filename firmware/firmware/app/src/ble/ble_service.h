#ifndef BLE_BLE_SERVICE_H_
#define BLE_BLE_SERVICE_H_

#include <stdint.h>
#include <stdbool.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/gatt.h>
#include "ble_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

/* IronLoop GATT Service: 4fafc201-1fb5-459e-8fcc-c5c9c331914b */
#define IRONLOOP_SERVICE_UUID \
    BT_UUID_128_ENCODE(0x4fafc201, 0x1fb5, 0x459e, 0x8fcc, 0xc5c9c331914b)

/* Stream Characteristic (Notify): beb5483e-36e1-4688-b7f5-ea07361b26a8 */
#define IRONLOOP_STREAM_CHAR_UUID \
    BT_UUID_128_ENCODE(0xbeb5483e, 0x36e1, 0x4688, 0xb7f5, 0xea07361b26a8)

/* Command Characteristic (Write): beb5483f-36e1-4688-b7f5-ea07361b26a8 */
#define IRONLOOP_CMD_CHAR_UUID \
    BT_UUID_128_ENCODE(0xbeb5483f, 0x36e1, 0x4688, 0xb7f5, 0xea07361b26a8)

/* Status Characteristic (Notify + Read): beb54840-36e1-4688-b7f5-ea07361b26a8 */
#define IRONLOOP_STATUS_CHAR_UUID \
    BT_UUID_128_ENCODE(0xbeb54840, 0x36e1, 0x4688, 0xb7f5, 0xea07361b26a8)

/* Callback types */
typedef void (*ble_command_handler_t)(uint8_t cmd);
typedef void (*ble_connection_state_cb_t)(bool connected);
typedef void (*ble_stream_subscribe_cb_t)(bool subscribed);

/**
 * @brief Initialize BLE stack, register GATT service, and start advertising.
 *
 * @param cmd_handler  Called when a command byte is written to CMD characteristic.
 * @param conn_cb      Called on BLE connect/disconnect events.
 * @param stream_cb    Called when central subscribes/unsubscribes to Stream CCCD.
 */
int ble_service_init(ble_command_handler_t cmd_handler,
                     ble_connection_state_cb_t conn_cb,
                     ble_stream_subscribe_cb_t stream_cb);

/**
 * @brief Check if a central is connected.
 */
bool ble_service_is_connected(void);

/**
 * @brief Check if stream notifications are subscribed.
 */
bool ble_service_is_stream_subscribed(void);

/**
 * @brief Send a batched IMU notification to connected central.
 */
int ble_service_notify_stream(const ble_stream_packet_t *pkt);

/**
 * @brief Send a status update notification.
 */
int ble_service_notify_status(const ble_status_packet_t *status);

#ifdef __cplusplus
}
#endif

#endif /* BLE_BLE_SERVICE_H_ */
