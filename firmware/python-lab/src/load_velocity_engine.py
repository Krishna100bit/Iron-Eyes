"""
load_velocity_engine.py  —  IronLoop Load-Velocity Profiling & e1RM Estimation
─────────────────────────────────────────────────────────────────────────────
Maintains per-exercise load-velocity data points from validated repetitions
and estimates Estimated 1-Repetition Maximum (e1RM) using classical linear
regression extrapolated to a Minimum Velocity Threshold (MVT).

Key Principles:
  1. Deterministic Linear Physics: Uses 1st-degree linear regression (velocity
     vs. load). Higher-order polynomial fits and non-linear approximations are
     explicitly avoided to prevent overfitting on sparse sets.
  2. Strict Data Quality Filtering: Repetitions flagged as noisy or suffering
     from packet loss are strictly excluded.
  3. Outlier Rejection: Residuals exceeding 2 standard deviations from an initial
     linear fit are pruned before final parameter estimation.
  4. Conservative Confidence Reporting: Given small sample sizes in practical
     training sessions, ratings are capped at "Moderate confidence".
"""

from dataclasses import dataclass, field
from typing import List, Optional, Tuple
import numpy as np
from scipy import stats

from config import (
    MIN_VELOCITY_THRESHOLD_SQUAT,
    MIN_POINTS_FOR_E1RM,
    DEFAULT_LV_PROFILE_SQUAT,
    DEFAULT_CONFIG,
)


@dataclass
class LoadVelocityPoint:
    """Single load-velocity observation from a validated rep."""
    load_kg: float
    mean_concentric_velocity: float  # m/s
    peak_concentric_velocity: float  # m/s
    data_quality: str                # "CLEAN", "NOISY", "PACKET_LOSS"
    rep_number: int = 0
    timestamp_s: float = 0.0


@dataclass
class E1RMResult:
    """Estimated 1RM output and regression diagnostics."""
    e1rm_kg: Optional[float]
    r_squared: float
    n_points: int
    n_distinct_loads: int
    confidence_label: str
    mvt_mps: float
    slope: float
    intercept: float
    status_message: str
    is_valid: bool = False
    profile_e1rm_kg: Optional[float] = None
    personal_e1rm_kg: Optional[float] = None
    blend_weight: float = 0.0

    def formatted_summary(self, exercise_name: str = "squat") -> str:
        """Format a single-line summary for dashboard display."""
        if not self.is_valid or self.e1rm_kg is None:
            return f"e1RM ({exercise_name}): {self.status_message}"
        return (
            f"e1RM ({exercise_name}): {self.e1rm_kg:.0f} kg  "
            f"[{self.confidence_label}]"
        )


def estimate_expected_pct_1rm(
    velocity_mps: float,
    profile: Optional[List[Tuple[float, float]]] = None,
) -> float:
    """
    Interpolate expected %1RM from concentric mean velocity using published research table.

    Args:
        velocity_mps: Mean Concentric Velocity in m/s.
        profile: List of (pct_1rm, velocity_mps) tuples sorted by %1RM descending.

    Returns:
        Expected %1RM in range [0.30 .. 1.00]
    """
    ref = profile if profile is not None else DEFAULT_LV_PROFILE_SQUAT
    if not ref or velocity_mps <= 0.0:
        return 1.0

    # Extract velocities and %1RM values
    # Sorted by velocity ascending (highest %1RM has lowest velocity)
    sorted_by_v = sorted(ref, key=lambda x: x[1])

    v_min = sorted_by_v[0][1]
    pct_max = sorted_by_v[0][0]  # 1.00 @ 0.30 m/s
    v_max = sorted_by_v[-1][1]
    pct_min = sorted_by_v[-1][0] # 0.50 @ 0.95 m/s

    if velocity_mps <= v_min:
        return float(pct_max)

    if velocity_mps >= v_max:
        # Linear extrapolation for light warmup loads (> 0.95 m/s)
        return max(0.30, float(pct_min * (v_max / velocity_mps)))

    # Piecewise linear interpolation between anchor points
    for i in range(len(sorted_by_v) - 1):
        v1, pct1 = sorted_by_v[i][1], sorted_by_v[i][0]
        v2, pct2 = sorted_by_v[i + 1][1], sorted_by_v[i + 1][0]
        if v1 <= velocity_mps <= v2:
            frac = (velocity_mps - v1) / (v2 - v1)
            return float(pct1 + frac * (pct2 - pct1))

    return float(pct_max)


