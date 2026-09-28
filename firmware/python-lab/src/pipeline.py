"""
pipeline.py  —  IronLoop VBT Signal Processing Pipeline
────────────────────────────────────────────────────────
Integrates the complete Phase-2 algorithmic chain into a single, pure,
independently testable function `process_session()`.

Code path is strictly identical for both live BLE execution and offline CSV replay.
No internal file I/O.
"""

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple, Union
import numpy as np

from config import VBTConfig, DEFAULT_CONFIG
from orientation_filter import compute_orientations_mahony
from gravity_removal import remove_gravity
from filtering import apply_savgol_filter
from stationary_detector import detect_stationary_periods
from zupt_integrator import integrate_with_zupt
from rep_detector import RepMetrics, detect_squat_reps


@dataclass
class PipelineResult:
    """Complete output of the VBT signal processing pipeline."""
    reps: List[RepMetrics]
    time_s: np.ndarray
    dt_s: np.ndarray
    accel_raw: np.ndarray        # (N, 3) m/s²
    gyro_corrected: np.ndarray   # (N, 3) deg/s
    quaternions: np.ndarray      # (N, 4) [w, x, y, z]
    linear_accel_world: np.ndarray  # (N, 3) m/s²
    linear_accel_z_raw: np.ndarray  # (N,) m/s²
    linear_accel_z_filt: np.ndarray # (N,) m/s²
    stationary_mask: np.ndarray  # (N,) bool
    velocity_z: np.ndarray       # (N,) m/s
    position_z: np.ndarray       # (N,) meters


