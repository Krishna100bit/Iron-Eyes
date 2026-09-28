/*
 * src/sensor/fifo.h
 *
 * IMU sample batching buffer (Stage 6 — FIFO Batching).
 *
 * Collects SAMPLES_PER_BATCH (5) IMU samples before signaling that a
 * complete notification payload is ready to transmit over BLE.
 */

#ifndef IRONLOOP_SENSOR_FIFO_H
#define IRONLOOP_SENSOR_FIFO_H

#include <stdint.h>
#include <stdbool.h>
#include "../drivers/imu.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SAMPLES_PER_BATCH  5

/* Single sample in fixed-point representation */
typedef struct {
    int16_t ax;     /* m/s² * 1000 */
    int16_t ay;
    int16_t az;
    int16_t gx;     /* °/s  * 100  */
    int16_t gy;
    int16_t gz;
    uint8_t dt_ms;  /* Delta time in ms since base_timestamp_ms */
} imu_batched_sample_t;

/* A complete batch ready for packetization */
typedef struct {
    uint32_t             base_timestamp_ms;
    uint8_t              count;
    imu_batched_sample_t samples[SAMPLES_PER_BATCH];
} imu_batch_t;

/* FIFO accumulator state */
typedef struct {
    uint32_t    base_ts_ms;
    uint8_t     count;
    imu_batch_t current_batch;
} imu_fifo_t;

/**
 * @brief Initialize the IMU batch FIFO.
 */
void imu_fifo_init(imu_fifo_t *fifo);

/**
 * @brief Push one physical sample into the FIFO.
 *
 * Converts floating point sample into scaled int16, calculates dt_ms relative
 * to the first sample in the batch, and adds it to the accumulator.
 *
 * @param fifo      Pointer to FIFO structure.
 * @param s         Pointer to physical-unit IMU sample.
 * @param ts_ms     Current timestamp in milliseconds.
 * @param out_batch Filled with complete batch when return value is true.
 * @return true when a complete batch of SAMPLES_PER_BATCH is ready.
 */
bool imu_fifo_push(imu_fifo_t *fifo,
                   const imu_sample_t *s,
                   uint32_t ts_ms,
                   imu_batch_t *out_batch);

/**
 * @brief Reset/clear the FIFO accumulator.
 */
void imu_fifo_reset(imu_fifo_t *fifo);

#ifdef __cplusplus
}
#endif
#endif /* IRONLOOP_SENSOR_FIFO_H */
