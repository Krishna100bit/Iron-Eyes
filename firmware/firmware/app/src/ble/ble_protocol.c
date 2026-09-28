#include "ble_protocol.h"
#include <string.h>

uint8_t ble_crc8_maxim(const uint8_t *data, uint16_t len)
{
    uint8_t crc = 0x00;
    for (uint16_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (uint8_t j = 0; j < 8; j++) {
            if (crc & 0x01) {
                crc = (crc >> 1) ^ 0x8C;
            } else {
                crc >>= 1;
            }
        }
    }
    return crc;
}

void ble_protocol_encode_stream_packet(ble_stream_packet_t *pkt)
{
    if (!pkt) return;

    pkt->protocol_version = BLE_PROTOCOL_VERSION;
    pkt->packet_type = BLE_PACKET_TYPE_IMU_BATCH;
    pkt->sample_count = BLE_SAMPLES_PER_BATCH;

    /* Compute CRC-8 over all bytes except the trailing crc8 field */
    uint16_t payload_len = sizeof(ble_stream_packet_t) - 1;
    pkt->crc8 = ble_crc8_maxim((const uint8_t *)pkt, payload_len);
}
