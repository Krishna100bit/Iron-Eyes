#!/usr/bin/env python3
"""
live_session.py  —  IronLoop Live VBT Velocity Testing Environment
──────────────────────────────────────────────────────────────────
1. Connects to "IronLoop" BLE device.
2. Sends 0x01 (START_SESSION) -> Firmware runs auto-calibration for ~3s.
3. Awaits Status notification confirming "calibrated" bit is set.
4. Streams 78-byte batched IMU samples at 100 Hz through the VBT pipeline.
5. Continuously prints LIVE instantaneous bar speed at a smooth, readable rate (~10 Hz).
6. Instantly displays completed rep metrics (Mean Concentric Velocity, Peak Velocity, ROM, Quality).
7. Automatically saves raw data & rep metrics to timestamped CSVs in data/real_captures/.
8. On Ctrl+C / STOP: prints final session summary (Total Reps, Best MCV, Packet Loss %).
"""

import asyncio
import csv
import datetime
import math
import os
import sys
import time
from collections import deque
from pathlib import Path
from typing import List, Optional

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

import numpy as np

from config import VBTConfig, DEFAULT_CONFIG
from packet_parser import (
    PacketParser,
    ParsedStreamBatch,
    ParsedStatusPacket,
    ParsedSample,
    STATUS_FLAG_CALIBRATED,
    STATUS_FLAG_SESSION_ACTIVE,
    STATUS_FLAG_LOW_BATT,
)
from ble_client import (
    IronLoopBLEClient,
    CMD_START_SESSION,
    CMD_STOP_SESSION,
    CMD_CALIBRATE,
    CMD_PING,
)
from pipeline import process_session, PipelineResult
from rep_detector import RepMetrics


