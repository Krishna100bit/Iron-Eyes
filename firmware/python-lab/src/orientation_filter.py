"""
orientation_filter.py  —  Mahony AHRS Quaternion Orientation Filter
─────────────────────────────────────────────────────────────────────
Algorithm Reference:
    Mahony, R., Hamel, T., & Pflimlin, J. M. (2008).
    "Nonlinear Complementary Filters on the Special Orthogonal Group."
    IEEE Transactions on Automatic Control, 53(5), 1203-1218.

This module implements the Mahony AHRS algorithm (quaternion-based):
1. Integrates gyroscope angular rate for fast, low-latency orientation change.
2. Computes the direction of gravity estimated from the current quaternion.
3. Calculates the cross-product error between measured accelerometer vector
   and estimated gravity vector.
4. Feeds the error through a Proportional-Integral (PI) feedback controller
   to continuously cancel gyro bias and align orientation with true vertical.
"""

from typing import Tuple
import numpy as np


class MahonyAHRS:
    """
    Mahony AHRS algorithm for 6-DOF IMU (Accelerometer + Gyroscope).
    Maintains internal quaternion [q0, q1, q2, q3] where q0 is the scalar (w) part.
    """

    def __init__(self, kp: float = 0.5, ki: float = 0.01):
        """
        Initialize Mahony AHRS filter.

        Args:
            kp: Proportional feedback gain.
            ki: Integral feedback gain.
        """
        self.kp = float(kp)
        self.ki = float(ki)

        # Quaternion state [w, x, y, z] representing sensor -> world orientation
        self.q = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)

        # Integral error state for gyro bias correction
        self.integral_fb = np.zeros(3, dtype=np.float64)

    def reset(self, q_init: np.ndarray = None):
        """Reset the filter state."""
        if q_init is not None:
            q_norm = np.linalg.norm(q_init)
            if q_norm > 1e-9:
                self.q = np.array(q_init, dtype=np.float64) / q_norm
            else:
                self.q = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)
        else:
            self.q = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)
        self.integral_fb = np.zeros(3, dtype=np.float64)

    def init_from_accel(self, accel: np.ndarray):
        """
        Initialize quaternion from a static accelerometer measurement (gravity vector).
        Aligns the sensor body frame gravity vector with the world [0, 0, 1] vertical axis.
        """
        a = np.asarray(accel, dtype=np.float64)
        norm_a = np.linalg.norm(a)
        if norm_a < 1e-4:
            self.reset()
            return

        a_unit = a / norm_a  # unit gravity direction in sensor body frame
        # We want rotation from body to world where world gravity is [0, 0, 1]
        # i.e., in body frame, gravity points down [0, 0, 1] or measured as [0, 0, +1] upward
        v_world = np.array([0.0, 0.0, 1.0], dtype=np.float64)

        # Half-way vector / axis-angle calculation between a_unit and v_world
        cross_prod = np.cross(a_unit, v_world)
        dot_prod = float(np.dot(a_unit, v_world))

        if dot_prod < -0.999999:
            # 180 degree flip around X axis
            self.q = np.array([0.0, 1.0, 0.0, 0.0], dtype=np.float64)
        elif dot_prod > 0.999999:
            # Already aligned
            self.q = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)
        else:
            w = 1.0 + dot_prod
            q = np.array([w, cross_prod[0], cross_prod[1], cross_prod[2]], dtype=np.float64)
            self.q = q / np.linalg.norm(q)

        self.integral_fb = np.zeros(3, dtype=np.float64)

    def update(self, accel: np.ndarray, gyro: np.ndarray, dt: float) -> np.ndarray:
        """
        Execute one Mahony AHRS algorithm update step.

        Args:
            accel: Accelerometer readings [ax, ay, az] in m/s² (or g).
            gyro: Gyroscope readings [gx, gy, gz] in deg/s or rad/s.
                  Note: this function converts deg/s to rad/s internally.
            dt: Time step in seconds.

        Returns:
            Current orientation quaternion [q0, q1, q2, q3] (w, x, y, z).
        """
        if dt <= 0.0:
            return self.q.copy()

        ax, ay, az = float(accel[0]), float(accel[1]), float(accel[2])
        # Convert gyro from deg/s to rad/s
        gx = np.radians(float(gyro[0]))
        gy = np.radians(float(gyro[1]))
        gz = np.radians(float(gyro[2]))

        q0, q1, q2, q3 = self.q

        # Compute feedback only if accelerometer measurement is valid (non-zero)
        norm_a = np.sqrt(ax * ax + ay * ay + az * az)
        if norm_a > 1e-4:
            # Normalize accelerometer measurement
            ax /= norm_a
            ay /= norm_a
            az /= norm_a

            # Estimated direction of gravity in sensor body frame from current quaternion
            # v = R(q)^T * [0, 0, 1]^T
            vx = 2.0 * (q1 * q3 - q0 * q2)
            vy = 2.0 * (q0 * q1 + q2 * q3)
            vz = q0 * q0 - q1 * q1 - q2 * q2 + q3 * q3

            # Error is cross product between measured direction and estimated direction of gravity
            ex = (ay * vz - az * vy)
            ey = (az * vx - ax * vz)
            ez = (ax * vy - ay * vx)

            # Apply integral feedback if Ki > 0
            if self.ki > 0.0:
                self.integral_fb[0] += ex * self.ki * dt
                self.integral_fb[1] += ey * self.ki * dt
                self.integral_fb[2] += ez * self.ki * dt
                gx += self.integral_fb[0]
                gy += self.integral_fb[1]
                gz += self.integral_fb[2]

            # Apply proportional feedback
            gx += self.kp * ex
            gy += self.kp * ey
            gz += self.kp * ez

        # Integrate rate of change of quaternion: q_dot = 0.5 * q (x) omega
        half_dt = 0.5 * dt
        dq0 = (-q1 * gx - q2 * gy - q3 * gz) * half_dt
        dq1 = ( q0 * gx + q2 * gz - q3 * gy) * half_dt
        dq2 = ( q0 * gy - q1 * gz + q3 * gx) * half_dt
        dq3 = ( q0 * gz + q1 * gy - q2 * gx) * half_dt

        q0 += dq0
        q1 += dq1
        q2 += dq2
        q3 += dq3

        # Normalize quaternion
        norm_q = np.sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3)
        if norm_q > 1e-9:
            self.q = np.array([q0 / norm_q, q1 / norm_q, q2 / norm_q, q3 / norm_q], dtype=np.float64)

        return self.q.copy()


