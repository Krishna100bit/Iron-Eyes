"""
phase3_live_vbt_streamer.py  —  IronLoop Phase-3 Live BLE Gym Streamer
───────────────────────────────────────────────────────────────────────
Full-featured Stage 5 & 6 interactive gym testing client:
  1. Connects to IronLoop BLE peripheral.
  2. Discovers GATT Characteristics (Stream, Command, Status).
  3. Subscribes to Status notifications (battery, device state).
  4. Triggers 3-second stationary calibration (0x03 CALIBRATE).
  5. Sends 0x01 START_SESSION to begin 100 Hz batched IMU streaming.
  6. Reconstructs 5 samples per batch with sub-ms timestamp accuracy.
  7. Live-plots rolling acceleration magnitude while VBT pipeline segments reps.
  8. Instant rep alert display (Mean Concentric Velocity, Peak Velocity, ROM).
  9. Saves raw captures and rep metrics to `python-lab/data/real_captures/`.

Usage:
    python python-lab/src/phase3_live_vbt_streamer.py
"""

import asyncio
import csv
from datetime import datetime
import math
from pathlib import Path
import struct
import sys
import time
from collections import deque

import matplotlib
matplotlib.use("TkAgg")
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from bleak import BleakScanner, BleakClient

from config import (
    SERVICE_UUID,
    IMU_CHAR_UUID as STREAM_CHAR_UUID,
    CMD_CHAR_UUID,
    CAPTURES_DIR,
    DEFAULT_CONFIG,
)
from ble_protocol_decoder import BatchedPacketDecoder, DecodedSample
from pipeline import process_session

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

STATUS_CHAR_UUID = "beb54840-36e1-4688-b7f5-ea07361b26a8"

# Commands
CMD_START_SESSION = 0x01
CMD_STOP_SESSION  = 0x02
CMD_CALIBRATE     = 0x03
CMD_PING          = 0x05

# Live plot configuration
WINDOW_S = 10
SAMPLE_HZ = 100
MAX_PTS = WINDOW_S * SAMPLE_HZ

# ── Global State ──────────────────────────────────────────────────────────────
decoder = BatchedPacketDecoder()
raw_samples_list = []
times_ms_deque = deque(maxlen=MAX_PTS)
magnitudes_deque = deque(maxlen=MAX_PTS)
last_reported_rep_count = 0
device_battery_mv = 4150
device_state_name = "IDLE"
session_start_time = None

# ── Matplotlib Live Figure Setup ──────────────────────────────────────────────
fig, ax_plot = plt.subplots(figsize=(10, 4.5))
fig.patch.set_facecolor("#111625")
ax_plot.set_facecolor("#182234")
ax_plot.set_title("IronLoop Phase-3 — Batched 100 Hz Stream (Stationary ≈ 9.81 m/s²)",
                  color="white", fontsize=11, weight="bold")
ax_plot.set_xlabel("Elapsed Time (ms)", color="#94a3b8")
ax_plot.set_ylabel("|a| (m/s²)", color="#94a3b8")
ax_plot.tick_params(colors="#94a3b8")
ax_plot.grid(True, linestyle="--", alpha=0.2, color="#334155")
ax_plot.axhline(9.80665, color="#10b981", linewidth=0.8, linestyle="--", label="g = 9.81 m/s²")
line, = ax_plot.plot([], [], color="#00f0ff", linewidth=1.2, label="|a| Accel Magnitude")
status_text = ax_plot.text(0.02, 0.90, "Connecting...", transform=ax_plot.transAxes,
                           color="#fbbf24", fontsize=9, weight="bold")
ax_plot.legend(loc="upper right", facecolor="#182234", labelcolor="white", fontsize=8)


def update_plot(_frame):
    if len(times_ms_deque) < 2:
        return line, status_text

    t0 = times_ms_deque[0]
    xs = [t - t0 for t in times_ms_deque]
    ys = list(magnitudes_deque)

    line.set_data(xs, ys)
    ax_plot.set_xlim(max(0, xs[-1] - WINDOW_S * 1000), xs[-1] + 200)
    lo = max(0.0, min(ys) - 1.5)
    hi = max(ys) + 1.5
    ax_plot.set_ylim(lo, hi)

    status_text.set_text(f"Status: {device_state_name} | Batt: {device_battery_mv/1000.0:.2f}V | Samples: {len(raw_samples_list)}")
    return line, status_text


