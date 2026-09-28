#!/usr/bin/env python3
"""
dashboard.py  —  IronLoop Interactive VBT Terminal Dashboard
────────────────────────────────────────────────────────────
Single-file, keyboard-driven live terminal interface for IronLoop.
Connects over BLE, processes IMU streams through the VBT pipeline in real-time,
computes repetition metrics, updates live bar speed, and estimates 1RM (e1RM)
via linear regression on distinct barbell loads.

Implementation Note (Curses vs Rich):
  This dashboard uses Python's built-in `curses` module (with `windows-curses`
  on Windows platforms) for flicker-free, non-blocking single-keypress terminal
  rendering synchronized with an asyncio event loop. Curses provides deterministic
  cross-platform window positioning and sub-window text input without external
  keyboard-hook daemon permissions.

Keyboard Commands (Single keypress):
  [c] Calibrate   : Send CALIBRATE command (0x03) over BLE
  [s] Start       : Send START_SESSION (0x01) — auto-calibrates + streams
  [x] Stop        : Send STOP_SESSION (0x02)
  [l] Set load    : Prompt for barbell load in kg (tags all subsequent reps)
  [r] Reset set   : Reset current set's rep count & e1RM data (start fresh set)
  [q] Quit        : Cleanly disconnect BLE and save full session to CSVs
"""

import asyncio
import csv
import curses
import datetime
import os
import sys
import time
from pathlib import Path
from typing import List, Optional, Tuple

import numpy as np

