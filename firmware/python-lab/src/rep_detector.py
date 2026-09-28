"""
rep_detector.py  —  Squat Repetition Segmentation and VBT Metrics
───────────────────────────────────────────────────────────────────
Segments continuous velocity and displacement streams into discrete squat reps
and computes standard Velocity-Based Training (VBT) metrics:
  - Mean Concentric Velocity (MCV, m/s)
  - Peak Concentric Velocity (PV, m/s)
  - Estimated Range of Motion / Displacement (ROM, m)
  - Eccentric & Concentric Durations (ms)
  - Data Quality Flag ("CLEAN", "NOISY", "PACKET_LOSS")

Squat Kinematic State Machine:
  [REST / READY]
        │
        │ v_z < v_start_thresh (< 0) after confirmed stillness
        ▼
  [ECCENTRIC PHASE]  (bar descending)
        │
        │ v_z crosses back through zero / inflects upward
        ▼
  [TURNAROUND / BOTTOM]
        │
        │ v_z > v_concentric_thresh (> 0)
        ▼
  [CONCENTRIC PHASE] (bar ascending)
        │
        │ v_z returns to ~0 AND stationary period confirmed
        ▼
  [LOCKOUT / REP COMPLETE]
"""

from dataclasses import dataclass, asdict
from typing import List, Optional
import numpy as np


@dataclass
class RepMetrics:
    """Standardized metrics for one completed barbell repetition."""
    rep_number: int
    start_idx: int
    turnaround_idx: int
    end_idx: int
    start_time_s: float
    turnaround_time_s: float
    end_time_s: float
    duration_ms: float
    eccentric_duration_ms: float
    concentric_duration_ms: float
    mean_concentric_velocity: float  # m/s (Primary VBT metric)
    peak_concentric_velocity: float  # m/s
    estimated_displacement: float    # meters (Range of Motion)
    data_quality: str                # "CLEAN" | "NOISY" | "PACKET_LOSS"

    def to_dict(self) -> dict:
        return asdict(self)


