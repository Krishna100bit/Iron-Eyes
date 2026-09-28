"""
test_vbt_pipeline.py  —  Unit & Integration Tests for IronLoop Phase-2 VBT Pipeline
───────────────────────────────────────────────────────────────────────────────────
Tests all deterministic signal processing components:
  1. Mahony AHRS Orientation Filter
  2. World Frame Gravity Removal
  3. Savitzky-Golay Filtering
  4. Dual-threshold Stationary Detection
  5. Zero-Velocity Update (ZUPT) Integrator
  6. Squat Rep Segmentation and VBT Metrics
  7. End-to-End Pipeline Execution on Synthetic Biomechanical Reps
  8. Offline CSV Replay and Plot Generation
"""

import sys
from pathlib import Path
import numpy as np

# Add src to path
SRC_DIR = Path(__file__).resolve().parent.parent / "src"
sys.path.insert(0, str(SRC_DIR))

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

from config import DEFAULT_CONFIG, VBTConfig
from orientation_filter import MahonyAHRS, compute_orientations_mahony
from gravity_removal import rotate_vector_by_quaternion, remove_gravity
from filtering import apply_savgol_filter
from stationary_detector import detect_stationary_periods
from zupt_integrator import integrate_with_zupt
from rep_detector import detect_squat_reps
from pipeline import process_session


def generate_synthetic_squat_set(
    sample_rate_hz: float = 100.0,
    n_reps: int = 3,
    rom_m: float = 0.50,
    concentric_duration_s: float = 0.75,
    eccentric_duration_s: float = 1.20,
    pause_duration_s: float = 0.50,
    rest_duration_s: float = 1.50,
) -> dict:
    """
    Generate realistic synthetic IMU timeseries data for a multi-rep squat set.
    """
    dt = 1.0 / sample_rate_hz
    g = 9.80665
    np.random.seed(42)

    time_pts = []
    ax_pts = []
    ay_pts = []
    az_pts = []
    gx_pts = []
    gy_pts = []
    gz_pts = []
    seq_pts = []

    curr_t = 0.0
    seq = 0

    # Initial rest
    n_initial = int(rest_duration_s * sample_rate_hz)
    for _ in range(n_initial):
        time_pts.append(curr_t)
        ax_pts.append(np.random.normal(0.0, 0.02))
        ay_pts.append(np.random.normal(0.0, 0.02))
        az_pts.append(g + np.random.normal(0.0, 0.02))  # stationary upright
        gx_pts.append(np.random.normal(0.0, 0.2))
        gy_pts.append(np.random.normal(0.0, 0.2))
        gz_pts.append(np.random.normal(0.0, 0.2))
        seq_pts.append(seq)
        seq += 1
        curr_t += dt

    for rep in range(n_reps):
        # 1. Eccentric phase (descent)
        # Displacement curve: z(t) = -rom * (1 - cos(pi * t / T_ecc)) / 2
        # a(t) = d²z/dt² = -rom * (pi/T_ecc)² * cos(pi * t / T_ecc) / 2
        n_ecc = int(eccentric_duration_s * sample_rate_hz)
        for i in range(n_ecc):
            t_rel = i * dt
            a_lin = -rom_m * (np.pi / eccentric_duration_s)**2 * np.cos(np.pi * t_rel / eccentric_duration_s) / 2.0
            time_pts.append(curr_t)
            ax_pts.append(np.random.normal(0.0, 0.02))
            ay_pts.append(np.random.normal(0.0, 0.02))
            az_pts.append(g + a_lin + np.random.normal(0.0, 0.03))
            gx_pts.append(np.random.normal(0.0, 0.3))
            gy_pts.append(np.random.normal(0.0, 0.3))
            gz_pts.append(np.random.normal(0.0, 0.3))
            seq_pts.append(seq)
            seq += 1
            curr_t += dt

        # 2. Bottom pause (turnaround)
        n_pause = int(pause_duration_s * sample_rate_hz)
        for _ in range(n_pause):
            time_pts.append(curr_t)
            ax_pts.append(np.random.normal(0.0, 0.02))
            ay_pts.append(np.random.normal(0.0, 0.02))
            az_pts.append(g + np.random.normal(0.0, 0.02))
            gx_pts.append(np.random.normal(0.0, 0.2))
            gy_pts.append(np.random.normal(0.0, 0.2))
            gz_pts.append(np.random.normal(0.0, 0.2))
            seq_pts.append(seq)
            seq += 1
            curr_t += dt

        # 3. Concentric phase (ascent)
        # a(t) = +rom * (pi/T_conc)² * cos(pi * t / T_conc) / 2
        n_conc = int(concentric_duration_s * sample_rate_hz)
        for i in range(n_conc):
            t_rel = i * dt
            a_lin = rom_m * (np.pi / concentric_duration_s)**2 * np.cos(np.pi * t_rel / concentric_duration_s) / 2.0
            time_pts.append(curr_t)
            ax_pts.append(np.random.normal(0.0, 0.02))
            ay_pts.append(np.random.normal(0.0, 0.02))
            az_pts.append(g + a_lin + np.random.normal(0.0, 0.03))
            gx_pts.append(np.random.normal(0.0, 0.3))
            gy_pts.append(np.random.normal(0.0, 0.3))
            gz_pts.append(np.random.normal(0.0, 0.3))
            seq_pts.append(seq)
            seq += 1
            curr_t += dt

        # 4. Lockout rest between reps
        n_rest = int(rest_duration_s * sample_rate_hz)
        for _ in range(n_rest):
            time_pts.append(curr_t)
            ax_pts.append(np.random.normal(0.0, 0.02))
            ay_pts.append(np.random.normal(0.0, 0.02))
            az_pts.append(g + np.random.normal(0.0, 0.02))
            gx_pts.append(np.random.normal(0.0, 0.2))
            gy_pts.append(np.random.normal(0.0, 0.2))
            gz_pts.append(np.random.normal(0.0, 0.2))
            seq_pts.append(seq)
            seq += 1
            curr_t += dt

    return {
        "ts_ms": np.array(time_pts) * 1000.0,
        "time_s": np.array(time_pts),
        "ax": np.array(ax_pts),
        "ay": np.array(ay_pts),
        "az": np.array(az_pts),
        "gx": np.array(gx_pts),
        "gy": np.array(gy_pts),
        "gz": np.array(gz_pts),
        "seq": np.array(seq_pts),
    }


