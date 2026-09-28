"""
config.py  —  IronLoop Central Tuning Parameters
─────────────────────────────────────────────────
ALL algorithmic and hardware thresholds are defined HERE and ONLY here.
No magic numbers exist in any algorithm module.
"""

from dataclasses import dataclass
from pathlib import Path

# ── BLE UUIDs (must match firmware ble_service.h) ─────────────────────────
SERVICE_UUID     = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
IMU_CHAR_UUID    = "beb5483e-36e1-4688-b7f5-ea07361b26a8"   # Stream (Notify)
CMD_CHAR_UUID    = "beb5483f-36e1-4688-b7f5-ea07361b26a8"   # Command (Write)
STATUS_CHAR_UUID = "beb54840-36e1-4688-b7f5-ea07361b26a8"   # Status (Notify/Read)

# ── Command Constants ─────────────────────────────────────────────────────
CMD_START_SESSION = 0x01
CMD_STOP_SESSION  = 0x02
CMD_CALIBRATE     = 0x03
CMD_PING          = 0x04

# ── Data directories ──────────────────────────────────────────────────────
CAPTURES_DIR = Path(__file__).resolve().parent.parent / "data" / "real_captures"

# ── Load-Velocity / e1RM Parameters ─────────────────────────────────────────
# Minimum Velocity Threshold (MVT) for Back Squat in m/s.
# NOTE: 0.30 m/s is a standard baseline from velocity-based training literature
# (e.g. González-Badillo & Sánchez-Medina, 2010). However, individual true 1RM
# terminal velocity varies significantly (typically 0.25 - 0.35 m/s) based on
# biomechanics, anthropometry, and training status. This value should be personalized
# over time per athlete and must NOT be presented as a universal physiological constant.
MIN_VELOCITY_THRESHOLD_SQUAT: float = 0.30

# Minimum number of distinct load points required before computing linear regression e1RM.
MIN_POINTS_FOR_E1RM: int = 4

# Reference Load-Velocity Profile for Back Squat:
# Mapping of approximate %1RM to expected Mean Concentric Velocity (m/s).
# NOTE: These figures are approximate, commonly cited reference anchor points from
# published VBT literature (e.g., González-Badillo & Sánchez-Medina 2010; Conceição et al. 2016;
# Weakley et al. 2021). They are intended as a generalized population prior for early-stage
# blending before athlete-specific regression data accumulates. For formal research or competition
# deployment, verify against peer-reviewed demographic-specific datasets.
# Format: List of (pct_1rm: float [0.0..1.0], mean_concentric_velocity_mps: float)
DEFAULT_LV_PROFILE_SQUAT = [
    (1.00, 0.30),   # 100% 1RM (MVT) ~0.30 m/s
    (0.90, 0.45),   # 90%  1RM ~0.45 m/s
    (0.80, 0.55),   # 80%  1RM ~0.55 m/s
    (0.70, 0.67),   # 70%  1RM ~0.65-0.70 m/s
    (0.60, 0.77),   # 60%  1RM ~0.75-0.80 m/s
    (0.50, 0.95),   # 50%  1RM ~0.90-1.00 m/s
]

# ── 300mAh Single-Cell LiPo Battery Discharge Profile ──────────────────────
# Non-linear discharge curve for small 1S LiPo (nominal 3.7V, 4.2V max, 3.2V cutoff).
# Format: (voltage_mv: int, state_of_charge_pct: float) sorted descending by voltage.
LIPO_DISCHARGE_CURVE_300MAH = [
    (4200, 100.0),
    (4100, 90.0),
    (3980, 80.0),
    (3870, 70.0),
    (3820, 60.0),
    (3790, 50.0),
    (3760, 40.0),
    (3730, 30.0),
    (3700, 20.0),
    (3550, 10.0),
    (3400, 5.0),    # LOW_BATTERY warning threshold
    (3200, 0.0),    # CRITICAL_BATTERY sleep shutdown threshold
]


