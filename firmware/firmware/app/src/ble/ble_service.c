/*
 * src/ble/ble_service.c
 *
 * BLE GATT Service implementation for IronLoop.
 *
 * Service UUID: 4fafc201-1fb5-459e-8fcc-c5c9c331914b
 *
 * Characteristics:
 *   1. Stream  (Notify)       — beb5483e-... — 78-byte batched IMU data
 *   2. Command (Write/WwoR)   — beb5483f-... — 1-byte command
 *   3. Status  (Notify+Read)  — beb54840-... — 4-byte status
 *
 * Features:
 *   - Auto-restarts advertising after disconnect
 *   - Notifies session_lite when stream is subscribed/unsubscribed
 */

#include "ble_service.h"
#include <zephyr/kernel.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(ble_service, LOG_LEVEL_INF);

static struct bt_uuid_128 service_uuid = BT_UUID_INIT_128(IRONLOOP_SERVICE_UUID);
static struct bt_uuid_128 stream_uuid  = BT_UUID_INIT_128(IRONLOOP_STREAM_CHAR_UUID);
static struct bt_uuid_128 cmd_uuid     = BT_UUID_INIT_128(IRONLOOP_CMD_CHAR_UUID);
static struct bt_uuid_128 status_uuid  = BT_UUID_INIT_128(IRONLOOP_STATUS_CHAR_UUID);

static struct bt_conn *current_conn = NULL;
static bool stream_notify_enabled = false;
static bool status_notify_enabled = false;
static ble_status_packet_t cached_status = {0};

static ble_command_handler_t app_cmd_handler = NULL;
static ble_connection_state_cb_t app_conn_cb = NULL;
static ble_stream_subscribe_cb_t app_stream_cb = NULL;

/* Forward declaration for re-advertising */
static int start_advertising(void);

/* ── CCCD Callbacks ──────────────────────────────────────────────────────── */
static void stream_ccc_cfg_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
    bool was_enabled = stream_notify_enabled;
    stream_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
    LOG_INF("Stream CCCD changed: %s", stream_notify_enabled ? "NOTIFY ENABLED" : "DISABLED");

    /* Notify the session manager about subscription change */
    if (app_stream_cb && (stream_notify_enabled != was_enabled)) {
        app_stream_cb(stream_notify_enabled);
    }
}

static void status_ccc_cfg_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
    status_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
    LOG_INF("Status CCCD changed: %s", status_notify_enabled ? "NOTIFY ENABLED" : "DISABLED");
}

/* ── Command Write Callback ──────────────────────────────────────────────── */
static ssize_t write_command(struct bt_conn *conn,
                             const struct bt_gatt_attr *attr,
                             const void *buf, uint16_t len,
                             uint16_t offset, uint8_t flags)
{
    if (len < 1) {
        return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
    }

    uint8_t cmd = ((const uint8_t *)buf)[0];
    LOG_INF("BLE Command received: 0x%02X", cmd);

    if (app_cmd_handler) {
        app_cmd_handler(cmd);
    }

    return len;
}

/* ── Status Read Callback ────────────────────────────────────────────────── */
static ssize_t read_status(struct bt_conn *conn,
                           const struct bt_gatt_attr *attr,
                           void *buf, uint16_t len,
                           uint16_t offset)
{
    return bt_gatt_attr_read(conn, attr, buf, len, offset, &cached_status, sizeof(cached_status));
}

/* ── GATT Service Declaration ────────────────────────────────────────────── */
/*
 * Attribute table layout (for bt_gatt_notify index references):
 *
 *  Index  Attribute
 *  -----  --------------------------------
 *    0    Primary Service Declaration
 *    1    Stream Char Declaration
 *    2    Stream Char Value            ← bt_gatt_notify target for stream
 *    3    Stream CCCD
 *    4    Command Char Declaration
 *    5    Command Char Value
 *    6    Status Char Declaration
 *    7    Status Char Value            ← bt_gatt_notify target for status
 *    8    Status CCCD
 */
