/*
 * src/drivers/imu.c
 *
 * Register-level I2C driver for LSM6DS3TR-C.
 *
 * Datasheet refs:
 *   AN5040  — LSM6DS3TR-C application note
 *   DM00341748 — register map
 *
 * Only the registers needed for phase 1 are listed; the full map lives in the
 * datasheet.  Every constant is named so the code is self-documenting.
 */

#include "imu.h"

#include <zephyr/kernel.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(imu, LOG_LEVEL_INF);

/* ===========================================================================
 * LSM6DS3TR-C register addresses
 * =========================================================================*/

/* Identity */
#define REG_WHO_AM_I         0x0F
#define WHO_AM_I_EXPECTED    0x6A   /* fixed value returned by the device */

/* Control registers */
#define REG_CTRL1_XL         0x10   /* Accelerometer control  */
#define REG_CTRL2_G          0x11   /* Gyroscope control      */
#define REG_CTRL3_C          0x12   /* Common control (SW_RST, BDU, …) */

/* Output registers — burst-readable starting at OUTX_L_G */
#define REG_OUTX_L_G         0x22   /* Gyro X low byte  (first in burst) */
#define REG_OUTX_L_XL        0x28   /* Accel X low byte */

/* Number of bytes for a full 6-axis burst (2 bytes × 3 axes × 2 sensors) */
#define IMU_BURST_BYTES      12

/* ===========================================================================
 * Register field values
 * =========================================================================*/

/*
 * CTRL1_XL — Accelerometer
 *   [7:4] ODR_XL   : 0100 = 104 Hz (high-performance)
 *   [3:2] FS_XL    : 10   = ±4 g
 *   [1]   LPF1_BW_SEL: 0
 *   [0]   reserved : 0
 *   → 0b 0100 1000 = 0x48
 */
#define CTRL1_XL_104HZ_4G    0x48

/*
 * CTRL2_G — Gyroscope
 *   [7:4] ODR_G    : 0100 = 104 Hz (high-performance)
 *   [3:1] FS_G     : 010  = ±500 °/s  (bit 3 is FS1, bit 2 is FS0, bit 1=0)
 *                    Actually: FS_G[2:0] at bits[3:1] — 500 dps = 010
 *   [0]   FS_125   : 0
 *   → 0b 0100 0100 = 0x44
 */
#define CTRL2_G_104HZ_500DPS 0x44

/*
 * CTRL3_C
 *   BDU  (bit 6) = 1 — Block Data Update: output registers not updated
 *                      between MSB and LSB reads.
 *   IF_INC (bit 2) = 1 — Auto-increment register address (enables burst).
 *   → 0b 0100 0100 = 0x44
 */
#define CTRL3_C_BDU_IF_INC   0x44

/* SW_RESET bit in CTRL3_C — pulse to reset all registers */
#define CTRL3_C_SW_RESET     0x01

/* ===========================================================================
 * Sensitivity constants  (from datasheet Table 3)
 *   Accelerometer: ±4 g  → 0.122 mg/LSB
 *   Gyroscope:    ±500°/s → 17.50 mdps/LSB
 * =========================================================================*/

/* Convert raw int16 accel count → m/s²
 *   raw * 0.122 mg/LSB  ×  9.80665 m/s²/g  ×  1e-3 g/mg  */
#define ACCEL_SENSITIVITY_MS2   (0.122f * 9.80665f * 0.001f)   /* ≈ 0.001197 */

/* Convert raw int16 gyro count → °/s
 *   raw * 17.50 m°/s/LSB × 1e-3 °/m°             */
#define GYRO_SENSITIVITY_DPS    (17.50f * 0.001f)               /* = 0.01750  */

/* ===========================================================================
 * Helper: single-byte register write
 * =========================================================================*/
static uint8_t active_i2c_addr = 0x6A;

static int reg_write(const struct device *dev, uint8_t reg, uint8_t val)
{
    uint8_t buf[2] = { reg, val };
    return i2c_write(dev, buf, sizeof(buf), active_i2c_addr);
}

static int reg_read_burst(const struct device *dev,
                           uint8_t reg, uint8_t *out, size_t len)
{
    return i2c_write_read(dev, active_i2c_addr, &reg, 1, out, len);
}

/* ===========================================================================
 * imu_init
 * =========================================================================*/
