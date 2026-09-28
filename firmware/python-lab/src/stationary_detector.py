"""
stationary_detector.py  —  Dual-Threshold Stationary / Rest Detector
─────────────────────────────────────────────────────────────────────
Classifies each sample in the IMU timeseries as STATIONARY (True) or MOVING (False).

Detection Criteria:
    Requires BOTH conditions to hold over a rolling window:
    1. Rolling variance of acceleration magnitude < stationary_accel_var_thresh
       (identifies absence of linear movement).
    2. Rolling mean/max of gyroscope magnitude < stationary_gyro_mag_thresh
       (identifies absence of rotational adjustments or bar repositioning).

Stationary regions serve as Zero-velocity Update (ZUPT) points to reset
integration drift and anchor rep boundaries.
"""

from typing import Tuple
import numpy as np


def detect_stationary_periods(
    accel: np.ndarray,
    gyro: np.ndarray,
    window_samples: int = 15,
    accel_var_thresh: float = 0.035,
    gyro_mag_thresh: float = 5.0,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Detect stationary intervals in IMU data using dual variance + gyro thresholds.

    Args:
        accel: (N, 3) acceleration in body or world frame (m/s²).
        gyro:  (N, 3) angular rate (deg/s).
        window_samples: Rolling window size in samples (e.g., 15 samples ≈ 150 ms at 100 Hz).
        accel_var_thresh: Variance threshold for |accel| (m/s²)².
        gyro_mag_thresh: Magnitude threshold for |gyro| (deg/s).

    Returns:
        stationary_mask: (N,) boolean array where True indicates stationary.
        accel_var_series: (N,) rolling variance of acceleration magnitude.
        gyro_mag_series: (N,) rolling mean of gyroscope magnitude.
    """
    n_samples = len(accel)
    if n_samples == 0:
        return np.array([], dtype=bool), np.array([]), np.array([])

    # Compute magnitudes
    accel_mag = np.linalg.norm(accel, axis=1)  # (N,)
    gyro_mag = np.linalg.norm(gyro, axis=1)    # (N,)

    w = max(3, min(int(window_samples), n_samples))
    half_w = w // 2

    # Fast rolling variance & rolling mean using convolution / uniform filter
    # To maintain exact causality or centered window:
    accel_var_series = np.zeros(n_samples, dtype=np.float64)
    gyro_mag_series = np.zeros(n_samples, dtype=np.float64)

    for i in range(n_samples):
        i_start = max(0, i - w + 1)
        i_end = i + 1

        a_win = accel_mag[i_start:i_end]
        g_win = gyro_mag[i_start:i_end]

        accel_var_series[i] = np.var(a_win) if len(a_win) > 1 else 0.0
        gyro_mag_series[i] = np.mean(g_win)

    # Dual condition check
    stationary_mask = (accel_var_series <= accel_var_thresh) & (gyro_mag_series <= gyro_mag_thresh)

    return stationary_mask, accel_var_series, gyro_mag_series