# ── BLE Notification Handlers ─────────────────────────────────────────────────
def on_stream_notification(_sender, data: bytearray):
    """Callback receiving 78-byte batched IMU notifications."""
    global raw_samples_list, session_start_time

    batch = decoder.decode(bytes(data))
    if batch is None:
        return

    if session_start_time is None:
        session_start_time = time.time()

    for s in batch.samples:
        raw_samples_list.append(s)
        mag = math.sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az)
        times_ms_deque.append(s.ts_ms)
        magnitudes_deque.append(mag)


def on_status_notification(_sender, data: bytearray):
    """Callback receiving status characteristic updates."""
    global device_battery_mv, device_state_name
    if len(data) >= 4:
        state_code = data[0]
        status_flags = data[1]
        batt_mv = data[2] | (data[3] << 8)
        device_battery_mv = batt_mv

        state_map = {0: "IDLE", 1: "READY", 2: "CALIBRATING", 3: "SESSION_ACTIVE"}
        device_state_name = state_map.get(state_code, "UNKNOWN")
        print(f"[STATUS UPDATE] Device State: {device_state_name} | Battery: {batt_mv/1000.0:.2f}V | Flags: 0x{status_flags:02X}")


# ── Background VBT Rep Detection Task ────────────────────────────────────────
async def rep_detection_worker():
    """Continuously evaluates streaming IMU samples through pure VBT pipeline."""
    global raw_samples_list, last_reported_rep_count

    while True:
        await asyncio.sleep(0.10)

        n = len(raw_samples_list)
        if n < 60:
            continue

        sample_dict = {
            "ts_ms": [s.ts_ms for s in raw_samples_list],
            "ax": [s.ax for s in raw_samples_list],
            "ay": [s.ay for s in raw_samples_list],
            "az": [s.az for s in raw_samples_list],
            "gx": [s.gx for s in raw_samples_list],
            "gy": [s.gy for s in raw_samples_list],
            "gz": [s.gz for s in raw_samples_list],
            "seq": [s.seq for s in raw_samples_list],
        }

        try:
            res = process_session(sample_dict, config=DEFAULT_CONFIG)
            if len(res.reps) > last_reported_rep_count:
                for r in res.reps[last_reported_rep_count:]:
                    print(
                        f"\n{'='*72}\n"
                        f"  >>> [REP #{r.rep_number} COMPLETED] <<<\n"
                        f"  Mean Concentric Velocity (MCV) : {r.mean_concentric_velocity:.3f} m/s\n"
                        f"  Peak Concentric Velocity (PV)  : {r.peak_concentric_velocity:.3f} m/s\n"
                        f"  Range of Motion (ROM)          : {r.estimated_displacement:.2f} m\n"
                        f"  Concentric Duration            : {r.concentric_duration_ms:.0f} ms\n"
                        f"  Data Quality                   : {r.data_quality}\n"
                        f"{'='*72}\n"
                    )
                last_reported_rep_count = len(res.reps)
        except Exception:
            pass


