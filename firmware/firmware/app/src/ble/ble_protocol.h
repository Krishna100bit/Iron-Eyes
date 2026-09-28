#ifndef BLE_BLE_PROTOCOL_H_
#define BLE_BLE_PROTOCOL_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BLE_PROTOCOL_VERSION        1
#define BLE_PACKET_TYPE_IMU_BATCH   1
#define BLE_SAMPLES_PER_BATCH       5

/* Commands (Write to Command Characteristic) */
#define CMD_START_SESSION           0x01
#define CMD_STOP_SESSION            0x02
#define CMD_CALIBRATE               0x03
#define CMD_PING                    0x04

/* Status Bitfield Flags */
#define STATUS_FLAG_CALIBRATED      (1 << 0)
#define STATUS_FLAG_LOW_BATT        (1 << 1)
#define STATUS_FLAG_SESSION_ACTIVE  (1 << 2)
#define STATUS_FLAG_SENSOR_FAULT    (1 << 3)

#pragma pack(push, 1)

typedef struct {
    int16_t ax;    /* Scale /1000 = m/s² */
    int16_t ay;
    int16_t az;
    int16_t gx;    /* Scale /100 = deg/s */
    int16_t gy;
    int16_t gz;
    uint8_t dt_ms; /* Milliseconds offset from base_timestamp_ms */
} ble_imu_sample_t;

typedef struct {
    /* 12-Byte Header */
    uint8_t  protocol_version;
    uint8_t  packet_type;
    uint16_t sequence_number;
    uint32_t base_timestamp_ms;
    uint8_t  sample_count;
    uint8_t  device_status;
    uint16_t battery_mv;

    /* 65-Byte Payload (5 samples x 13 bytes) */
    ble_imu_sample_t samples[BLE_SAMPLES_PER_BATCH];

    /* 1-Byte Footer */
    uint8_t  crc8;
} ble_stream_packet_t;

typedef struct {
    uint8_t  device_status;
    uint16_t battery_mv;
    uint8_t  last_command_ack;
} ble_status_packet_t;

#pragma pack(pop)

#define BLE_STREAM_PACKET_SIZE  sizeof(ble_stream_packet_t) /* Exactly 78 bytes */
#define BLE_STATUS_PACKET_SIZE  sizeof(ble_status_packet_t) /* Exactly 4 bytes */

/**
 * @brief Calculate CRC-8/MAXIM (1-Wire) over a byte buffer.
 */
uint8_t ble_crc8_maxim(const uint8_t *data, uint16_t len);

/**
 * @brief Finalize and encode a batched stream packet (computes CRC-8).
 */
void ble_protocol_encode_stream_packet(ble_stream_packet_t *pkt);

#ifdef __cplusplus
}
#endif

#endif /* BLE_BLE_PROTOCOL_H_ */
