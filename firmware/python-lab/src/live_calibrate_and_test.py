"""
live_calibrate_and_test.py  —  Live BLE Gym Calibration & VBT Streaming
─────────────────────────────────────────────────────────────────────────
Live testing tool for IronLoop at the gym:
  1. Connects to IronLoop BLE peripheral.
  2. Discovers Command characteristic and writes 0x03 (CALIBRATE).
  3. Pauses 3.5s for stationary sensor calibration on the board.
  4. Streams 100 Hz IMU telemetry in real time.
  5. Continuously feeds data through the pure `pipeline.process_session()` chain.
  6. Prints live rep notifications the moment a barbell rep finishes.
  7. Saves every raw sample and all rep metrics to timestamped CSV files under
     `python-lab/data/real_captures/` for future offline replay and tuning.

Usage:
    python python-lab/src/live_calibrate_and_test.py
"""

import asyncio
import csv
from datetime import datetime
import math
from pathlib import Path
import struct
import sys
import time

from bleak import BleakScanner, BleakClient

from config import (
    SERVICE_UUID,
    IMU_CHAR_UUID,
    CMD_CHAR_UUID,
    CMD_CALIBRATE,
    CAPTURES_DIR,
    DEFAULT_CONFIG,
)
from pipeline import process_session

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

# ── Packet format (20 bytes, little-endian) ───────────────────────────────────
PKT_FMT = "<BHIhhhhhhB"
PKT_SIZE = struct.calcsize(PKT_FMT)
ACCEL_SCALE = 1000.0  # raw int16 -> m/s²
GYRO_SCALE = 100.0    # raw int16 -> °/s


def crc8_maxim(data: bytes) -> int:
    """CRC-8/MAXIM (Dallas/1-Wire). Poly=0x31, Init=0x00, RefIn=RefOut=True."""
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8C if crc & 0x01 else crc >> 1
    return crc


# ── Global streaming state ────────────────────────────────────────────────────
raw_records = []
total_packets_rx = 0
crc_errors = 0
last_reported_rep_idx = 0
calibration_completed = False


def decode_packet(data: bytearray):
    """Decode raw BLE packet and verify CRC."""
    global crc_errors
    if len(data) != PKT_SIZE:
        return None

    received_crc = data[-1]
    computed_crc = crc8_maxim(data[:-1])
    if received_crc != computed_crc:
        crc_errors += 1
        return None

    ver, seq, ts, ax, ay, az, gx, gy, gz, _ = struct.unpack(PKT_FMT, data)
    return {
        "ts_ms": ts,
        "ax": ax / ACCEL_SCALE,
        "ay": ay / ACCEL_SCALE,
        "az": az / ACCEL_SCALE,
        "gx": gx / GYRO_SCALE,
        "gy": gy / GYRO_SCALE,
        "gz": gz / GYRO_SCALE,
        "seq": seq,
    }


def on_imu_packet(_sender, data: bytearray):
    """BLE notification callback — decode packet and store."""
    global total_packets_rx, raw_records
    sample = decode_packet(data)
    if sample is None:
        return

    total_packets_rx += 1
    raw_records.append(sample)


async def live_pipeline_loop():
    """Background task evaluating streaming samples with VBT pipeline."""
    global raw_records, last_reported_rep_idx

    print("[INFO] VBT Rep Detector active — perform your squat set...\n")

    while True:
        await asyncio.sleep(0.10)  # Check every 100 ms

        n = len(raw_records)
        if n < 50:
            continue

        # Prepare batch dict for pipeline
        recent_data = {
            "ts_ms": [s["ts_ms"] for s in raw_records],
            "ax": [s["ax"] for s in raw_records],
            "ay": [s["ay"] for s in raw_records],
            "az": [s["az"] for s in raw_records],
            "gx": [s["gx"] for s in raw_records],
            "gy": [s["gy"] for s in raw_records],
            "gz": [s["gz"] for s in raw_records],
            "seq": [s["seq"] for s in raw_records],
        }

        try:
            result = process_session(samples=recent_data, config=DEFAULT_CONFIG)
        except Exception as e:
            continue

        # Check for newly completed reps
        if len(result.reps) > last_reported_rep_idx:
            for r in result.reps[last_reported_rep_idx:]:
                print(
                    f"\n{'='*70}\n"
                    f"  >>> [REP #{r.rep_number} COMPLETED] <<<\n"
                    f"  Mean Concentric Velocity (MCV) : {r.mean_concentric_velocity:.3f} m/s\n"
                    f"  Peak Concentric Velocity (PV)  : {r.peak_concentric_velocity:.3f} m/s\n"
                    f"  Range of Motion (ROM)          : {r.estimated_displacement:.2f} m\n"
                    f"  Concentric Duration            : {r.concentric_duration_ms:.0f} ms\n"
                    f"  Data Quality                   : {r.data_quality}\n"
                    f"{'='*70}\n"
                )
            last_reported_rep_idx = len(result.reps)


