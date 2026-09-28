/*
 * src/sensor/fifo.c
 *
 * Implementation of IMU batching buffer.
 */

#include "fifo.h"
#include <string.h>

#define ACCEL_SCALE_FACTOR  1000.0f  /* m/s² -> int16 (× 1000) */
#define GYRO_SCALE_FACTOR   100.0f   /* °/s  -> int16 (× 100)  */

static inline int16_t clamp_i16(float v)
{
    if (v > 32767.0f)  return 32767;
    if (v < -32768.0f) return -32768;
    return (int16_t)v;
}

void imu_fifo_init(imu_fifo_t *fifo)
{
    if (fifo) {
        memset(fifo, 0, sizeof(*fifo));
    }
}

void imu_fifo_reset(imu_fifo_t *fifo)
{
    if (fifo) {
        fifo->count = 0;
        fifo->base_ts_ms = 0;
    }
}

bool imu_fifo_push(imu_fifo_t *fifo,
                   const imu_sample_t *s,
                   uint32_t ts_ms,
                   imu_batch_t *out_batch)
{
    if (!fifo || !s) {
        return false;
    }

    if (fifo->count == 0) {
        fifo->base_ts_ms = ts_ms;
        fifo->current_batch.base_timestamp_ms = ts_ms;
        fifo->current_batch.count = 0;
    }

    uint32_t dt = ts_ms - fifo->base_ts_ms;
    if (dt > 255) {
        dt = 255; /* clamp to uint8 max */
    }

    imu_batched_sample_t *dst = &fifo->current_batch.samples[fifo->count];
    dst->ax = clamp_i16(s->ax_ms2 * ACCEL_SCALE_FACTOR);
    dst->ay = clamp_i16(s->ay_ms2 * ACCEL_SCALE_FACTOR);
    dst->az = clamp_i16(s->az_ms2 * ACCEL_SCALE_FACTOR);
    dst->gx = clamp_i16(s->gx_dps * GYRO_SCALE_FACTOR);
    dst->gy = clamp_i16(s->gy_dps * GYRO_SCALE_FACTOR);
    dst->gz = clamp_i16(s->gz_dps * GYRO_SCALE_FACTOR);
    dst->dt_ms = (uint8_t)dt;

    fifo->count++;
    fifo->current_batch.count = fifo->count;

    if (fifo->count >= SAMPLES_PER_BATCH) {
        if (out_batch) {
            memcpy(out_batch, &fifo->current_batch, sizeof(imu_batch_t));
        }
        fifo->count = 0;
        return true;
    }

    return false;
}
