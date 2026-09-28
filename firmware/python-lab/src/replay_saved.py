"""
replay_saved.py  —  Offline VBT Capture Replay & Analysis
──────────────────────────────────────────────────────────
CLI tool to load a previously recorded raw IMU capture CSV, execute the
complete VBT pipeline offline, print the formatted Rep metrics table,
and generate a high-resolution multi-panel analysis figure.

Usage:
    python python-lab/src/replay_saved.py --input path/to/capture.csv
"""

import argparse
import sys
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")  # Non-interactive backend for file saving
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

from config import DEFAULT_CONFIG, VBTConfig
from pipeline import process_session, PipelineResult


def load_capture_csv(csv_path: Path):
    """Load raw IMU samples from CSV file."""
    if not csv_path.exists():
        raise FileNotFoundError(f"Capture file not found: {csv_path}")

    # Expected columns: timestamp_ms (or time_s), ax, ay, az, gx, gy, gz, (optional seq)
    data = np.genfromtxt(csv_path, delimiter=",", names=True, dtype=float)

    col_names = [name.lower() for name in data.dtype.names]
    
    # Map common column name variations
    def find_col(candidates):
        for c in candidates:
            if c.lower() in col_names:
                return data[data.dtype.names[col_names.index(c.lower())]]
        return None

    ts = find_col(["ts_ms", "timestamp_ms", "timestamp", "time_ms", "time_s", "time"])
    ax = find_col(["ax", "acc_x", "accel_x", "ax_ms2", "accel_x_ms2", "acc_x_ms2"])
    ay = find_col(["ay", "acc_y", "accel_y", "ay_ms2", "accel_y_ms2", "acc_y_ms2"])
    az = find_col(["az", "acc_z", "accel_z", "az_ms2", "accel_z_ms2", "acc_z_ms2"])
    gx = find_col(["gx", "gyr_x", "gyro_x", "gx_dps", "gyro_x_dps", "gyr_x_dps"])
    gy = find_col(["gy", "gyr_y", "gyro_y", "gy_dps", "gyro_y_dps", "gyr_y_dps"])
    gz = find_col(["gz", "gyr_z", "gyro_z", "gz_dps", "gyro_z_dps", "gyr_z_dps"])
    seq = find_col(["seq", "seq_num", "sequence", "seq_no"])

    if any(v is None for v in [ts, ax, ay, az, gx, gy, gz]):
        # Try positional loading without headers
        raw_arr = np.genfromtxt(csv_path, delimiter=",", skip_header=0)
        if raw_arr.ndim == 2 and raw_arr.shape[1] >= 7:
            ts = raw_arr[:, 0]
            ax, ay, az = raw_arr[:, 1], raw_arr[:, 2], raw_arr[:, 3]
            gx, gy, gz = raw_arr[:, 4], raw_arr[:, 5], raw_arr[:, 6]
            seq = raw_arr[:, 7] if raw_arr.shape[1] >= 8 else None
        else:
            raise ValueError(f"Could not parse required columns from {csv_path}")

    samples = {
        "ts_ms": ts,
        "ax": ax, "ay": ay, "az": az,
        "gx": gx, "gy": gy, "gz": gz,
    }
    if seq is not None:
        samples["seq"] = seq

    return samples


def print_rep_table(result: PipelineResult, file_name: str):
    """Print clean ASCII table of detected reps and velocity loss."""
    print("\n" + "=" * 92)
    print(f"  IRONLOOP VBT REPLAY ANALYSIS -- {file_name}")
    print("=" * 92)

    if not result.reps:
        print("  No completed reps detected with current threshold settings.")
        print("=" * 92 + "\n")
        return

    headers = [
        "Rep #", "Start (s)", "Turn (s)", "End (s)", "Tot (ms)",
        "Ecc (ms)", "Conc (ms)", "MCV (m/s)", "PV (m/s)", "ROM (m)", "Quality"
    ]
    print(f"  {headers[0]:<6} {headers[1]:<10} {headers[2]:<10} {headers[3]:<9} {headers[4]:<9} "
          f"{headers[5]:<9} {headers[6]:<10} {headers[7]:<10} {headers[8]:<9} {headers[9]:<8} {headers[10]:<8}")
    print("  " + "-" * 88)

    best_mcv = max(r.mean_concentric_velocity for r in result.reps)

    for r in result.reps:
        print(
            f"  {r.rep_number:<6d} "
            f"{r.start_time_s:<10.2f} "
            f"{r.turnaround_time_s:<10.2f} "
            f"{r.end_time_s:<9.2f} "
            f"{r.duration_ms:<9.0f} "
            f"{r.eccentric_duration_ms:<9.0f} "
            f"{r.concentric_duration_ms:<10.0f} "
            f"{r.mean_concentric_velocity:<10.3f} "
            f"{r.peak_concentric_velocity:<9.3f} "
            f"{r.estimated_displacement:<8.3f} "
            f"{r.data_quality:<8}"
        )

    print("  " + "-" * 88)
    print(f"  Best Mean Concentric Velocity: {best_mcv:.3f} m/s")
    if len(result.reps) > 1:
        last_mcv = result.reps[-1].mean_concentric_velocity
        vl_pct = ((best_mcv - last_mcv) / best_mcv) * 100.0 if best_mcv > 0 else 0.0
        print(f"  Set Velocity Loss:             {vl_pct:.1f}%")
    print("=" * 92 + "\n")