class LiveVBTManager:
    """Manages the live streaming, incremental VBT pipeline processing, display, and logging."""

    def __init__(self, config: VBTConfig = DEFAULT_CONFIG):
        self.config = config
        self.ble_client = IronLoopBLEClient(
            on_batch_cb=self._on_batch_received,
            on_status_cb=self._on_status_received,
        )

        # Buffer of accumulated samples for pipeline
        self.raw_samples: List[ParsedSample] = []
        self.completed_reps: List[RepMetrics] = []
        self.last_rep_count = 0

        # State tracking
        self.is_calibrated = False
        self.is_session_active = False
        self.current_battery_mv = 0
        self.is_low_battery = False

        # Live display state
        self.live_speed_ms = 0.0
        self.live_state_str = "CALIBRATING..."
        self.t_first_sample: Optional[float] = None
        self.t_last_display_update = 0.0

        # Output file paths
        self.capture_dir = Path(__file__).resolve().parent.parent / "data" / "real_captures"
        self.capture_dir.mkdir(parents=True, exist_ok=True)
        timestamp_str = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        self.raw_csv_path = self.capture_dir / f"ironloop_raw_{timestamp_str}.csv"
        self.rep_csv_path = self.capture_dir / f"ironloop_reps_{timestamp_str}.csv"

        # CSV writers
        self._raw_file = open(self.raw_csv_path, "w", newline="", encoding="utf-8")
        self._raw_writer = csv.writer(self._raw_file)
        self._raw_writer.writerow(["ts_ms", "ax", "ay", "az", "gx", "gy", "gz", "seq"])

        self._rep_file = open(self.rep_csv_path, "w", newline="", encoding="utf-8")
        self._rep_writer = csv.writer(self._rep_file)
        self._rep_writer.writerow([
            "rep_number", "mean_concentric_vel_mps", "peak_concentric_vel_mps",
            "duration_ms", "concentric_duration_ms", "displacement_m", "data_quality"
        ])

        self.calibration_event = asyncio.Event()

    def _on_status_received(self, status: ParsedStatusPacket):
        self.current_battery_mv = status.battery_mv
        self.is_low_battery = status.is_low_battery
        self.is_calibrated = status.is_calibrated
        self.is_session_active = status.is_session_active

        if self.is_calibrated and not self.calibration_event.is_set():
            self.calibration_event.set()

    def _on_batch_received(self, batch: ParsedStreamBatch):
        self.current_battery_mv = batch.battery_mv
        self.is_low_battery = batch.is_low_battery
        self.is_calibrated = batch.is_calibrated
        self.is_session_active = batch.is_session_active

        if self.t_first_sample is None and len(batch.samples) > 0:
            self.t_first_sample = time.time()

        for s in batch.samples:
            self.raw_samples.append(s)
            self._raw_writer.writerow([
                f"{s.timestamp_ms:.2f}",
                f"{s.ax_ms2:.4f}",
                f"{s.ay_ms2:.4f}",
                f"{s.az_ms2:.4f}",
                f"{s.gx_dps:.3f}",
                f"{s.gy_dps:.3f}",
                f"{s.gz_dps:.3f}",
                s.sequence_number,
            ])

        # Run pipeline incrementally over recent buffer (up to last 1500 samples = 15s)
        self._process_incremental_vbt()

    def _process_incremental_vbt(self):
        n = len(self.raw_samples)
        if n < 30:
            return

        # Use recent window to maintain real-time speed
        window_size = min(n, 1200)
        recent = self.raw_samples[-window_size:]

        ts = np.array([s.timestamp_ms for s in recent], dtype=np.float64)
        ax = np.array([s.ax_ms2 for s in recent], dtype=np.float64)
        ay = np.array([s.ay_ms2 for s in recent], dtype=np.float64)
        az = np.array([s.az_ms2 for s in recent], dtype=np.float64)
        gx = np.array([s.gx_dps for s in recent], dtype=np.float64)
        gy = np.array([s.gy_dps for s in recent], dtype=np.float64)
        gz = np.array([s.gz_dps for s in recent], dtype=np.float64)
        seq = np.array([s.sequence_number for s in recent], dtype=np.int64)

        sample_dict = {
            "ts_ms": ts,
            "ax": ax, "ay": ay, "az": az,
            "gx": gx, "gy": gy, "gz": gz,
            "seq": seq,
        }

        try:
            result: PipelineResult = process_session(sample_dict, config=self.config)
            if len(result.velocity_z) > 0:
                self.live_speed_ms = float(result.velocity_z[-1])

                # Determine dynamic state
                v = self.live_speed_ms
                if abs(v) < 0.05:
                    self.live_state_str = "STATIONARY / REST"
                elif v < -0.08:
                    self.live_state_str = "ECCENTRIC (DESCENDING)"
                elif v > 0.08:
                    self.live_state_str = "CONCENTRIC (ASCENDING)"
                else:
                    self.live_state_str = "TURNAROUND"

            # Check for new completed reps
            if len(result.reps) > self.last_rep_count:
                new_reps = result.reps[self.last_rep_count:]
                for rep in new_reps:
                    self.completed_reps.append(rep)
                    self._on_new_rep_completed(rep)
                self.last_rep_count = len(result.reps)

        except Exception as e:
            pass

    def _on_new_rep_completed(self, rep: RepMetrics):
        """Immediately display banner for new completed rep and log to CSV."""
        self._rep_writer.writerow([
            rep.rep_number,
            f"{rep.mean_concentric_velocity:.3f}",
            f"{rep.peak_concentric_velocity:.3f}",
            f"{rep.duration_ms:.1f}",
            f"{rep.concentric_duration_ms:.1f}",
            f"{rep.estimated_displacement:.3f}",
            rep.data_quality,
        ])
        self._rep_file.flush()

        print("\n" + "=" * 68)
        print(f"  🏆 REP {rep.rep_number:02d} COMPLETE!")
        print(f"  ├─ Mean Concentric Velocity : {rep.mean_concentric_velocity:.2f} m/s  (Primary VBT Metric)")
        print(f"  ├─ Peak Concentric Velocity : {rep.peak_concentric_velocity:.2f} m/s")
        print(f"  ├─ Concentric Duration      : {rep.concentric_duration_ms:.0f} ms  (Total: {rep.duration_ms:.0f} ms)")
        print(f"  ├─ Range of Motion (ROM)    : {rep.estimated_displacement * 100.0:.1f} cm")
        print(f"  └─ Data Quality             : {rep.data_quality}")
        print("=" * 68 + "\n")

    def update_live_terminal(self):
        """Prints live bar speed continuously at ~10 Hz without line clutter."""
        now = time.time()
        if now - self.t_last_display_update < 0.10:
            return
        self.t_last_display_update = now

        loss = self.ble_client.parser.packet_loss_percentage
        batt = self.current_battery_mv
        reps_cnt = len(self.completed_reps)

        speed_display = f"{self.live_speed_ms:+5.2f} m/s"
        bar_len = min(20, int(abs(self.live_speed_ms) * 15))
        bar_char = "▲" if self.live_speed_ms > 0 else "▼"
        bar_visual = (bar_char * bar_len).ljust(20)

        sys.stdout.write(
            f"\r[LIVE SPEED] {speed_display} [{bar_visual}] | "
            f"State: {self.live_state_str:<22} | Reps: {reps_cnt:02d} | "
            f"Batt: {batt}mV | Loss: {loss:.1f}%"
        )
        sys.stdout.flush()

    def close(self):
        """Flush and close CSV files."""
        try:
            self._raw_file.flush()
            self._raw_file.close()
            self._rep_file.flush()
            self._rep_file.close()
        except Exception:
            pass


