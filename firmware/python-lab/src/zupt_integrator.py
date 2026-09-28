"""
zupt_integrator.py  —  Zero-Velocity Update (ZUPT) Integrator
─────────────────────────────────────────────────────────────
Integrates filtered vertical linear acceleration into vertical velocity
and displacement.

ZUPT (Zero-velocity UPdaTe) Drift Correction:
    Open-loop integration of accelerometer signals suffers from cumulative drift
    (quadratic in position, linear in velocity). Because barbell exercises
    (such as squats) feature stationary pauses at the start, bottom, and lockout
    of each repetition, whenever the stationary detector flags stillness,
    velocity is clamped to 0.0 m/s. This guarantees zero accumulated drift
    across multiple reps.
"""

from typing import Tuple
import numpy as np


def integrate_with_zupt(
    linear_accel_z: np.ndarray,
    dt_series: np.ndarray,
    stationary_mask: np.ndarray,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Integrate vertical linear acceleration into velocity and position with ZUPT resets.

    Args:
        linear_accel_z: (N,) array of vertical linear acceleration (m/s²).
        dt_series:      (N,) array of delta time per sample (seconds).
        stationary_mask:(N,) boolean array where True indicates the sensor is stationary.

    Returns:
        velocity_z: (N,) vertical velocity series (m/s).
        position_z: (N,) vertical displacement series (meters).
    """
    n_samples = len(linear_accel_z)
    if n_samples == 0:
        return np.array([]), np.array([])

    velocity_z = np.zeros(n_samples, dtype=np.float64)
    position_z = np.zeros(n_samples, dtype=np.float64)

    curr_v = 0.0
    curr_p = 0.0

    for i in range(n_samples):
        dt = float(dt_series[i]) if i < len(dt_series) and dt_series[i] > 0 else 0.01

        if stationary_mask[i]:
            # ZUPT: clamp velocity to zero at rest
            curr_v = 0.0
            curr_p = 0.0
        else:
            # Integrate acceleration to velocity: v = v_prev + a * dt
            curr_v += float(linear_accel_z[i]) * dt
            # Integrate velocity to position: p = p_prev + v * dt
            curr_p += curr_v * dt

        velocity_z[i] = curr_v
        position_z[i] = curr_p

    return velocity_z, position_z