def test_orientation_filter():
    """Test Mahony AHRS filter initialization and static convergence."""
    accel = np.array([0.0, 0.0, 9.80665])
    gyro = np.array([0.0, 0.0, 0.0])
    dt = 0.01

    filter_ahrs = MahonyAHRS(kp=0.5, ki=0.01)
    filter_ahrs.init_from_accel(accel)

    # Orientation should be aligned [1, 0, 0, 0]
    q = filter_ahrs.q
    assert np.isclose(q[0], 1.0, atol=1e-3)
    assert np.isclose(np.linalg.norm(q[1:]), 0.0, atol=1e-3)

    # Update for 100 steps
    for _ in range(100):
        q = filter_ahrs.update(accel, gyro, dt)

    assert np.isclose(np.linalg.norm(q), 1.0, atol=1e-5)
    print("  [OK] Mahony AHRS static test passed.")


def test_gravity_removal():
    """Test gravity removal on static sensor."""
    accel = np.array([[0.0, 0.0, 9.80665], [0.0, 0.0, 9.80665]])
    quats = np.array([[1.0, 0.0, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]])

    lin_accel_world, lin_z = remove_gravity(accel, quats)
    assert np.allclose(lin_accel_world, 0.0, atol=1e-3)
    assert np.allclose(lin_z, 0.0, atol=1e-3)
    print("  [OK] Gravity removal test passed.")


def test_filtering():
    """Test Savitzky-Golay filtering smoothness and shape preservation."""
    x = np.sin(np.linspace(0, 2 * np.pi, 100)) + np.random.normal(0, 0.1, 100)
    filtered = apply_savgol_filter(x, window_length=15, polyorder=3)
    assert len(filtered) == len(x)
    assert np.std(np.diff(filtered)) < np.std(np.diff(x))  # Smoothed
    print("  [OK] Savitzky-Golay filter test passed.")


def test_stationary_detector():
    """Test dual-threshold stationary classification."""
    n = 100
    # Still segment
    accel_still = np.tile([0.0, 0.0, 9.81], (n, 1)) + np.random.normal(0, 0.01, (n, 3))
    gyro_still = np.tile([0.0, 0.0, 0.0], (n, 1)) + np.random.normal(0, 0.1, (n, 3))

    mask_still, _, _ = detect_stationary_periods(accel_still, gyro_still)
    assert np.mean(mask_still) > 0.90  # Most should be True

    # Moving segment
    accel_moving = np.tile([0.0, 0.0, 9.81], (n, 1)) + np.random.normal(0, 1.5, (n, 3))
    gyro_moving = np.tile([0.0, 0.0, 0.0], (n, 1)) + np.random.normal(0, 20.0, (n, 3))

    mask_moving, _, _ = detect_stationary_periods(accel_moving, gyro_moving)
    assert np.mean(mask_moving) < 0.10  # Most should be False
    print("  [OK] Stationary detector test passed.")