# ── CSV Logging ───────────────────────────────────────────────────────────────
def save_session_results(session_tag: str):
    CAPTURES_DIR.mkdir(parents=True, exist_ok=True)
    raw_csv_path = CAPTURES_DIR / f"raw_batched_{session_tag}.csv"
    rep_csv_path = CAPTURES_DIR / f"reps_batched_{session_tag}.csv"

    if raw_samples_list:
        with open(raw_csv_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["ts_ms", "ax", "ay", "az", "gx", "gy", "gz", "seq"])
            for s in raw_samples_list:
                writer.writerow([s.ts_ms, s.ax, s.ay, s.az, s.gx, s.gy, s.gz, s.seq])
        print(f"  [SAVED] Raw capture ({len(raw_samples_list)} samples) -> {raw_csv_path}")

        # Run final pipeline on complete capture
        sample_dict = {
            "ts_ms": [s.ts_ms for s in raw_samples_list],
            "ax": [s.ax for s in raw_samples_list],
            "ay": [s.ay for s in raw_samples_list],
            "az": [s.az for s in raw_samples_list],
            "gx": [s.gx for s in raw_samples_list],
            "gy": [s.gy for s in raw_samples_list],
            "gz": [s.gz for s in raw_samples_list],
            "seq": [s.seq for s in raw_samples_list],
        }
        res = process_session(sample_dict, config=DEFAULT_CONFIG)
        if res.reps:
            with open(rep_csv_path, "w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=list(res.reps[0].to_dict().keys()))
                writer.writeheader()
                for r in res.reps:
                    writer.writerow(r.to_dict())
            print(f"  [SAVED] Rep metrics ({len(res.reps)} reps)      -> {rep_csv_path}")


# ── BLE Main Lifecycle ────────────────────────────────────────────────────────
async def ble_runner():
    session_tag = datetime.now().strftime("%Y%m%d_%H%M%S")
    print(f"\n[INFO] Scanning for 'IronLoop' BLE peripheral...")

    device = await BleakScanner.find_device_by_filter(
        lambda d, _adv: d.name == "IronLoop",
        timeout=15.0,
    )
    if device is None:
        print("[ERR]  'IronLoop' not found. Ensure board is powered and advertising.")
        return

    print(f"[INFO] Found: {device.name} ({device.address})")

    async with BleakClient(device) as client:
        print(f"[INFO] Connected [OK]  MTU={client.mtu_size} bytes")

        # 1. Subscribe to Status characteristic
        try:
            await client.start_notify(STATUS_CHAR_UUID, on_status_notification)
            print(f"[INFO] Subscribed to Status Characteristic")
        except Exception as e:
            print(f"[WARN] Status char subscription skipped ({e})")

        # 2. Trigger Stationary Calibration (0x03)
        print("\n[CMD]  Sending CALIBRATE command (0x03)...")
        print("[CMD]  HOLD SENSOR STILL FOR 3 SECONDS...")
        try:
            await client.write_gatt_char(CMD_CHAR_UUID, bytes([CMD_CALIBRATE]), response=False)
        except Exception as e:
            print(f"[WARN] Calibrate write failed: {e}")

        await asyncio.sleep(3.5)

        # 3. Subscribe to Batched Stream characteristic
        print(f"[INFO] Subscribing to Stream Characteristic ({STREAM_CHAR_UUID})...")
        await client.start_notify(STREAM_CHAR_UUID, on_stream_notification)

        # 4. Start Session (0x01)
        print("[CMD]  Sending START_SESSION command (0x01)...")
        try:
            await client.write_gatt_char(CMD_CHAR_UUID, bytes([CMD_START_SESSION]), response=False)
            print("[INFO] Session active — 100 Hz batched streaming started [OK]!\n")
        except Exception as e:
            print(f"[WARN] Start session write failed: {e}")

        # 5. Launch VBT rep detection worker
        rep_task = asyncio.create_task(rep_detection_worker())

        try:
            while True:
                await asyncio.sleep(1)
        except (KeyboardInterrupt, asyncio.CancelledError):
            pass
        finally:
            print("\n[CMD]  Stopping session (0x02)...")
            try:
                await client.write_gatt_char(CMD_CHAR_UUID, bytes([CMD_STOP_SESSION]), response=False)
            except Exception:
                pass
            rep_task.cancel()
            try:
                await rep_task
            except Exception:
                pass
            await client.stop_notify(STREAM_CHAR_UUID)

    print("\n" + "=" * 70)
    print("  SESSION SUMMARY")
    print(f"  Total Packets Received : {decoder.total_packets_rx}")
    print(f"  Total Samples Decoded  : {decoder.total_samples_rx}")
    print(f"  CRC Errors             : {decoder.crc_errors}")
    print(f"  Dropped Packets        : {decoder.dropped_packets}")
    save_session_results(session_tag)
    print("=" * 70 + "\n")


# ── Entry Point ───────────────────────────────────────────────────────────────
async def run_all():
    ble_task = asyncio.create_task(ble_runner())

    ani = animation.FuncAnimation(fig, update_plot, interval=50, blit=False, cache_frame_data=False)
    plt.tight_layout()
    plt.show(block=False)

    try:
        while not ble_task.done():
            plt.pause(0.04)
            await asyncio.sleep(0)
    except KeyboardInterrupt:
        pass
    finally:
        ble_task.cancel()
        try:
            await ble_task
        except Exception:
            pass


if __name__ == "__main__":
    try:
        asyncio.run(run_all())
    except KeyboardInterrupt:
        pass
