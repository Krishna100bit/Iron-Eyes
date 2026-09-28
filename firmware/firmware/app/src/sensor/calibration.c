/*
 * src/sensor/calibration.c
 *
 * IMU calibration implementation.
 */

#include "calibration.h"
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <string.h>

LOG_MODULE_REGISTER(calibration, LOG_LEVEL_INF);

#define CALIBRATION_SAMPLE_COUNT  300  /* 3.0 seconds at 100 Hz */

void imu_calibration_init(imu_calibration_t *cal)
{
    if (cal) {
        memset(cal, 0, sizeof(*cal));
        cal->is_calibrated = false;
    }
}

int imu_calibration_run(const struct device *i2c_dev, imu_calibration_t *cal)
{
    if (!i2c_dev || !cal) {
        return -EINVAL;
    }

    LOG_INF("Starting 3-second stationary calibration (300 samples)...");
    LOG_INF("KEEP DEVICE COMPLETELY STILL!");

    float sum_ax = 0.0f, sum_ay = 0.0f, sum_az = 0.0f;
    float sum_gx = 0.0f, sum_gy = 0.0f, sum_gz = 0.0f;
    int valid_count = 0;

    for (int i = 0; i < CALIBRATION_SAMPLE_COUNT; i++) {
        imu_sample_t s;
        int ret = imu_read(i2c_dev, &s);
        if (ret == 0) {
            sum_ax += s.ax_ms2;
            sum_ay += s.ay_ms2;
            sum_az += s.az_ms2;
            sum_gx += s.gx_dps;
            sum_gy += s.gy_dps;
            sum_gz += s.gz_dps;
            valid_count++;
        }
        k_msleep(10);
    }

    if (valid_count < 50) {
        LOG_ERR("Calibration failed: only %d valid samples", valid_count);
        return -EIO;
    }

    cal->gyro_bias_dps[0] = sum_gx / (float)valid_count;
    cal->gyro_bias_dps[1] = sum_gy / (float)valid_count;
    cal->gyro_bias_dps[2] = sum_gz / (float)valid_count;

    cal->accel_gravity_ms2[0] = sum_ax / (float)valid_count;
    cal->accel_gravity_ms2[1] = sum_ay / (float)valid_count;
    cal->accel_gravity_ms2[2] = sum_az / (float)valid_count;

    cal->is_calibrated = true;

    LOG_INF("Calibration SUCCESS (%d samples):", valid_count);
    LOG_INF("  Gyro bias (deg/s): gx=%.3f, gy=%.3f, gz=%.3f",
            (double)cal->gyro_bias_dps[0], (double)cal->gyro_bias_dps[1], (double)cal->gyro_bias_dps[2]);
    LOG_INF("  Gravity vector (m/s2): ax=%.3f, ay=%.3f, az=%.3f",
            (double)cal->accel_gravity_ms2[0], (double)cal->accel_gravity_ms2[1], (double)cal->accel_gravity_ms2[2]);

    return 0;
}

void imu_calibration_apply(const imu_calibration_t *cal, imu_sample_t *s)
{
    if (cal && cal->is_calibrated && s) {
        s->gx_dps -= cal->gyro_bias_dps[0];
        s->gy_dps -= cal->gyro_bias_dps[1];
        s->gz_dps -= cal->gyro_bias_dps[2];
    }
}