def test_zupt_integrator():
    """Test ZUPT integrator resets velocity at stationary points."""
    dt = np.full(100, 0.01)
    lin_a = np.full(100, 1.0)  # constant 1 m/s² accel
    stat_mask = np.zeros(100, dtype=bool)
    stat_mask[50:] = True  # sensor stops at sample 50

    vel, pos = integrate_with_zupt(lin_a, dt, stat_mask)
    assert vel[49] > 0.40  # accelerated
    assert vel[50] == 0.0  # ZUPT clamped
    assert vel[99] == 0.0  # remained clamped
    print("  [OK] ZUPT integrator test passed.")


def test_end_to_end_squat_pipeline():
    """Test end-to-end VBT pipeline on synthetic 3-rep squat dataset."""
    sim_data = generate_synthetic_squat_set(
        sample_rate_hz=100.0,
        n_reps=3,
        rom_m=0.50,
        concentric_duration_s=0.75,
        eccentric_duration_s=1.20,
    )

    result = process_session(sim_data, config=DEFAULT_CONFIG)

    print(f"\n  [E2E TEST] Detected {len(result.reps)} reps (Expected: 3)")
    assert len(result.reps) == 3, f"Expected 3 reps, got {len(result.reps)}"

    for r in result.reps:
        print(
            f"    Rep {r.rep_number}: MCV={r.mean_concentric_velocity:.3f} m/s, "
            f"PV={r.peak_concentric_velocity:.3f} m/s, ROM={r.estimated_displacement:.2f} m, "
            f"Quality={r.data_quality}"
        )
        # Verify physical realism
        assert 0.35 <= r.mean_concentric_velocity <= 1.20, f"Unrealistic MCV: {r.mean_concentric_velocity}"
        assert 0.50 <= r.peak_concentric_velocity <= 1.80, f"Unrealistic PV: {r.peak_concentric_velocity}"
        assert 0.30 <= r.estimated_displacement <= 0.75, f"Unrealistic ROM: {r.estimated_displacement}"
        assert r.data_quality == "CLEAN"

    print("  [OK] End-to-end squat pipeline verification passed.")


def test_offline_csv_replay():
    """Save synthetic set to CSV and run replay_saved.py."""
    import csv
    from replay_saved import load_capture_csv, generate_analysis_plot

    captures_dir = SRC_DIR.parent / "data" / "real_captures"
    captures_dir.mkdir(parents=True, exist_ok=True)

    csv_path = captures_dir / "synthetic_squat_test.csv"
    plot_path = captures_dir / "synthetic_squat_test_analysis.png"

    sim_data = generate_synthetic_squat_set(n_reps=3)

    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["ts_ms", "ax", "ay", "az", "gx", "gy", "gz", "seq"])
        n = len(sim_data["ts_ms"])
        for i in range(n):
            writer.writerow([
                sim_data["ts_ms"][i],
                sim_data["ax"][i],
                sim_data["ay"][i],
                sim_data["az"][i],
                sim_data["gx"][i],
                sim_data["gy"][i],
                sim_data["gz"][i],
                sim_data["seq"][i],
            ])

    # Replay
    samples = load_capture_csv(csv_path)
    result = process_session(samples, config=DEFAULT_CONFIG)
    assert len(result.reps) == 3

    # Generate analysis plot
    generate_analysis_plot(result, plot_path, "Synthetic Squat Test")
    assert plot_path.exists() and plot_path.stat().st_size > 10000
    print(f"  [OK] Replay CSV and analysis plot generated -> {plot_path}")



def run_all_tests():
    print("\n========================================================")
    print("  RUNNING IRONLOOP PHASE-2 VBT PIPELINE TEST SUITE")
    print("========================================================")
    test_orientation_filter()
    test_gravity_removal()
    test_filtering()
    test_stationary_detector()
    test_zupt_integrator()
    test_end_to_end_squat_pipeline()
    test_offline_csv_replay()
    print("========================================================")
    print("  ALL TESTS PASSED SUCCESSFULLY (7/7)")
    print("========================================================\n")


if __name__ == "__main__":
    run_all_tests()
