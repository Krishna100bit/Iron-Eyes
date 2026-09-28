# IronLoop — Battery Management & Protection Notes (300mAh LiPo)

This document details the battery hardware design, software monitoring architecture, LiPo discharge profiling, and safety protection thresholds for IronLoop running on a **300mAh single-cell Lithium Polymer (LiPo) battery**.

---

## 1. Hardware Architecture & Voltage Sensing

| Parameter | Value / Hardware Routing |
|-----------|--------------------------|
| **Battery Chemistry** | Single-Cell 1S LiPo (3.7V nominal, 4.2V peak) |
| **Nominal Capacity** | 300 mAh (~1.11 Wh) |
| **ADC Channel** | AIN7 (P0.31) on Nordic nRF52840 SAADC |
| **ADC Resolution** | 12-bit (0 – 4095), 0.6V internal ref, 1/6 input gain (0 – 3.6V range) |
| **Divider Enable Pin** | P0.14 (`VBAT_ENABLE`, Active LOW) |
| **Voltage Divider** | $R_1 = 1\,\text{M}\Omega$, $R_2 = 510\,\text{k}\Omega$ (Multiplier: $\approx 2.961$) |
| **Quiescent Current Protection** | P0.14 is driven LOW only during the brief ADC sample window, eliminating idle parasitic drain |

---

## 2. Onboard Charging Architecture

- **Independent Hardware Operation**: The onboard charge management IC operates independently of the nRF52840 MCU. LiPo charging occurs normally and safely whether the device is awake, streaming, or in `SYSTEM OFF` low-power sleep mode.
- **Hardware-Managed Charge Status**: On the Seeed Studio XIAO nRF52840 Sense board revision, the charge status `/CHG` pin is routed directly to the onboard orange charging LED and is **not connected to any nRF52840 GPIO pin**.
- **Software Handling**: Consequently, charge detection is handled exclusively in hardware; software does not fabricate or guess a charge state pin. Status bit 3 remains `0`, and voltage monitoring functions transparently.

---

## 3. Voltage Thresholds & Over-Discharge Protection

Small 300mAh LiPo cells are vulnerable to permanent internal degradation and swelling if repeatedly discharged below 3.0V. IronLoop implements a two-stage defense in firmware:

| Stage | Threshold (mV) | Action / System Response |
|-------|----------------|--------------------------|
| **Nominal Full** | $4200\,\text{mV}$ | $100\%$ charge |
| **Nominal Range** | $3700 - 4100\,\text{mV}$ | Normal streaming operation ($20\% - 90\%$) |
| **Low Battery Warning** | $\le 3400\,\text{mV}$ | Sets `STATUS_FLAG_LOW_BATT` bit, triggers high-priority flashing RED LED overlay, and notifies dashboard |
| **Critical Cutoff** | $\le 3200\,\text{mV}$ | **Automatic Safe Shutdown**: Stops any active IMU streaming session, sends a final status packet over BLE, and enters `SYSTEM OFF` deep sleep (< $2\,\mu\text{A}$ current draw) |

---

## 4. Signal Filtering & Voltage Sag Smoothing

During BLE radio transmission bursts, momentary voltage sags can occur on a small 300mAh cell due to internal resistance ($R_{\text{int}} \approx 150 - 300\,\text{m}\Omega$). 
- **Sampling Interval**: Sampled once every 5 seconds (`BATTERY_SAMPLE_INTERVAL_SEC = 5`).
- **Rolling Average Filter**: A 6-sample circular buffer (`BATTERY_SMOOTHING_WINDOW = 6`) averages the readings over $\approx 30$ seconds, preventing spurious low-battery alarms during heavy radio traffic.

---

## 5. Non-Linear LiPo Discharge Profile (Python Lab)

In [python-lab/src/config.py](file:///c:/SIH/python-lab/src/config.py), the `LIPO_DISCHARGE_CURVE_300MAH` lookup table maps voltage to state-of-charge percentage using piecewise linear interpolation:

```
  Voltage (mV)    State of Charge (%)
  ────────────    ───────────────────
    4200 mV             100%
    4100 mV              90%
    3980 mV              80%
    3870 mV              70%
    3820 mV              60%
    3790 mV              50%
    3760 mV              40%
    3730 mV              30%
    3700 mV              20%
    3550 mV              10%
    3400 mV               5% (Warning)
    3200 mV               0% (Cutoff)
```

The live dashboard displays both values simultaneously (e.g. `Batt: 82% (3.94V)`).

---

## 6. Physical Pack Protection Circuitry Note

> [!IMPORTANT]
> While IronLoop's firmware cuts off MCU operation at $3200\,\text{mV}$, **all 300mAh LiPo packs used with wearable/barbell hardware must contain an onboard integrated protection circuit module (PCM/BMS)**.
> 
> Typical 1S PCM ICs (such as DW01A + 8205A MOSFETs) provide hardware-level failsafes:
> 1. Over-discharge cutoff (hardware disconnect at $\approx 2.4 - 2.5\,\text{V}$)
> 2. Over-charge cutoff (hardware disconnect at $\approx 4.28 - 4.30\,\text{V}$)
> 3. Short-circuit / over-current protection ($\approx 1 - 2\,\text{A}$)
> 
> Always confirm that your specific 300mAh JST-PH LiPo battery includes a built-in PCM under the yellow Kapton tape before deployment.
