#ifndef DRIVERS_BATTERY_H_
#define DRIVERS_BATTERY_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * 300mAh Single-Cell LiPo Battery Monitoring (Seeed XIAO nRF52840 Sense):
 *
 * Hardware Design & Routing:
 * - Read pin: AIN7 (P0.31) on nRF52840 SAADC.
 * - Divider Enable Pin: P0.14 (Active LOW). Driving P0.14 LOW connects the divider to GND.
 * - Resistor divider: R1 = 1M, R2 = 510k.
 *   Multiplier: (R1 + R2) / R2 = (1000 + 510) / 510 ≈ 2.961.
 *
 * Hardware-Level Charging Note:
 * - Onboard charge IC operates independently in hardware. LiPo charging proceeds normally
 *   whether the MCU is awake, streaming, or in System OFF sleep mode.
 * - Charge state detection (/CHG pin) is NOT routed to an MCU GPIO on this board revision;
 *   charging is managed autonomously in hardware by the charge IC and indicated via the board's CHG LED.
 */
#define BATTERY_DIVIDER_NUMERATOR     2961
#define BATTERY_DIVIDER_DENOMINATOR   1000

#define BATTERY_SMOOTHING_WINDOW      6     /* Rolling average of last 6 readings (~30s window) */
#define BATTERY_SAMPLE_INTERVAL_SEC   5     /* Sample ADC once every 5 seconds */

#define BATTERY_LOW_THRESHOLD_MV      3400  /* Low battery warning (starts high-priority red LED overlay) */
#define BATTERY_CRITICAL_THRESHOLD_MV 3200  /* Critical cutoff (gracefully stops session and enters System OFF sleep) */
#define BATTERY_FULL_THRESHOLD_MV     4200  /* Nominal 100% full charge */

/**
 * @brief Initialize battery ADC channel, divider control pin, and prime rolling filter.
 * @return 0 on success, negative error code on failure.
 */
int battery_init(void);

/**
 * @brief Read the current smoothed battery voltage in millivolts.
 * @return Battery voltage in mV (e.g. 3850 mV).
 */
uint16_t battery_read_mv(void);

/**
 * @brief Sample raw ADC, push into rolling window, and compute updated smoothed voltage.
 * @return Latest smoothed battery voltage in mV.
 */
uint16_t battery_sample_tick(void);

/**
 * @brief Check if battery is below the low-battery warning threshold (< 3400 mV).
 * @return true if low, false otherwise.
 */
bool battery_is_low(void);

/**
 * @brief Check if battery is at or below critical shutdown threshold (<= 3200 mV).
 * @return true if critical, false otherwise.
 */
bool battery_is_critical(void);

#ifdef __cplusplus
}
#endif

#endif /* DRIVERS_BATTERY_H_ */
