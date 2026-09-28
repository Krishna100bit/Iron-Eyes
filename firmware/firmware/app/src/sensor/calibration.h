/*
 * src/sensor/calibration.h
 *
 * IMU stationary calibration routine (Stage 4).
 */

#ifndef IRONLOOP_SENSOR_CALIBRATION_H
#define IRONLOOP_SENSOR_CALIBRATION_H

#include <stdint.h>
#include <stdbool.h>
#include <zephyr/device.h>
#include "../drivers/imu.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool  is_calibrated;
    float gyro_bias_dps[3];    /* gx, gy, gz bias in deg/s */
    float accel_gravity_ms2[3];/* ax, ay, az gravity vector at rest */
} imu_calibration_t;

/**
 * @brief Initialize calibration state.
 */
void imu_calibration_init(imu_calibration_t *cal);

/**
 * @brief Perform a 3-second stationary calibration.
 *
 * Must be called with the device sitting completely still.
 *
 * @param i2c_dev  Pointer to I2C bus device.
 * @param cal      Output calibration structure.
 * @return 0 on success, negative errno on failure.
 */
int imu_calibration_run(const struct device *i2c_dev, imu_calibration_t *cal);

/**
 * @brief Apply calibration (gyro bias subtraction) to a sample.
 */
void imu_calibration_apply(const imu_calibration_t *cal, imu_sample_t *s);

#ifdef __cplusplus
}
#endif
#endif /* IRONLOOP_SENSOR_CALIBRATION_H */