class LoadVelocityEngine:
    """
    Tracks load-velocity profiles for resistance exercises and computes e1RM
    by blending published research reference profiles with athlete-specific regression.
    """

    def __init__(
        self,
        exercise_name: str = "squat",
        mvt_mps: float = MIN_VELOCITY_THRESHOLD_SQUAT,
        min_points: int = MIN_POINTS_FOR_E1RM,
        reference_profile: Optional[List[Tuple[float, float]]] = None,
    ):
        self.exercise_name = exercise_name
        self.mvt_mps = mvt_mps
        self.min_points = min_points
        self.reference_profile = reference_profile if reference_profile is not None else DEFAULT_LV_PROFILE_SQUAT
        self.points: List[LoadVelocityPoint] = []
        self._last_result: Optional[E1RMResult] = None

    def reset(self):
        """Clear all stored data points and reset engine state."""
        self.points.clear()
        self._last_result = None

    def add_rep(
        self,
        load_kg: float,
        mean_concentric_velocity: float,
        peak_concentric_velocity: float = 0.0,
        data_quality: str = "CLEAN",
        rep_number: int = 0,
        timestamp_s: float = 0.0,
    ) -> E1RMResult:
        """
        Record a newly completed repetition and recalculate e1RM.
        """
        pt = LoadVelocityPoint(
            load_kg=float(load_kg),
            mean_concentric_velocity=float(mean_concentric_velocity),
            peak_concentric_velocity=float(peak_concentric_velocity),
            data_quality=str(data_quality).strip().upper(),
            rep_number=rep_number,
            timestamp_s=timestamp_s,
        )
        self.points.append(pt)
        return self.compute_e1rm()

    def get_valid_points(self) -> List[LoadVelocityPoint]:
        """Return only clean data quality points with positive load and velocity."""
        return [
            p for p in self.points
            if p.data_quality == "CLEAN" and p.load_kg > 0.0 and p.mean_concentric_velocity > 0.0
        ]

    def compute_e1rm(self) -> E1RMResult:
        """
        Compute blended e1RM combining published research anchor points with personal regression.
        """
        valid_pts = self.get_valid_points()
        n = len(valid_pts)
        distinct_loads = len(set(p.load_kg for p in valid_pts))

        # ── Case 1: n = 0 (No valid data points) ──────────────────────────────
        if n == 0:
            result = E1RMResult(
                e1rm_kg=None,
                r_squared=0.0,
                n_points=0,
                n_distinct_loads=0,
                confidence_label="Low confidence",
                mvt_mps=self.mvt_mps,
                slope=0.0,
                intercept=0.0,
                status_message="insufficient data (0 reps)",
                is_valid=False,
                profile_e1rm_kg=None,
                personal_e1rm_kg=None,
                blend_weight=0.0,
            )
            self._last_result = result
            return result

        # ── Step 1: Research Profile-Based 1RM Estimate ───────────────────────
        # Take the highest-load point completed so far
        highest_load_pt = max(valid_pts, key=lambda p: p.load_kg)
        expected_pct_1rm = estimate_expected_pct_1rm(
            highest_load_pt.mean_concentric_velocity,
            self.reference_profile,
        )
        profile_based_e1rm = float(highest_load_pt.load_kg / max(0.20, expected_pct_1rm))

        # ── Step 2: Athlete's Own Linear Regression (if n >= min_points) ──────
        personal_regression_e1rm: Optional[float] = None
        r_squared: float = 0.0
        slope: float = 0.0
        intercept: float = 0.0
        has_valid_personal_fit = False

        if distinct_loads >= self.min_points:
            loads = np.array([p.load_kg for p in valid_pts], dtype=np.float64)
            vels = np.array([p.mean_concentric_velocity for p in valid_pts], dtype=np.float64)

            # Initial linear fit
            slope_init, intercept_init, r_init, _, _ = stats.linregress(loads, vels)

            # Outlier rejection (> 2 std residuals)
            fitted_vels = slope_init * loads + intercept_init
            residuals = vels - fitted_vels
            std_res = np.std(residuals)

            if std_res > 1e-5:
                inlier_mask = np.abs(residuals) <= (2.0 * std_res)
            else:
                inlier_mask = np.ones(len(loads), dtype=bool)

            loads_clean = loads[inlier_mask]
            vels_clean = vels[inlier_mask]

            if len(np.unique(loads_clean)) < self.min_points:
                loads_clean, vels_clean = loads, vels

            slope, intercept, r_value, _, _ = stats.linregress(loads_clean, vels_clean)
            r_squared = float(r_value ** 2)

            # Check physiological validity: negative slope (velocity drops with load)
            if slope < -1e-6:
                extrapolated = float((self.mvt_mps - intercept) / slope)
                if 20.0 <= extrapolated <= 600.0:
                    personal_regression_e1rm = extrapolated
                    has_valid_personal_fit = True

        # ── Step 3: Blend Profile & Personal Estimates ────────────────────────
        # Weight w increases from 0.0 to 1.0 as personal data points accumulate
        if has_valid_personal_fit and personal_regression_e1rm is not None:
            w = float(min(1.0, n / 8.0))
            final_e1rm = float(w * personal_regression_e1rm + (1.0 - w) * profile_based_e1rm)

            if n >= 8 and w >= 1.0:
                confidence_label = f"Personal fit (n={n}, R²={r_squared:.2f})"
            else:
                confidence_label = f"Blended (n={n})"
        else:
            w = 0.0
            final_e1rm = profile_based_e1rm
            confidence_label = f"Profile-based (n={n}, low confidence)"

        result = E1RMResult(
            e1rm_kg=final_e1rm,
            r_squared=r_squared,
            n_points=n,
            n_distinct_loads=distinct_loads,
            confidence_label=confidence_label,
            mvt_mps=self.mvt_mps,
            slope=slope,
            intercept=intercept,
            status_message="OK",
            is_valid=True,
            profile_e1rm_kg=profile_based_e1rm,
            personal_e1rm_kg=personal_regression_e1rm,
            blend_weight=w,
        )
        self._last_result = result
        return result

    @property
    def latest_result(self) -> Optional[E1RMResult]:
        return self._last_result