def save_session_csv(session_tag: str):
    """Save raw capture and rep summary to CSV."""
    CAPTURES_DIR.mkdir(parents=True, exist_ok=True)

    raw_csv_path = CAPTURES_DIR / f"raw_capture_{session_tag}.csv"
    rep_csv_path = CAPTURES_DIR / f"reps_{session_tag}.csv"

    if raw_records:
        with open(raw_csv_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=["ts_ms", "ax", "ay", "az", "gx", "gy", "gz", "seq"])
            writer.writeheader()
            writer.writerows(raw_records)
        print(f"  [SAVED] Raw capture ({len(raw_records)} samples) -> {raw_csv_path}")

        # Run final pipeline on full set
        full_data = {
            "ts_ms": [s["ts_ms"] for s in raw_records],
            "ax": [s["ax"] for s in raw_records],
            "ay": [s["ay"] for s in raw_records],
            "az": [s["az"] for s in raw_records],
            "gx": [s["gx"] for s in raw_records],
            "gy": [s["gy"] for s in raw_records],
            "gz": [s["gz"] for s in raw_records],
            "seq": [s["seq"] for s in raw_records],
        }
        res = process_session(full_data, config=DEFAULT_CONFIG)

        if res.reps:
            with open(rep_csv_path, "w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=list(res.reps[0].to_dict().keys()))
                writer.writeheader()
                for r in res.reps:
                    writer.writerow(r.to_dict())
            print(f"  [SAVED] Rep metrics ({len(res.reps)} reps)     -> {rep_csv_path}")


async def main():
    session_tag = datetime.now().strftime("%Y%m%d_%H%M%S")
    print("\n" + "=" * 70)
    print(f"  IRONLOOP LIVE CALIBRATE & VBT TESTER  (Session: {session_tag})")
    print("=" * 70)

    print(f"[INFO] Scanning for BLE peripheral 'IronLoop'...")
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

        # ── 1. Send CALIBRATE command (0x03) ──────────────────────────────────
        print("\n[CMD]  Sending CALIBRATE command (0x03)...")
        print("[CMD]  HOLD SENSOR COMPLETELY STILL FOR 3 SECONDS...")
        try:
            await client.write_gatt_char(CMD_CHAR_UUID, bytes([CMD_CALIBRATE]), response=False)
            print("[CMD]  Calibrate command dispatched successfully.")
        except Exception as e:
            print(f"[WARN] Failed to write to CMD char ({e}) — continuing.")

        # Wait 3.5 seconds for on-board stationary calibration
        await asyncio.sleep(3.5)
        print("[INFO] Calibration complete! Starting live IMU streaming.")

        # ── 2. Subscribe to IMU data ──────────────────────────────────────────
        await client.start_notify(IMU_CHAR_UUID, on_imu_packet)

        # ── 3. Run live pipeline loop ─────────────────────────────────────────
        pipe_task = asyncio.create_task(live_pipeline_loop())

        try:
            while True:
                await asyncio.sleep(1)
        except (KeyboardInterrupt, asyncio.CancelledError):
            pass
        finally:
            pipe_task.cancel()
            try:
                await pipe_task
            except (asyncio.CancelledError, Exception):
                pass
            await client.stop_notify(IMU_CHAR_UUID)

    print("\n" + "=" * 70)
    print("  SESSION SUMMARY")
    print(f"  Total samples captured : {len(raw_records)}")
    print(f"  Total CRC errors       : {crc_errors}")
    save_session_csv(session_tag)
    print("=" * 70 + "\n")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