def generate_analysis_plot(result: PipelineResult, output_path: Path, title: str):
    """Generate and save multi-panel analysis figure."""
    t = result.time_s
    fig, axes = plt.subplots(4, 1, figsize=(13, 10), sharex=True)
    fig.patch.set_facecolor("#111625")

    colors = {
        "bg": "#182234",
        "grid": "#24334a",
        "text": "#e0e6ed",
        "subtext": "#94a3b8",
        "ax": "#f43f5e", "ay": "#10b981", "az": "#38bdf8",
        "vel": "#00f0ff",
        "rom": "#a855f7",
        "filt": "#fbbf24",
        "ecc": "#f43f5e",
        "conc": "#10b981",
    }

    for ax in axes:
        ax.set_facecolor(colors["bg"])
        ax.grid(True, linestyle="--", alpha=0.3, color=colors["grid"])
        ax.tick_params(colors=colors["subtext"])
        for spine in ax.spines.values():
            spine.set_color(colors["grid"])

    # ── Panel 1: Raw Accelerometer & Gyroscope ────────────────────────────────
    ax1 = axes[0]
    ax1.plot(t, result.accel_raw[:, 0], color=colors["ax"], label="ax", lw=1.0)
    ax1.plot(t, result.accel_raw[:, 1], color=colors["ay"], label="ay", lw=1.0)
    ax1.plot(t, result.accel_raw[:, 2], color=colors["az"], label="az", lw=1.0)
    ax1.set_ylabel("Raw Accel (m/s²)", color=colors["text"])
    ax1.set_title(f"IronLoop VBT Analysis — {title}", color="white", fontsize=13, weight="bold")
    ax1.legend(loc="upper right", facecolor=colors["bg"], labelcolor=colors["text"], fontsize=8)

    # ── Panel 2: World Linear Acceleration (Gravity Removed) ──────────────────
    ax2 = axes[1]
    ax2.plot(t, result.linear_accel_z_raw, color="#64748b", alpha=0.5, label="a_z (raw world)", lw=0.8)
    ax2.plot(t, result.linear_accel_z_filt, color=colors["filt"], label="a_z (Savitzky-Golay)", lw=1.3)
    ax2.axhline(0.0, color="#64748b", linestyle=":", lw=0.8)
    ax2.set_ylabel("Linear a_z (m/s²)", color=colors["text"])
    ax2.legend(loc="upper right", facecolor=colors["bg"], labelcolor=colors["text"], fontsize=8)

    # ── Panel 3: Vertical Velocity with ZUPT & Rep Shading ────────────────────
    ax3 = axes[2]
    ax3.plot(t, result.velocity_z, color=colors["vel"], lw=1.5, label="v_z (ZUPT corrected)")
    ax3.axhline(0.0, color="#64748b", linestyle="--", lw=0.8)

    # Highlight Reps: Eccentric (red) and Concentric (green)
    for r in result.reps:
        ax3.axvspan(r.start_time_s, r.turnaround_time_s, color=colors["ecc"], alpha=0.2)
        ax3.axvspan(r.turnaround_time_s, r.end_time_s, color=colors["conc"], alpha=0.25)
        # Rep badge text
        ax3.text(
            r.turnaround_time_s, max(0.2, r.peak_concentric_velocity * 0.8),
            f"R{r.rep_number}: {r.mean_concentric_velocity:.2f} m/s",
            color="white", fontsize=8, weight="bold", ha="center",
            bbox=dict(boxstyle="round,pad=0.2", facecolor="#1e293b", edgecolor=colors["conc"], alpha=0.85)
        )

    ecc_patch = mpatches.Patch(color=colors["ecc"], alpha=0.3, label="Eccentric Descent")
    conc_patch = mpatches.Patch(color=colors["conc"], alpha=0.4, label="Concentric Ascent")
    handles, labels = ax3.get_legend_handles_labels()
    handles.extend([ecc_patch, conc_patch])
    ax3.legend(handles=handles, loc="upper right", facecolor=colors["bg"], labelcolor=colors["text"], fontsize=8)
    ax3.set_ylabel("Velocity (m/s)", color=colors["text"])

    # ── Panel 4: Vertical Displacement (ROM) ──────────────────────────────────
    ax4 = axes[3]
    ax4.plot(t, result.position_z, color=colors["rom"], lw=1.4, label="Displacement (meters)")
    ax4.set_ylabel("ROM (m)", color=colors["text"])
    ax4.set_xlabel("Time (seconds)", color=colors["text"])
    ax4.legend(loc="upper right", facecolor=colors["bg"], labelcolor=colors["text"], fontsize=8)

    plt.tight_layout()
    plt.savefig(output_path, dpi=200, facecolor=fig.get_facecolor(), edgecolor="none")
    plt.close(fig)
    print(f"  [SAVED] Analysis plot -> {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Replay saved IronLoop raw capture and evaluate VBT pipeline.")
    parser.add_argument("--input", "-i", type=str, required=True, help="Path to input capture CSV file")
    parser.add_argument("--output", "-o", type=str, default=None, help="Optional output image path")
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: input file '{input_path}' does not exist.")
        sys.exit(1)

    print(f"\n[INFO] Loading capture from: {input_path}")
    samples = load_capture_csv(input_path)

    print("[INFO] Processing through VBT pipeline...")
    result = process_session(samples=samples, config=DEFAULT_CONFIG)

    print_rep_table(result, input_path.name)

    plot_output = Path(args.output) if args.output else input_path.with_name(f"{input_path.stem}_analysis.png")
    generate_analysis_plot(result, plot_output, input_path.stem)


if __name__ == "__main__":
    main()