BT_GATT_SERVICE_DEFINE(ironloop_svc,
    BT_GATT_PRIMARY_SERVICE(&service_uuid),

    /* 1. Stream Characteristic (Notify) — Index 1,2,3 */
    BT_GATT_CHARACTERISTIC(&stream_uuid.uuid,
                           BT_GATT_CHRC_NOTIFY,
                           BT_GATT_PERM_NONE,
                           NULL, NULL, NULL),
    BT_GATT_CCC(stream_ccc_cfg_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),

    /* 2. Command Characteristic (Write) — Index 4,5 */
    BT_GATT_CHARACTERISTIC(&cmd_uuid.uuid,
                           BT_GATT_CHRC_WRITE | BT_GATT_CHRC_WRITE_WITHOUT_RESP,
                           BT_GATT_PERM_WRITE,
                           NULL, write_command, NULL),

    /* 3. Status Characteristic (Notify + Read) — Index 6,7,8 */
    BT_GATT_CHARACTERISTIC(&status_uuid.uuid,
                           BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
                           BT_GATT_PERM_READ,
                           read_status, NULL, &cached_status),
    BT_GATT_CCC(status_ccc_cfg_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
);

/* ── GAP Advertising Data ────────────────────────────────────────────────── */
static const struct bt_data ad[] = {
    BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
    BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME, sizeof(CONFIG_BT_DEVICE_NAME) - 1),
};

static const struct bt_data sd[] = {
    BT_DATA_BYTES(BT_DATA_UUID128_ALL, IRONLOOP_SERVICE_UUID),
};

static int start_advertising(void)
{
    int err = bt_le_adv_start(BT_LE_ADV_CONN_FAST_1, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));
    if (err) {
        LOG_ERR("Advertising start failed (err %d)", err);
    } else {
        LOG_INF("Advertising as '%s' started", CONFIG_BT_DEVICE_NAME);
    }
    return err;
}

/* ── Connection Callbacks ────────────────────────────────────────────────── */
static void connected(struct bt_conn *conn, uint8_t err)
{
    if (err) {
        LOG_ERR("BLE Connection failed (err 0x%02X)", err);
        /* Re-advertise even on failed connection */
        start_advertising();
        return;
    }

    current_conn = bt_conn_ref(conn);
    LOG_INF("BLE Central Connected [OK]");

    if (app_conn_cb) {
        app_conn_cb(true);
    }
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
    LOG_INF("BLE Central Disconnected (reason 0x%02X)", reason);

    if (current_conn) {
        bt_conn_unref(current_conn);
        current_conn = NULL;
    }

    stream_notify_enabled = false;
    status_notify_enabled = false;

    if (app_conn_cb) {
        app_conn_cb(false);
    }

    /* Auto-restart advertising so the device is always discoverable */
    LOG_INF("Re-starting advertising...");
    start_advertising();
}

BT_CONN_CB_DEFINE(conn_callbacks) = {
    .connected    = connected,
    .disconnected = disconnected,
};

int ble_service_init(ble_command_handler_t cmd_handler,
                     ble_connection_state_cb_t conn_cb,
                     ble_stream_subscribe_cb_t stream_cb)
{
    int err;
    app_cmd_handler = cmd_handler;
    app_conn_cb = conn_cb;
    app_stream_cb = stream_cb;

    err = bt_enable(NULL);
    if (err) {
        LOG_ERR("Bluetooth init failed (err %d)", err);
        return err;
    }

    LOG_INF("Bluetooth initialized successfully");

    err = start_advertising();
    return err;
}

bool ble_service_is_connected(void)
{
    return (current_conn != NULL);
}

bool ble_service_is_stream_subscribed(void)
{
    return stream_notify_enabled;
}

int ble_service_notify_stream(const ble_stream_packet_t *pkt)
{
    if (!current_conn || !stream_notify_enabled) {
        return -EACCES;
    }

    /* Stream characteristic value attribute is at index 2 in service definition */
    return bt_gatt_notify(current_conn, &ironloop_svc.attrs[2], pkt, sizeof(ble_stream_packet_t));
}

int ble_service_notify_status(const ble_status_packet_t *status)
{
    if (status) {
        cached_status = *status;
    }

    if (!current_conn || !status_notify_enabled) {
        return 0;
    }

    /* Status characteristic value attribute is at index 7 in service definition */
    return bt_gatt_notify(current_conn, &ironloop_svc.attrs[7], &cached_status, sizeof(ble_status_packet_t));
}