# Adjust module search path for direct execution
sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import (
    VBTConfig,
    DEFAULT_CONFIG,
    MIN_VELOCITY_THRESHOLD_SQUAT,
    MIN_POINTS_FOR_E1RM,
    CAPTURES_DIR,
    battery_mv_to_percent,
)
from packet_parser import (
    PacketParser,
    ParsedStreamBatch,
    ParsedStatusPacket,
    ParsedSample,
    STATUS_FLAG_CALIBRATED,
    STATUS_FLAG_LOW_BATT,
    STATUS_FLAG_SESSION_ACTIVE,
    STATUS_FLAG_SENSOR_FAULT,
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
from load_velocity_engine import LoadVelocityEngine, E1RMResult, LoadVelocityPoint


class DashboardApp:
    """Manages BLE connection, VBT pipeline, e1RM engine, and curses UI."""

    def __init__(self, stdscr):
        self.stdscr = stdscr
        self.config = DEFAULT_CONFIG

        # BLE Client & State
        self.ble_client: Optional[IronLoopBLEClient] = None
        self.ble_status_text = "scanning..."
        self.is_connected = False
        self.is_reconnecting = False
        self.reconnect_attempt = 0
        self.max_reconnect_retries = 5

        # Hardware & Session Status
        self.battery_mv = 4200
        self.is_calibrated = False
        self.is_session_active = False
        self.has_sensor_fault = False
        self.session_state_text = "IDLE"

        # Load & Set Tracking
        self.current_load_kg: float = 100.0
        self.current_set_reps: List[Tuple[float, RepMetrics]] = []
        self.all_session_reps: List[Tuple[float, RepMetrics]] = []
        self.raw_samples_with_load: List[Tuple[ParsedSample, float]] = []

        # Real-time VBT Metrics
        self.live_bar_speed: float = 0.0
        self.last_rep_display: str = "None yet"
        self.last_pipeline_rep_count: int = 0

        # e1RM Load-Velocity Engine
        self.e1rm_engine = LoadVelocityEngine(
            exercise_name="squat",
            mvt_mps=self.config.min_velocity_threshold_squat,
            min_points=self.config.min_points_for_e1rm,
        )
        self.latest_e1rm: Optional[E1RMResult] = None

        # UI & Input state
        self.is_running = True
        self.prompt_active = False
        self.status_message = "Ready. Press [s] to start session or [c] to calibrate."
        self.status_message_expire = 0.0

        # Output Capture Paths
        self.capture_dir = CAPTURES_DIR
        self.capture_dir.mkdir(parents=True, exist_ok=True)
        self.session_timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

    # ── BLE Callbacks ──────────────────────────────────────────────────────────

    def on_batch_received(self, batch: ParsedStreamBatch):
        self.battery_mv = batch.battery_mv
        self.is_calibrated = batch.is_calibrated
        self.is_session_active = batch.is_session_active
        self.has_sensor_fault = bool(batch.device_status & STATUS_FLAG_SENSOR_FAULT)

        if self.is_session_active:
            self.session_state_text = "ACTIVE"
        elif self.session_state_text == "ACTIVE":
            self.session_state_text = "IDLE"

        # Accumulate raw samples tagged with current load
        for s in batch.samples:
            self.raw_samples_with_load.append((s, self.current_load_kg))

        # Run pipeline over rolling window
        self._process_pipeline_window()

    def on_status_received(self, status: ParsedStatusPacket):
        self.battery_mv = status.battery_mv
        self.is_calibrated = status.is_calibrated
        self.is_session_active = status.is_session_active
        self.has_sensor_fault = bool(status.device_status & STATUS_FLAG_SENSOR_FAULT)

        if self.has_sensor_fault:
            self.set_status_message("⚠️ SENSOR FAULT DETECTED: Check IMU wiring / board", duration_s=6.0)

        if self.is_session_active:
            self.session_state_text = "ACTIVE"
            self.ble_status_text = "CONNECTED, streaming"
        elif self.session_state_text == "Calibrating...":
            if self.is_calibrated:
                self.session_state_text = "ACTIVE"
                self.ble_status_text = "CONNECTED, streaming"
                self.set_status_message("✅ Calibration complete. Streaming active!", duration_s=3.0)

    # ── Signal Processing & Rep Detection ──────────────────────────────────────

    def _process_pipeline_window(self):
        n = len(self.raw_samples_with_load)
        if n < 30:
            return

        window_size = min(n, 1200)  # ~12 seconds rolling window
        window = self.raw_samples_with_load[-window_size:]

        samples_list = [item[0] for item in window]
        ts = np.array([s.timestamp_ms for s in samples_list], dtype=np.float64)
        ax = np.array([s.ax_ms2 for s in samples_list], dtype=np.float64)
        ay = np.array([s.ay_ms2 for s in samples_list], dtype=np.float64)
        az = np.array([s.az_ms2 for s in samples_list], dtype=np.float64)
        gx = np.array([s.gx_dps for s in samples_list], dtype=np.float64)
        gy = np.array([s.gy_dps for s in samples_list], dtype=np.float64)
        gz = np.array([s.gz_dps for s in samples_list], dtype=np.float64)
        seq = np.array([s.sequence_number for s in samples_list], dtype=np.int64)

        sample_dict = {
            "ts_ms": ts,
            "ax": ax, "ay": ay, "az": az,
            "gx": gx, "gy": gy, "gz": gz,
            "seq": seq,
        }

        try:
            result: PipelineResult = process_session(sample_dict, config=self.config)
            if len(result.velocity_z) > 0:
                self.live_bar_speed = float(result.velocity_z[-1])

            if self.is_session_active:
                self.session_state_text = "ACTIVE"

            # Detect newly completed reps
            if len(result.reps) > self.last_pipeline_rep_count:
                new_reps = result.reps[self.last_pipeline_rep_count:]
                for rep in new_reps:
                    self._on_rep_completed(rep)
                self.last_pipeline_rep_count = len(result.reps)

        except Exception as e:
            pass

    def _on_rep_completed(self, rep: RepMetrics):
        """Tag rep with current load, update last rep string, and feed e1RM engine."""
        load = self.current_load_kg
        self.current_set_reps.append((load, rep))
        self.all_session_reps.append((load, rep))

        # Format last rep display (e.g. "mean 0.71 m/s  peak 0.95 m/s  OK")
        quality_str = "OK" if rep.data_quality == "CLEAN" else rep.data_quality
        self.last_rep_display = (
            f"mean {rep.mean_concentric_velocity:.2f} m/s  "
            f"peak {rep.peak_concentric_velocity:.2f} m/s  "
            f"{quality_str}"
        )

        # Feed Part 4 e1RM engine
        self.latest_e1rm = self.e1rm_engine.add_rep(
            load_kg=load,
            mean_concentric_velocity=rep.mean_concentric_velocity,
            peak_concentric_velocity=rep.peak_concentric_velocity,
            data_quality=rep.data_quality,
            rep_number=len(self.all_session_reps),
            timestamp_s=rep.end_time_s,
        )

    # ── Command & UI Actions ───────────────────────────────────────────────────

    def set_status_message(self, msg: str, duration_s: float = 3.0):
        self.status_message = msg
        self.status_message_expire = time.time() + duration_s

    async def send_cmd_calibrate(self):
        if not self.is_connected or not self.ble_client:
            self.set_status_message("❌ BLE not connected!")
            return
        self.session_state_text = "Calibrating..."
        self.set_status_message("⚙️ Running 3s calibration... KEEP BARBELL STILL!")
        await self.ble_client.send_command(CMD_CALIBRATE)

    async def send_cmd_start(self):
        if not self.is_connected or not self.ble_client:
            self.set_status_message("❌ BLE not connected!")
            return
        self.session_state_text = "Calibrating..."
        self.set_status_message("🚀 Starting session... Auto-calibrating (3s)...")
        await self.ble_client.send_command(CMD_START_SESSION)

    async def send_cmd_stop(self):
        if not self.is_connected or not self.ble_client:
            self.set_status_message("❌ BLE not connected!")
            return
        self.session_state_text = "IDLE"
        self.set_status_message("⏹️ Session stopped.")
        await self.ble_client.send_command(CMD_STOP_SESSION)

    def reset_current_set(self):
        """Reset current set's rep count and e1RM working data without restarting session."""
        self.current_set_reps.clear()
        self.e1rm_engine.reset()
        self.latest_e1rm = self.e1rm_engine.compute_e1rm()
        self.last_rep_display = "None yet (set reset)"
        self.set_status_message("🔄 Current set data and e1RM reset. Ready for new set!")

    def prompt_set_load(self):
        """Sub-window / inline input for new load in kg."""
        curses.echo()
        curses.curs_set(1)
        self.stdscr.nodelay(False)

        h, w = self.stdscr.getmaxyx()
        prompt_win = curses.newwin(5, min(50, w - 4), max(0, h // 2 - 2), max(0, (w - 50) // 2))
        prompt_win.box()
        prompt_win.addstr(1, 2, "SET BARBELL LOAD", curses.A_BOLD)
        prompt_win.addstr(2, 2, f"Enter load in kg [current: {self.current_load_kg:g} kg]: ")
        prompt_win.refresh()

        try:
            user_input = prompt_win.getstr(3, 2, 10).decode("utf-8").strip()
            if user_input:
                new_load = float(user_input)
                if 0.0 < new_load <= 600.0:
                    self.current_load_kg = new_load
                    self.set_status_message(f"✅ Barbell load set to {self.current_load_kg:g} kg")
                else:
                    self.set_status_message("⚠️ Load must be between 1 and 600 kg")
        except Exception:
            self.set_status_message("⚠️ Invalid number entered")
        finally:
            del prompt_win
            curses.noecho()
            curses.curs_set(0)
            self.stdscr.nodelay(True)
            self.stdscr.clear()

    # ── Session CSV Persistence ────────────────────────────────────────────────

    def save_session_data(self):
        """Save raw samples and rep results with load tags to CSVs."""
        if not self.raw_samples_with_load and not self.all_session_reps:
            return None, None

        raw_csv = self.capture_dir / f"ironloop_raw_{self.session_timestamp}.csv"
        rep_csv = self.capture_dir / f"ironloop_reps_{self.session_timestamp}.csv"

        # 1. Write Raw Samples CSV
        if self.raw_samples_with_load:
            with open(raw_csv, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow(["ts_ms", "ax_ms2", "ay_ms2", "az_ms2", "gx_dps", "gy_dps", "gz_dps", "seq", "load_kg"])
                for s, load in self.raw_samples_with_load:
                    writer.writerow([
                        f"{s.timestamp_ms:.2f}",
                        f"{s.ax_ms2:.4f}",
                        f"{s.ay_ms2:.4f}",
                        f"{s.az_ms2:.4f}",
                        f"{s.gx_dps:.3f}",
                        f"{s.gy_dps:.3f}",
                        f"{s.gz_dps:.3f}",
                        s.sequence_number,
                        f"{load:.1f}",
                    ])

        # 2. Write Rep Metrics CSV
        if self.all_session_reps:
            with open(rep_csv, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow([
                    "rep_number", "load_kg", "mean_concentric_vel_mps", "peak_concentric_vel_mps",
                    "duration_ms", "concentric_duration_ms", "displacement_m", "data_quality"
                ])
                for idx, (load, rep) in enumerate(self.all_session_reps, start=1):
                    writer.writerow([
                        idx,
                        f"{load:.1f}",
                        f"{rep.mean_concentric_velocity:.3f}",
                        f"{rep.peak_concentric_velocity:.3f}",
                        f"{rep.duration_ms:.1f}",
                        f"{rep.concentric_duration_ms:.1f}",
                        f"{rep.estimated_displacement:.3f}",
                        rep.data_quality,
                    ])

        return raw_csv, rep_csv

    # ── Curses UI Renderer ─────────────────────────────────────────────────────

    def render(self):
        """Draw the exact IronLoop dashboard layout in curses."""
        self.stdscr.erase()
        h, w = self.stdscr.getmaxyx()
        box_w = 52

        # Format fields
        ble_str = f"[{self.ble_status_text}]"
        
        # Battery calculation via non-linear LiPo discharge curve
        batt_pct = battery_mv_to_percent(self.battery_mv)
        batt_v = self.battery_mv / 1000.0
        batt_str = f"{batt_pct}% ({batt_v:.2f}V)"
        cal_str = "YES" if self.is_calibrated else "NO"

        load_str = f"{self.current_load_kg:g} kg"
        speed_str = f"{self.live_bar_speed:+.2f} m/s"
        reps_set_cnt = len(self.current_set_reps)

        # e1RM line
        if self.latest_e1rm is None:
            e1rm_display = self.e1rm_engine.compute_e1rm().formatted_summary("squat")
        else:
            e1rm_display = self.latest_e1rm.formatted_summary("squat")

        # Visual Speed Bar
        bar_len = min(12, int(abs(self.live_bar_speed) * 10))
        bar_char = "▲" if self.live_bar_speed > 0 else "▼"
        bar_visual = (bar_char * bar_len).ljust(12)

        # Construct lines matching specification:
        # ┌─ IRONLOOP ─────────────────────────────────────┐
        # │ BLE: [scanning... / connecting.. / CONNECTED]  │
        # │ Batt: 87% (4.05V)        Calibrated: YES/NO    │
        # │ Session: IDLE / ACTIVE                         │
        # │ Load: 100 kg                                   │
        # ├────────────────────────────────────────────────┤
        # │ LIVE BAR SPEED:    0.74 m/s                    │
        # │ Last rep: mean 0.71 m/s  peak 0.95 m/s  OK     │
        # │ Reps this set: 4                               │
        # ├────────────────────────────────────────────────┤
        # │ e1RM (squat): 142 kg  (R²=0.91, n=6 points)    │
        # ├────────────────────────────────────────────────┤
        # │ [c] Calibrate  [s] Start  [x] Stop  [l] Set load│
        # │ [r] Reset set  [q] Quit                        │
        # └────────────────────────────────────────────────┘

        top_border = "┌─ IRONLOOP " + "─" * (box_w - 13) + "┐"
        mid_border = "├" + "─" * (box_w - 2) + "┤"
        bot_border = "└" + "─" * (box_w - 2) + "┘"

        lines = [
            top_border,
            f"│ BLE: {ble_str:<{box_w - 9}}│",
            f"│ Batt: {batt_str:<18} Calibrated: {cal_str:<13}│",
            f"│ Session: {self.session_state_text:<{box_w - 13}}│",
            f"│ Load: {load_str:<{box_w - 10}}│",
            mid_border,
            f"│ LIVE BAR SPEED:    {speed_str:<8} [{bar_visual}]    │",
            f"│ Last rep: {self.last_rep_display:<{box_w - 14}}│",
            f"│ Reps this set: {reps_set_cnt:<{box_w - 19}}│",
            mid_border,
            f"│ {e1rm_display:<{box_w - 4}}│",
            mid_border,
            f"│ [c] Calibrate  [s] Start  [x] Stop  [l] Set load │",
            f"│ [r] Reset set  [w] Wake/Reconnect   [q] Quit     │",
            bot_border,
        ]

        start_y = max(1, (h - len(lines) - 3) // 2)
        start_x = max(2, (w - box_w) // 2)

        for i, line in enumerate(lines):
            try:
                self.stdscr.addstr(start_y + i, start_x, line)
            except curses.error:
                pass

        # Status / Feedback line below box
        if time.time() < self.status_message_expire and self.status_message:
            try:
                self.stdscr.addstr(start_y + len(lines) + 1, start_x, f">> {self.status_message}", curses.A_BOLD)
            except curses.error:
                pass

        self.stdscr.refresh()


# ── Main Async Execution Loop ──────────────────────────────────────────────────

async def run_dashboard(stdscr):
    # Curses terminal setup
    curses.curs_set(0)
    stdscr.nodelay(True)
    stdscr.keypad(True)
    curses.noecho()

    app = DashboardApp(stdscr)

    # Instantiate BLE client
    app.ble_client = IronLoopBLEClient(
        on_batch_cb=app.on_batch_received,
        on_status_cb=app.on_status_received,
    )

    async def ble_reconnect_loop():
        """Background task managing initial connection and automatic reconnection."""
        while app.is_running:
            if not app.is_connected and not app.is_reconnecting:
                app.is_reconnecting = True
                app.reconnect_attempt += 1

                if app.reconnect_attempt == 1:
                    app.ble_status_text = "scanning..."
                else:
                    backoff = min(8.0, 1.0 * (1.5 ** (app.reconnect_attempt - 1)))
                    app.ble_status_text = f"DISCONNECTED — reconnecting ({app.reconnect_attempt}/{app.max_reconnect_retries})..."
                    await asyncio.sleep(backoff)

                try:
                    app.ble_status_text = "connecting..."
                    connected = await app.ble_client.scan_and_connect(timeout_s=10.0)
                    if connected:
                        app.is_connected = True
                        app.is_reconnecting = False
                        app.reconnect_attempt = 0
                        app.ble_status_text = "CONNECTED"
                        app.set_status_message("✅ Connected to IronLoop over BLE!")
                    else:
                        app.is_connected = False
                        app.is_reconnecting = False
                except Exception as e:
                    app.is_connected = False
                    app.is_reconnecting = False

            # Monitor disconnect flag from ble_client
            if app.ble_client and not app.ble_client.is_connected and app.is_connected:
                app.is_connected = False
                app.ble_status_text = "DISCONNECTED — reconnecting..."

            await asyncio.sleep(0.5)

    # Spawn background BLE task
    ble_task = asyncio.create_task(ble_reconnect_loop())

    # Main non-blocking curses UI & keypress loop (~15 Hz)
    try:
        while app.is_running:
            # Handle keypress
            try:
                ch = stdscr.getch()
            except Exception:
                ch = -1

            if ch != -1:
                key = chr(ch).lower() if 0 <= ch <= 255 else ""
                if key == "q":
                    app.is_running = False
                    break
                elif key == "c":
                    await app.send_cmd_calibrate()
                elif key == "s":
                    await app.send_cmd_start()
                elif key == "x":
                    await app.send_cmd_stop()
                elif key == "l":
                    app.prompt_set_load()
                elif key == "r":
                    app.reset_current_set()
                elif key == "w":
                    app.is_connected = False
                    app.is_reconnecting = False
                    app.reconnect_attempt = 0
                    app.ble_status_text = "scanning (manual wake)..."
                    app.set_status_message("🔍 Looking for IronLoop BLE signal...", duration_s=4.0)

            # Redraw dashboard
            app.render()
            await asyncio.sleep(0.06)

    finally:
        app.is_running = False
        ble_task.cancel()

        # Cleanly disconnect BLE
        if app.ble_client and app.ble_client.is_connected:
            try:
                await app.ble_client.send_command(CMD_STOP_SESSION)
                await asyncio.sleep(0.2)
                await app.ble_client.disconnect()
            except Exception:
                pass

        # Save session CSVs
        raw_csv, rep_csv = app.save_session_data()

        # Restore terminal before printing final summary
        curses.endwin()

        print("\n" + "=" * 60)
        print("  IRONLOOP — SESSION TERMINATED")
        print("=" * 60)
        print(f"  Total Reps Recorded : {len(app.all_session_reps)}")
        if app.latest_e1rm and app.latest_e1rm.is_valid:
            print(f"  Final e1RM (Squat)  : {app.latest_e1rm.e1rm_kg:.1f} kg (R²={app.latest_e1rm.r_squared:.2f})")
        if raw_csv and raw_csv.exists():
            print(f"  Raw Data Saved      : {raw_csv}")
        if rep_csv and rep_csv.exists():
            print(f"  Rep Metrics Saved   : {rep_csv}")
        print("=" * 60 + "\n")


def main():
    try:
        curses.wrapper(lambda stdscr: asyncio.run(run_dashboard(stdscr)))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
