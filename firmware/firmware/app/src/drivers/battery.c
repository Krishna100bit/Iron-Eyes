#include "battery.h"
#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/adc.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(battery, LOG_LEVEL_INF);

/* ADC SAADC Channel 7 corresponds to AIN7 (P0.31) on nRF52840 */
#define ADC_NODE            DT_NODELABEL(adc)
#define ADC_CHANNEL_ID      7
#define ADC_RESOLUTION      12
#define ADC_GAIN            ADC_GAIN_1_6
#define ADC_REFERENCE       ADC_REF_INTERNAL
#define ADC_ACQUISITION_TIME ADC_ACQ_TIME_DEFAULT

/* Divider enable pin on XIAO BLE: P0.14 */
#define VBAT_ENABLE_PORT_NODE DT_NODELABEL(gpio0)
#define VBAT_ENABLE_PIN       14

static const struct device *adc_dev = DEVICE_DT_GET(ADC_NODE);
static const struct device *gpio0_dev = DEVICE_DT_GET(VBAT_ENABLE_PORT_NODE);

static int16_t sample_buffer;
static uint16_t cached_battery_mv = 3850; /* Smoothed LiPo voltage */
static bool is_initialized = false;

/* Rolling average buffer for smoothing load sags and radio TX bursts */
static uint16_t history_buffer[BATTERY_SMOOTHING_WINDOW];
static uint8_t history_index = 0;
static uint8_t history_count = 0;

static struct adc_channel_cfg channel_cfg = {
    .gain = ADC_GAIN,
    .reference = ADC_REFERENCE,
    .acquisition_time = ADC_ACQUISITION_TIME,
    .channel_id = ADC_CHANNEL_ID,
#if defined(CONFIG_ADC_NRFX_SAADC)
    .input_positive = SAADC_CH_PSELP_PSELP_AnalogInput7,
#endif
};

static struct adc_sequence sequence = {
    .channels = BIT(ADC_CHANNEL_ID),
    .buffer = &sample_buffer,
    .buffer_size = sizeof(sample_buffer),
    .resolution = ADC_RESOLUTION,
};

static uint16_t read_instantaneous_adc_mv(void)
{
    if (!is_initialized || !adc_dev) {
        return cached_battery_mv;
    }

    /* Momentarily enable resistor divider (Active LOW) */
    if (device_is_ready(gpio0_dev)) {
        gpio_pin_set(gpio0_dev, VBAT_ENABLE_PIN, 0);
        k_busy_wait(10); /* Brief stabilization */
    }

    int ret = adc_read(adc_dev, &sequence);

    /* Disable divider to minimize quiescent current drain */
    if (device_is_ready(gpio0_dev)) {
        gpio_pin_set(gpio0_dev, VBAT_ENABLE_PIN, 1);
    }

    if (ret < 0) {
        LOG_WRN("ADC read failed (%d), using cached %u mV", ret, cached_battery_mv);
        return cached_battery_mv;
    }

    int32_t raw_val = sample_buffer;
    if (raw_val < 0) {
        raw_val = 0;
    }

    /* Convert 12-bit ADC code to pin voltage (internal 0.6V ref with 1/6 gain = 3.6V range) */
    int32_t pin_mv = (raw_val * 3600) / (1 << ADC_RESOLUTION);

    /* Apply resistor divider ratio */
    int32_t batt_mv = (pin_mv * BATTERY_DIVIDER_NUMERATOR) / BATTERY_DIVIDER_DENOMINATOR;

    /* Clamp to plausible single-cell LiPo bounds (2.8V - 4.35V) */
    if (batt_mv < 2500) {
        batt_mv = 3700;
    } else if (batt_mv > 4350) {
        batt_mv = 4200;
    }

    return (uint16_t)batt_mv;
}

static uint16_t compute_smoothed_average(uint16_t new_sample)
{
    history_buffer[history_index] = new_sample;
    history_index = (history_index + 1) % BATTERY_SMOOTHING_WINDOW;
    if (history_count < BATTERY_SMOOTHING_WINDOW) {
        history_count++;
    }

    uint32_t sum = 0;
    for (uint8_t i = 0; i < history_count; i++) {
        sum += history_buffer[i];
    }

    return (uint16_t)(sum / history_count);
}

int battery_init(void)
{
    int ret;

    /* Configure divider enable pin P0.14 (Active LOW) */
    if (device_is_ready(gpio0_dev)) {
        ret = gpio_pin_configure(gpio0_dev, VBAT_ENABLE_PIN, GPIO_OUTPUT_INACTIVE);
        if (ret < 0) {
            LOG_WRN("Failed to configure VBAT enable pin: %d", ret);
        }
    }

    if (!device_is_ready(adc_dev)) {
        LOG_WRN("ADC device not ready, using nominal battery readings");
        is_initialized = false;
        return -ENODEV;
    }

    ret = adc_channel_setup(adc_dev, &channel_cfg);
    if (ret < 0) {
        LOG_ERR("ADC channel setup failed: %d", ret);
        return ret;
    }

    is_initialized = true;

    /* Prime rolling average buffer with initial readings */
    uint16_t initial_raw = read_instantaneous_adc_mv();
    for (int i = 0; i < BATTERY_SMOOTHING_WINDOW; i++) {
        history_buffer[i] = initial_raw;
    }
    history_count = BATTERY_SMOOTHING_WINDOW;
    history_index = 0;
    cached_battery_mv = initial_raw;

    LOG_INF("Battery monitor online: %u mV (smoothed over %d samples)", cached_battery_mv, BATTERY_SMOOTHING_WINDOW);
    return 0;
}

uint16_t battery_sample_tick(void)
{
    uint16_t raw_mv = read_instantaneous_adc_mv();
    cached_battery_mv = compute_smoothed_average(raw_mv);

    if (battery_is_critical()) {
        LOG_ERR("BATTERY CRITICAL: %u mV (cutoff <= %u mV)", cached_battery_mv, BATTERY_CRITICAL_THRESHOLD_MV);
    } else if (battery_is_low()) {
        LOG_WRN("BATTERY LOW: %u mV (warning < %u mV)", cached_battery_mv, BATTERY_LOW_THRESHOLD_MV);
    } else {
        LOG_DBG("Battery reading: %u mV (raw %u mV)", cached_battery_mv, raw_mv);
    }

    return cached_battery_mv;
}

uint16_t battery_read_mv(void)
{
    return cached_battery_mv;
}

bool battery_is_low(void)
{
    return (cached_battery_mv < BATTERY_LOW_THRESHOLD_MV);
}

bool battery_is_critical(void)
{
    return (cached_battery_mv <= BATTERY_CRITICAL_THRESHOLD_MV);
}
