/*
 * src/drivers/imu.h
 *
 * Register-level I2C driver for the LSM6DS3TR-C 6-axis IMU.
 *
 * Public API used by main.c / ble_service.c.
 */

#ifndef IRONLOOP_IMU_H
#define IRONLOOP_IMU_H

#include <stdint.h>
#include <stdbool.h>
#include <zephyr/device.h>

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------------
 * Configuration knobs (change here or via prj.conf in a later phase)
 * -------------------------------------------------------------------------*/

/*
 * I2C address: 0x6A (SDO=GND, factory default on Seeed Sense)
 *              0x6B (SDO=VCC)
 * Must match boards/xiao_ble.overlay reg property.
 */
#define IMU_I2C_ADDR   0x6A

/* -------------------------------------------------------------------------
 * One raw sample — floating-point for readability in phase 1.
 * Phase 2 will switch to fixed-point int16 throughout the pipeline.
 * -------------------------------------------------------------------------*/
typedef struct {
    float ax_ms2;   /* acceleration X, m/s²  */
    float ay_ms2;   /* acceleration Y, m/s²  */
    float az_ms2;   /* acceleration Z, m/s²  */
    float gx_dps;   /* angular rate X, °/s   */
    float gy_dps;   /* angular rate Y, °/s   */
    float gz_dps;   /* angular rate Z, °/s   */
} imu_sample_t;

/* -------------------------------------------------------------------------
 * Public functions
 * -------------------------------------------------------------------------*/

/**
 * @brief  Initialise the IMU.
 *
 * - Verifies WHO_AM_I register.
 * - Configures accelerometer : ±4 g  at ~104 Hz ODR.
 * - Configures gyroscope     : ±500 °/s at ~104 Hz ODR.
 * - Enables block-data-update (BDU) so reads are consistent.
 *
 * @param  i2c_dev  Pointer to the I2C bus device obtained from DT.
 * @return 0 on success, negative errno on failure.
 */
int imu_init(const struct device *i2c_dev);

/**
 * @brief  Read one sample from the IMU output registers.
 *
 * Performs a burst read of all 12 output bytes, converts raw counts to
 * physical units, and fills @p out.
 *
 * @param  i2c_dev  Pointer to the same I2C bus device passed to imu_init().
 * @param  out      Pointer to caller-allocated imu_sample_t.
 * @return 0 on success, negative errno on failure.
 */
int imu_read(const struct device *i2c_dev, imu_sample_t *out);

#ifdef __cplusplus
}
#endif
#endif /* IRONLOOP_IMU_H */