def compute_orientations_mahony(
    accel_data: np.ndarray,
    gyro_data: np.ndarray,
    dt_data: np.ndarray,
    kp: float = 0.5,
    ki: float = 0.01,
) -> np.ndarray:
    """
    Batch processing function for Mahony AHRS algorithm over a timeseries.

    Args:
        accel_data: (N, 3) array of acceleration [ax, ay, az] in m/s².
        gyro_data:  (N, 3) array of angular rate [gx, gy, gz] in deg/s (bias removed).
        dt_data:    (N,) array of sample delta times in seconds.
        kp:         Mahony proportional gain.
        ki:         Mahony integral gain.

    Returns:
        quaternions: (N, 4) array of orientation quaternions [w, x, y, z].
    """
    n_samples = len(accel_data)
    quaternions = np.zeros((n_samples, 4), dtype=np.float64)

    filter_ahrs = MahonyAHRS(kp=kp, ki=ki)

    # Initialize from first stationary accelerometer sample if available
    if n_samples > 0:
        filter_ahrs.init_from_accel(accel_data[0])

    for i in range(n_samples):
        dt = float(dt_data[i]) if i < len(dt_data) else 0.01
        quaternions[i] = filter_ahrs.update(accel_data[i], gyro_data[i], dt)

    return quaternions