def process_session(
    samples: Union[np.ndarray, Dict[str, np.ndarray]],
    gyro_bias: Optional[np.ndarray] = None,
    config: Optional[VBTConfig] = None,
) -> PipelineResult:
    """
    Process an IMU session through the entire VBT algorithm pipeline.

    Args:
        samples: Either a dictionary with keys:
                    'ts_ms' (or 'time_s'), 'ax', 'ay', 'az', 'gx', 'gy', 'gz', optionally 'seq'
                 or an (N, 7) or (N, 8) numpy array [ts_ms, ax, ay, az, gx, gy, gz, (seq)].
        gyro_bias: Optional 3-element array [gbx, gby, gbz] (deg/s) to subtract from gyro.
        config: VBTConfig instance with hyperparameters (defaults to DEFAULT_CONFIG).

    Returns:
        PipelineResult containing detected reps and all processed time-series arrays.
    """
    cfg = config if config is not None else DEFAULT_CONFIG

    # ── 1. Unpack and sanitize sample arrays ───────────────────────────────────
    seq_numbers = None
    if isinstance(samples, dict):
        if "time_s" in samples:
            time_s = np.asarray(samples["time_s"], dtype=np.float64)
        elif "ts_ms" in samples:
            ts_ms = np.asarray(samples["ts_ms"], dtype=np.float64)
            time_s = (ts_ms - ts_ms[0]) / 1000.0 if len(ts_ms) > 0 else np.array([])
        else:
            n = len(samples.get("ax", []))
            time_s = np.arange(n, dtype=np.float64) * cfg.nominal_dt_s

        accel_raw = np.column_stack([samples["ax"], samples["ay"], samples["az"]]).astype(np.float64)
        gyro_raw = np.column_stack([samples["gx"], samples["gy"], samples["gz"]]).astype(np.float64)

        if "seq" in samples:
            seq_numbers = np.asarray(samples["seq"], dtype=np.int64)

    elif isinstance(samples, np.ndarray):
        if samples.ndim != 2 or samples.shape[1] < 7:
            raise ValueError(f"Expected 2D array with >= 7 columns, got shape {samples.shape}")

        ts = samples[:, 0].astype(np.float64)
        # If timestamp values appear to be in milliseconds (> 100), convert to seconds
        if np.max(ts) > 100.0:
            time_s = (ts - ts[0]) / 1000.0
        else:
            time_s = ts - ts[0]

        accel_raw = samples[:, 1:4].astype(np.float64)
        gyro_raw = samples[:, 4:7].astype(np.float64)

        if samples.shape[1] >= 8:
            seq_numbers = samples[:, 7].astype(np.int64)
    else:
        raise TypeError(f"Unsupported samples type: {type(samples)}")

    n_samples = len(accel_raw)
    if n_samples == 0:
        empty = np.array([])
        return PipelineResult(
            reps=[], time_s=empty, dt_s=empty, accel_raw=np.zeros((0, 3)),
            gyro_corrected=np.zeros((0, 3)), quaternions=np.zeros((0, 4)),
            linear_accel_world=np.zeros((0, 3)), linear_accel_z_raw=empty,
            linear_accel_z_filt=empty, stationary_mask=empty.astype(bool),
            velocity_z=empty, position_z=empty,
            setup_state="CALIBRATED", active_start_idx=0
        )

    # Compute dt per sample
    dt_s = np.diff(time_s, prepend=time_s[0] - cfg.nominal_dt_s)
    # Clamp non-positive or abnormally high delta times to nominal dt
    dt_s[dt_s <= 0.0] = cfg.nominal_dt_s
    dt_s[dt_s > 0.10] = cfg.nominal_dt_s

    # ── 2. Gyroscope bias subtraction ─────────────────────────────────────────
    gyro_corrected = gyro_raw.copy()
    if gyro_bias is not None:
        gb = np.asarray(gyro_bias, dtype=np.float64).reshape(3,)
        gyro_corrected -= gb

    # ── 3. Mahony AHRS orientation filter ─────────────────────────────────────
    quaternions = compute_orientations_mahony(
        accel_data=accel_raw,
        gyro_data=gyro_corrected,
        dt_data=dt_s,
        kp=cfg.mahony_kp,
        ki=cfg.mahony_ki,
    )

    # ── 4. World frame transformation and gravity removal ─────────────────────
    linear_accel_world, linear_accel_z_raw = remove_gravity(
        accel_sensor=accel_raw,
        quaternions=quaternions,
    )

    # ── 5. Savitzky-Golay filtering on vertical linear acceleration ───────────
    linear_accel_z_filt = apply_savgol_filter(
        data=linear_accel_z_raw,
        window_length=cfg.savgol_window_length,
        polyorder=cfg.savgol_polyorder,
    )

    # ── 6. Dual-threshold stationary / rest detection ─────────────────────────
    stationary_mask, _, _ = detect_stationary_periods(
        accel=accel_raw,
        gyro=gyro_corrected,
        window_samples=cfg.stationary_window_samples,
        accel_var_thresh=cfg.stationary_accel_var_thresh,
        gyro_mag_thresh=cfg.stationary_gyro_mag_thresh,
    )

    # ── 7. Constrained numerical integration with ZUPT ────────────────────────
    velocity_z, position_z = integrate_with_zupt(
        linear_accel_z=linear_accel_z_filt,
        dt_series=dt_s,
        stationary_mask=stationary_mask,
    )

    # ── 7b. Light Savitzky-Golay post-smoothing on velocity (Part 1) ──────────
    if cfg.velocity_smoothing_window > 1 and len(velocity_z) > cfg.velocity_smoothing_window:
        velocity_z = apply_savgol_filter(
            data=velocity_z,
            window_length=cfg.velocity_smoothing_window,
            polyorder=cfg.velocity_smoothing_polyorder,
        )
        # Re-zero during stationary intervals to maintain ZUPT rigor
        velocity_z[stationary_mask] = 0.0

    # ── 8. Squat rep detection and VBT metric calculation ─────────────────────
    reps = detect_squat_reps(
        velocity_z=velocity_z,
        position_z=position_z,
        time_s=time_s,
        stationary_mask=stationary_mask,
        seq_numbers=seq_numbers,
        vel_start_thresh=cfg.rep_velocity_start_thresh,
        vel_concentric_thresh=cfg.rep_velocity_concentric_thresh,
        vel_end_thresh=cfg.rep_velocity_end_thresh,
        min_duration_s=cfg.rep_min_duration_s,
        min_concentric_duration_s=cfg.rep_min_concentric_duration_s,
        min_displacement_m=cfg.rep_min_displacement_m,
        max_packet_loss_pct=cfg.max_packet_loss_pct,
    )

    return PipelineResult(
        reps=reps,
        time_s=time_s,
        dt_s=dt_s,
        accel_raw=accel_raw,
        gyro_corrected=gyro_corrected,
        quaternions=quaternions,
        linear_accel_world=linear_accel_world,
        linear_accel_z_raw=linear_accel_z_raw,
        linear_accel_z_filt=linear_accel_z_filt,
        stationary_mask=stationary_mask,
        velocity_z=velocity_z,
        position_z=position_z,
    )