def detect_squat_reps(
    velocity_z: np.ndarray,
    position_z: np.ndarray,
    time_s: np.ndarray,
    stationary_mask: np.ndarray,
    seq_numbers: Optional[np.ndarray] = None,
    vel_start_thresh: float = -0.06,
    vel_concentric_thresh: float = 0.08,
    vel_end_thresh: float = 0.05,
    min_duration_s: float = 0.30,
    min_concentric_duration_s: float = 0.15,
    min_displacement_m: float = 0.10,
    max_packet_loss_pct: float = 5.0,
) -> List[RepMetrics]:
    """
    Segment the vertical velocity timeseries into completed squat repetitions.

    Args:
        velocity_z:      (N,) vertical velocity series in world frame (m/s).
        position_z:      (N,) vertical displacement series (meters).
        time_s:          (N,) timestamps in seconds.
        stationary_mask: (N,) boolean mask indicating stationary periods.
        seq_numbers:     (N,) optional BLE packet sequence numbers to assess packet loss.
        vel_start_thresh: Downward velocity to initiate eccentric descent (m/s, < 0).
        vel_concentric_thresh: Upward velocity confirming concentric ascent (m/s, > 0).
        vel_end_thresh:   Velocity threshold indicating near-zero velocity at rep end.
        min_duration_s:   Minimum total rep duration to reject noise.
        min_concentric_duration_s: Minimum ascent duration.
        min_displacement_m: Minimum vertical range of motion.
        max_packet_loss_pct: Packet loss threshold above which data_quality is flagged.

    Returns:
        List of RepMetrics objects for each detected rep.
    """
    n_samples = len(velocity_z)
    if n_samples < 10:
        return []

    reps: List[RepMetrics] = []

    # States: 0 = IDLE/READY, 1 = ECCENTRIC (descent), 2 = CONCENTRIC (ascent)
    state = 0
    start_idx = 0
    turnaround_idx = 0
    rep_counter = 1
    reached_concentric_threshold = False

    for i in range(1, n_samples):
        v = float(velocity_z[i])
        is_stat = bool(stationary_mask[i])

        if state == 0:
            # Look for start of downward motion after or during stationary
            if v <= vel_start_thresh:
                # Find preceding stationary anchor point (within last ~15 samples)
                anchor = i
                for k in range(i - 1, max(-1, i - 15), -1):
                    if stationary_mask[k]:
                        anchor = k
                        break
                start_idx = anchor
                reached_concentric_threshold = False
                state = 1  # In Eccentric Phase

        elif state == 1:
            # During eccentric descent, watch for velocity turnaround (inflection point to upward motion)
            if v >= 0.0:
                # Find exact local minimum velocity in the eccentric window
                ecc_window = velocity_z[start_idx:i+1]
                local_min_offset = int(np.argmin(ecc_window))
                turnaround_idx = start_idx + local_min_offset
                reached_concentric_threshold = False
                state = 2  # Transition to Concentric Phase

        elif state == 2:
            # Track whether meaningful upward concentric velocity has been achieved
            if v >= vel_concentric_thresh:
                reached_concentric_threshold = True

            # Rep finishes at lockout when:
            # 1. Concentric upward threshold was reached, AND
            # 2. Velocity returns to rest (is_stat or near-zero after peak)
            is_near_zero = abs(v) <= vel_end_thresh
            is_lockout = reached_concentric_threshold and (is_stat or (is_near_zero and i > turnaround_idx + 8))

            # Timeout / aborted rep if stuck without ascending for too long (> 4 seconds)
            is_timeout = (i - turnaround_idx) > 400 and not reached_concentric_threshold

            if is_lockout:
                end_idx = i
                t_start = float(time_s[start_idx])
                t_turn = float(time_s[turnaround_idx])
                t_end = float(time_s[end_idx])

                tot_dur = t_end - t_start
                ecc_dur = t_turn - t_start
                conc_dur = t_end - t_turn

                # Concentric velocity slice
                conc_vel = velocity_z[turnaround_idx:end_idx + 1]

                # Check minimum duration constraints
                if tot_dur >= min_duration_s and conc_dur >= min_concentric_duration_s and len(conc_vel) > 0:
                    peak_conc_vel = float(np.max(conc_vel))
                    rom = float(np.ptp(position_z[start_idx:end_idx + 1]))

                    # Must satisfy minimum displacement (ROM) and concentric threshold
                    if rom >= min_displacement_m and peak_conc_vel >= vel_concentric_thresh:
                        # Mean concentric velocity: average of positive upward velocity points
                        pos_conc_vel = conc_vel[conc_vel > 0.0]
                        mean_conc_vel = float(np.mean(pos_conc_vel)) if len(pos_conc_vel) > 0 else float(np.mean(conc_vel))

                        # Assess data quality
                        data_quality = "CLEAN"

                        # Check stationary bounding (allows rolling window ~25 samples to settle)
                        stat_start_clean = bool(np.any(stationary_mask[max(0, start_idx-25):min(n_samples, start_idx+5)]))
                        stat_end_clean = bool(np.any(stationary_mask[max(0, end_idx-5):min(n_samples, end_idx+25)]))

                        if not (stat_start_clean and stat_end_clean):
                            data_quality = "NOISY"

                        # Check packet loss if sequence numbers provided
                        if seq_numbers is not None and len(seq_numbers) == n_samples:
                            rep_seqs = seq_numbers[start_idx:end_idx + 1]
                            if len(rep_seqs) > 1:
                                expected_pkts = int((rep_seqs[-1] - rep_seqs[0]) % 65536) + 1
                                actual_pkts = len(rep_seqs)
                                lost_pkts = max(0, expected_pkts - actual_pkts)
                                loss_pct = (lost_pkts / expected_pkts) * 100.0 if expected_pkts > 0 else 0.0
                                if loss_pct > max_packet_loss_pct:
                                    data_quality = "PACKET_LOSS"

                        rep = RepMetrics(
                            rep_number=rep_counter,
                            start_idx=start_idx,
                            turnaround_idx=turnaround_idx,
                            end_idx=end_idx,
                            start_time_s=round(t_start, 3),
                            turnaround_time_s=round(t_turn, 3),
                            end_time_s=round(t_end, 3),
                            duration_ms=round(tot_dur * 1000.0, 1),
                            eccentric_duration_ms=round(ecc_dur * 1000.0, 1),
                            concentric_duration_ms=round(conc_dur * 1000.0, 1),
                            mean_concentric_velocity=round(mean_conc_vel, 3),
                            peak_concentric_velocity=round(peak_conc_vel, 3),
                            estimated_displacement=round(rom, 3),
                            data_quality=data_quality,
                        )
                        reps.append(rep)
                        rep_counter += 1

                state = 0


            elif is_timeout:
                state = 0


    return reps