int imu_init(const struct device *i2c_dev)
{
    int ret;
    uint8_t who_am_i = 0;

    if (!device_is_ready(i2c_dev)) {
        LOG_ERR("I2C bus not ready");
        return -ENODEV;
    }

    /* -----------------------------------------------------------------
     * 1. Probe 0x6A and 0x6B for WHO_AM_I
     * ----------------------------------------------------------------*/
    active_i2c_addr = 0x6A;
    ret = reg_read_burst(i2c_dev, REG_WHO_AM_I, &who_am_i, 1);
    if (ret < 0 || who_am_i != WHO_AM_I_EXPECTED) {
        LOG_WRN("Probe at 0x6A failed (val=0x%02X, ret=%d), trying 0x6B...", who_am_i, ret);
        active_i2c_addr = 0x6B;
        ret = reg_read_burst(i2c_dev, REG_WHO_AM_I, &who_am_i, 1);
    }

    LOG_INF("LSM6DS3TR-C at 0x%02X WHO_AM_I = 0x%02X (expected 0x%02X)%s",
            active_i2c_addr, who_am_i, WHO_AM_I_EXPECTED,
            (who_am_i == WHO_AM_I_EXPECTED) ? "  [OK]" : "  [MISMATCH]");

    if (who_am_i != WHO_AM_I_EXPECTED) {
        LOG_ERR("IMU identity check failed at both 0x6A and 0x6B");
        return -ENODEV;
    }

    /* -----------------------------------------------------------------
     * 2. Software reset — bring device to known state
     * ----------------------------------------------------------------*/
    ret = reg_write(i2c_dev, REG_CTRL3_C, CTRL3_C_SW_RESET);
    if (ret < 0) {
        LOG_ERR("SW reset write failed: %d", ret);
        return ret;
    }
    k_msleep(5);

    /* -----------------------------------------------------------------
     * 3. Configure CTRL3_C first (BDU + auto-increment)
     * ----------------------------------------------------------------*/
    ret = reg_write(i2c_dev, REG_CTRL3_C, CTRL3_C_BDU_IF_INC);
    if (ret < 0) {
        LOG_ERR("CTRL3_C write failed: %d", ret);
        return ret;
    }

    /* -----------------------------------------------------------------
     * 4. Configure accelerometer: 104 Hz, ±4 g
     * ----------------------------------------------------------------*/
    ret = reg_write(i2c_dev, REG_CTRL1_XL, CTRL1_XL_104HZ_4G);
    if (ret < 0) {
        LOG_ERR("CTRL1_XL write failed: %d", ret);
        return ret;
    }

    /* -----------------------------------------------------------------
     * 5. Configure gyroscope: 104 Hz, ±500 °/s
     * ----------------------------------------------------------------*/
    ret = reg_write(i2c_dev, REG_CTRL2_G, CTRL2_G_104HZ_500DPS);
    if (ret < 0) {
        LOG_ERR("CTRL2_G write failed: %d", ret);
        return ret;
    }

    LOG_INF("IMU configured: accel=104Hz/±4g  gyro=104Hz/±500dps");
    return 0;
}

/* ===========================================================================
 * imu_read
 * =========================================================================*/
int imu_read(const struct device *i2c_dev, imu_sample_t *out)
{
    uint8_t  raw[IMU_BURST_BYTES];
    int16_t  gx_raw, gy_raw, gz_raw;
    int16_t  ax_raw, ay_raw, az_raw;
    int      ret;

    /*
     * Burst read layout (IF_INC=1 means auto-increment):
     *   Bytes  0- 1: OUTX_L_G / OUTX_H_G   — gyro X
     *   Bytes  2- 3: OUTY_L_G / OUTY_H_G   — gyro Y
     *   Bytes  4- 5: OUTZ_L_G / OUTZ_H_G   — gyro Z
     *   Bytes  6- 7: OUTX_L_XL / OUTX_H_XL — accel X
     *   Bytes  8- 9: OUTY_L_XL / OUTY_H_XL — accel Y
     *   Bytes 10-11: OUTZ_L_XL / OUTZ_H_XL — accel Z
     *
     * We start the burst at REG_OUTX_L_G (0x22) which covers both blocks
     * contiguously through to 0x2D.
     */
    ret = reg_read_burst(i2c_dev, REG_OUTX_L_G, raw, IMU_BURST_BYTES);
    if (ret < 0) {
        LOG_ERR("IMU burst read failed: %d", ret);
        return ret;
    }

    /* Reconstruct signed 16-bit values (little-endian on device) */
    gx_raw = (int16_t)((uint16_t)raw[1]  << 8 | raw[0]);
    gy_raw = (int16_t)((uint16_t)raw[3]  << 8 | raw[2]);
    gz_raw = (int16_t)((uint16_t)raw[5]  << 8 | raw[4]);
    ax_raw = (int16_t)((uint16_t)raw[7]  << 8 | raw[6]);
    ay_raw = (int16_t)((uint16_t)raw[9]  << 8 | raw[8]);
    az_raw = (int16_t)((uint16_t)raw[11] << 8 | raw[10]);

    /* Convert to physical units */
    out->ax_ms2 = ax_raw * ACCEL_SENSITIVITY_MS2;
    out->ay_ms2 = ay_raw * ACCEL_SENSITIVITY_MS2;
    out->az_ms2 = az_raw * ACCEL_SENSITIVITY_MS2;
    out->gx_dps = gx_raw * GYRO_SENSITIVITY_DPS;
    out->gy_dps = gy_raw * GYRO_SENSITIVITY_DPS;
    out->gz_dps = gz_raw * GYRO_SENSITIVITY_DPS;

    return 0;
}
