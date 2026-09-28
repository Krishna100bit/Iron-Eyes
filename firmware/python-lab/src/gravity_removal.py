"""
gravity_removal.py  —  World Frame Transformation and Gravity Removal
───────────────────────────────────────────────────────────────────────
Transforms accelerometer measurements from the IMU body frame into the
inertial world frame (where Z is aligned vertically upwards) using orientation
quaternions, then removes the static gravity vector [0, 0, g].

Output:
    linear_accel_world: (N, 3) acceleration caused strictly by barbell motion.
"""

from typing import Tuple
import numpy as np


def rotate_vector_by_quaternion(q: np.ndarray, v: np.ndarray) -> np.ndarray:
    """
    Rotate 3D vector(s) v from sensor body frame to world frame using quaternion(s) q.

    Args:
        q: (4,) or (N, 4) array of quaternions [w, x, y, z].
        v: (3,) or (N, 3) array of 3D vectors [vx, vy, vz].

    Returns:
        v_rotated: (3,) or (N, 3) vector(s) in world frame.
    """
    q = np.asarray(q, dtype=np.float64)
    v = np.asarray(v, dtype=np.float64)

    single_input = (q.ndim == 1 and v.ndim == 1)
    if single_input:
        q = q.reshape(1, 4)
        v = v.reshape(1, 3)

    w = q[:, 0]
    x = q[:, 1]
    y = q[:, 2]
    z = q[:, 3]

    vx = v[:, 0]
    vy = v[:, 1]
    vz = v[:, 2]

    # Rotation matrix elements applied to vector v
    # R * v
    rx = (1.0 - 2.0 * (y*y + z*z)) * vx + 2.0 * (x*y - w*z) * vy + 2.0 * (x*z + w*y) * vz
    ry = 2.0 * (x*y + w*z) * vx + (1.0 - 2.0 * (x*x + z*z)) * vy + 2.0 * (y*z - w*x) * vz
    rz = 2.0 * (x*z - w*y) * vx + 2.0 * (y*z + w*x) * vy + (1.0 - 2.0 * (x*x + y*y)) * vz

    v_world = np.column_stack((rx, ry, rz))

    if single_input:
        return v_world[0]
    return v_world


def remove_gravity(
    accel_sensor: np.ndarray,
    quaternions: np.ndarray,
    gravity_magnitude: float = 9.80665,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Convert raw accelerometer measurements into gravity-free linear acceleration in world frame.

    Args:
        accel_sensor: (N, 3) array of acceleration in body frame [ax, ay, az] (m/s²).
        quaternions:  (N, 4) array of orientation quaternions [w, x, y, z].
        gravity_magnitude: Gravitational acceleration in m/s² (default 9.80665).

    Returns:
        linear_accel_world: (N, 3) array of pure linear acceleration [lax, lay, laz] in world frame.
        linear_accel_z:     (N,) 1D array of vertical linear acceleration along world Z axis (m/s²).
    """
    accel_sensor = np.asarray(accel_sensor, dtype=np.float64)
    quaternions = np.asarray(quaternions, dtype=np.float64)

    # 1. Rotate accelerometer vectors into world frame
    accel_world = rotate_vector_by_quaternion(quaternions, accel_sensor)

    # 2. Subtract static gravity [0, 0, g] from world frame
    gravity_world = np.array([0.0, 0.0, gravity_magnitude], dtype=np.float64)
    linear_accel_world = accel_world - gravity_world

    # Vertical linear acceleration (World Z axis)
    linear_accel_z = linear_accel_world[:, 2]

    return linear_accel_world, linear_accel_z