async def run_live_session():
    print("""
======================================================================
  IRONLOOP — Live Barbell Velocity Testing Environment (VBT)
======================================================================
  • Instantaneous Bar Speed (m/s)
  • Mean & Peak Concentric Rep Velocity
  • Automatic Stationary Baseline Calibration
  • Real-time CSV logging to data/real_captures/
======================================================================
""")

    manager = LiveVBTManager()

    # 1. Connect to IronLoop
    connected = await manager.ble_client.scan_and_connect(timeout_s=15.0)
    if not connected:
        print("[ERR] Could not connect to IronLoop. Make sure the device is powered on.")
        return

    print("\n[INFO] Connected to IronLoop! Sending START_SESSION (0x01)...")
    await manager.ble_client.send_command(CMD_START_SESSION)

    print("[INFO] Firmware is running auto-calibration (3s stationary baseline)...")
    print("[INFO] KEEP THE BARBELL COMPLETELY STILL!")

    # 2. Await calibration confirmation
    try:
        await asyncio.wait_for(manager.calibration_event.wait(), timeout=8.0)
        print("\n[OK] Device CALIBRATED & SESSION ACTIVE! You may begin your set.\n")
    except asyncio.TimeoutError:
        print("\n[WARN] Calibration confirmation timeout, proceeding with live stream...\n")

    print("-" * 70)
    print("  Streaming live data. Perform your reps (Eccentric -> Concentric -> Pause).")
    print("  Press Ctrl+C to stop session and view summary.")
    print("-" * 70 + "\n")

    try:
        while manager.ble_client.is_connected:
            manager.update_live_terminal()
            await asyncio.sleep(0.05)
    except KeyboardInterrupt:
        print("\n\n[INFO] User requested session stop (Ctrl+C)...")
    finally:
        # Send STOP_SESSION command
        await manager.ble_client.send_command(CMD_STOP_SESSION)
        await asyncio.sleep(0.3)
        await manager.ble_client.disconnect()
        manager.close()

        # Print Final Session Summary
        total_reps = len(manager.completed_reps)
        total_samples = len(manager.raw_samples)
        loss_pct = manager.ble_client.parser.packet_loss_percentage

        best_mcv = 0.0
        best_pv = 0.0
        if total_reps > 0:
            best_mcv = max(r.mean_concentric_velocity for r in manager.completed_reps)
            best_pv = max(r.peak_concentric_velocity for r in manager.completed_reps)

        print("\n" + "=" * 60)
        print("  SESSION SUMMARY")
        print("=" * 60)
        print(f"  Total Reps Detected       : {total_reps}")
        if total_reps > 0:
            print(f"  Fastest Mean Velocity     : {best_mcv:.2f} m/s (Best Rep)")
            print(f"  Peak Concentric Velocity  : {best_pv:.2f} m/s")
        print(f"  Total Samples Logged      : {total_samples}")
        print(f"  Session Packet Loss       : {loss_pct:.2f}%")
        print(f"  Raw Data CSV Saved        : {manager.raw_csv_path}")
        print(f"  Rep Metrics CSV Saved     : {manager.rep_csv_path}")
        print("=" * 60 + "\n")


if __name__ == "__main__":
    try:
        asyncio.run(run_live_session())
    except KeyboardInterrupt:
        pass