def battery_mv_to_percent(battery_mv: int) -> int:
    """
    Convert raw battery voltage in mV to state-of-charge percentage using
    piecewise linear interpolation across the LiPo discharge curve.
    """
    if battery_mv >= LIPO_DISCHARGE_CURVE_300MAH[0][0]:
        return 100
    if battery_mv <= LIPO_DISCHARGE_CURVE_300MAH[-1][0]:
        return 0

    for i in range(len(LIPO_DISCHARGE_CURVE_300MAH) - 1):
        v_high, p_high = LIPO_DISCHARGE_CURVE_300MAH[i]
        v_low, p_low = LIPO_DISCHARGE_CURVE_300MAH[i + 1]
        if v_low <= battery_mv <= v_high:
            frac = (battery_mv - v_low) / (v_high - v_low)
            pct = p_low + frac * (p_high - p_low)
            return int(round(pct))

    return 0


@dataclass
class VBTConfig:
    # ── Sampling & Hardware ───────────────────────────────────────────────
    sample_rate_hz: float = 100.0           # Nominal IMU sampling rate (Hz)
    dt_default_s: float = 0.01              # Nominal sample interval (10 ms)
    nominal_dt_s: float = 0.01              # Alias for dt_default_s
    accel_scale_raw: float = 1000.0         # Raw i16 -> m/s² divider
    gyro_scale_raw: float = 100.0           # Raw i16 -> °/s divider
    gravity_constant: float = 9.80665       # Standard Earth gravity (m/s²)

    # ── Mahony AHRS Orientation Filter ────────────────────────────────────
    mahony_kp: float = 0.40                 # Proportional feedback gain (-20% tuned to minimize motion jitter)
    mahony_ki: float = 0.01                 # Integral feedback gain

    # ── Savitzky-Golay Linear Acceleration Filter ─────────────────────────
    savgol_window_length: int = 11          # Window length (odd integer)
    savgol_polyorder: int = 2               # Polynomial order

    # ── Post-Integration Velocity Smoothing ───────────────────────────────
    velocity_smoothing_window: int = 5      # Light Savitzky-Golay window on velocity_z
    velocity_smoothing_polyorder: int = 2   # Polynomial order for velocity smoothing

    # ── Stationary & Zero Velocity Update (ZUPT) Detector ─────────────────
    stationary_window_samples: int = 15     # Rolling window size (samples)
    stationary_accel_var_thresh: float = 0.06  # Variance threshold for |accel| (m/s²)²
    stationary_gyro_mag_thresh_dps: float = 8.0 # Gyro threshold (°/s)
    stationary_gyro_mag_thresh: float = 8.0     # Alias for stationary_gyro_mag_thresh_dps

    # ── Barbell Rep Segmentation State Machine ────────────────────────────
    rep_min_duration_s: float = 0.40        # Minimum total rep duration (seconds)
    rep_max_duration_s: float = 6.00        # Maximum total rep duration (seconds)
    rep_min_concentric_duration_s: float = 0.15 # Minimum concentric duration (seconds)
    rep_min_displacement_m: float = 0.10    # Minimum vertical displacement (meters)

    # Velocity thresholds for phase transitions (m/s)
    rep_eccentric_vel_thresh: float = -0.08
    rep_velocity_start_thresh: float = -0.08    # Alias
    rep_concentric_vel_thresh: float = 0.10
    rep_velocity_concentric_thresh: float = 0.10 # Alias
    rep_lockout_vel_thresh: float = 0.05
    rep_velocity_end_thresh: float = 0.05        # Alias

    # ── Data Quality Scoring ──────────────────────────────────────────────
    max_acceptable_loss_pct: float = 5.0
    max_packet_loss_pct: float = 5.0             # Alias

    # ── Load-Velocity / e1RM ──────────────────────────────────────────────
    min_velocity_threshold_squat: float = MIN_VELOCITY_THRESHOLD_SQUAT
    min_points_for_e1rm: int = MIN_POINTS_FOR_E1RM


# Global default instance
DEFAULT_CONFIG = VBTConfig()

