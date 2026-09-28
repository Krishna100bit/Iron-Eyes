#!/usr/bin/env python3
"""
phase1_raw_viewer.py  —  IronLoop BLE Real-time IMU Viewer
────────────────────────────────────────────────────────────
Scans for the "IronLoop" BLE peripheral, connects, subscribes to the
IMU notify characteristic (supports both 78-byte batched and 20-byte single packets),
and live-plots accel magnitude and 3-axis traces on a rolling 10-second window.

Dependencies:  pip install bleak matplotlib

Usage:
    python python-lab/src/phase1_raw_viewer.py
"""

# ── BLE UUIDs ──────────────────────────────────────────────────────────────
SERVICE_UUID  = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
IMU_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8"
CMD_CHAR_UUID = "beb5483f-36e1-4688-b7f5-ea07361b26a8"
# ──────────────────────────────────────────────────────────────────────────

import asyncio
import struct
import math
import time
import sys
import threading
from collections import deque

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

import matplotlib
try:
    matplotlib.use("TkAgg")
except Exception:
    pass
import matplotlib.pyplot as plt
from bleak import BleakScanner, BleakClient

# ── Packet Formats ─────────────────────────────────────────────────────────
# Single sample (20 bytes): <BHIhhhhhhB
PKT_FMT_SINGLE = "<BHIhhhhhhB"
PKT_SIZE_SINGLE = struct.calcsize(PKT_FMT_SINGLE)  # 20 bytes

# Batched samples (78 bytes):
# Header: <BBHIBBH (12 bytes)
# 5 * Sample: <hhhhhhB (13 bytes each)
# CRC: 1 byte
HEADER_FMT = "<BBHIBBH"
HEADER_SIZE = struct.calcsize(HEADER_FMT)  # 12 bytes
SAMPLE_FMT = "<hhhhhhB"
SAMPLE_SIZE = struct.calcsize(SAMPLE_FMT)  # 13 bytes
PKT_SIZE_BATCH = HEADER_SIZE + (5 * SAMPLE_SIZE) + 1  # 78 bytes

ACCEL_SCALE = 1000.0   # raw i16 → m/s²
GYRO_SCALE  = 100.0    # raw i16 → °/s

# ── Live-plot rolling window (seconds) ────────────────────────────────────
WINDOW_S   = 10
SAMPLE_HZ  = 100
MAX_PTS    = WINDOW_S * SAMPLE_HZ

def crc8_maxim(data: bytes) -> int:
    """CRC-8/1-Wire (Dallas/Maxim). Poly=0x31, Init=0x00, RefIn=RefOut=True."""
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8C if crc & 0x01 else crc >> 1
    return crc

# ── Global state & thread lock ───────────────────────────────────────────
data_lock = threading.Lock()
times_ms   = deque(maxlen=MAX_PTS)
magnitudes = deque(maxlen=MAX_PTS)
accel_x    = deque(maxlen=MAX_PTS)
accel_y    = deque(maxlen=MAX_PTS)
accel_z    = deque(maxlen=MAX_PTS)

total_rx   = 0
crc_errors = 0
t_start    = None
is_connected = False
status_text = "Scanning..."
is_app_running = True

def decode_and_enqueue(data: bytearray):
    """Decode either 78-byte batched or 20-byte single packet."""
    global total_rx, crc_errors, t_start

    if len(data) == 0:
        return

    # Check CRC-8
    received_crc = data[-1]
    computed_crc = crc8_maxim(data[:-1])
    if received_crc != computed_crc:
        crc_errors += 1
        return

    if t_start is None:
        t_start = time.time()

    if len(data) == PKT_SIZE_BATCH:
        # 78-byte Batched Packet
        ver, ptype, seq, base_ts, count, status, batt_mv = struct.unpack(
            HEADER_FMT, data[:HEADER_SIZE]
        )
        offset = HEADER_SIZE
        with data_lock:
            for _ in range(min(count, 5)):
                ax, ay, az, gx, gy, gz, dt_ms = struct.unpack(
                    SAMPLE_FMT, data[offset : offset + SAMPLE_SIZE]
                )
                offset += SAMPLE_SIZE

                t_ms = base_ts + dt_ms
                ax_ms2 = ax / ACCEL_SCALE
                ay_ms2 = ay / ACCEL_SCALE
                az_ms2 = az / ACCEL_SCALE
                mag = math.sqrt(ax_ms2**2 + ay_ms2**2 + az_ms2**2)

                times_ms.append(t_ms)
                magnitudes.append(mag)
                accel_x.append(ax_ms2)
                accel_y.append(ay_ms2)
                accel_z.append(az_ms2)
                total_rx += 1

            if magnitudes:
                last_mag = magnitudes[-1]
                last_ax = accel_x[-1]
                last_ay = accel_y[-1]
                last_az = accel_z[-1]
            else:
                last_mag = last_ax = last_ay = last_az = 0.0

        print(
            f"\r[RX] seq={seq:5d} | batt={batt_mv}mV | |a|={last_mag:6.2f} m/s² | "
            f"a=({last_ax:+5.2f}, {last_ay:+5.2f}, {last_az:+5.2f}) m/s²",
            end="",
            flush=True,
        )

    elif len(data) == PKT_SIZE_SINGLE:
        # 20-byte Single Packet
        ver, seq, ts, ax, ay, az, gx, gy, gz, _ = struct.unpack(PKT_FMT_SINGLE, data)
        ax_ms2 = ax / ACCEL_SCALE
        ay_ms2 = ay / ACCEL_SCALE
        az_ms2 = az / ACCEL_SCALE
        mag = math.sqrt(ax_ms2**2 + ay_ms2**2 + az_ms2**2)

        with data_lock:
            times_ms.append(ts)
            magnitudes.append(mag)
            accel_x.append(ax_ms2)
            accel_y.append(ay_ms2)
            accel_z.append(az_ms2)
            total_rx += 1

        print(
            f"\r[RX] seq={seq:5d} | |a|={mag:6.2f} m/s² | "
            f"a=({ax_ms2:+5.2f}, {ay_ms2:+5.2f}, {az_ms2:+5.2f}) m/s²",
            end="",
            flush=True,
        )

def on_notify(sender, data: bytearray):
    decode_and_enqueue(data)

# ── Matplotlib UI ─────────────────────────────────────────────────────────
fig, (ax_plot, ax_components) = plt.subplots(2, 1, figsize=(11, 7), sharex=True)
fig.patch.set_facecolor("#0f172a")

# Top plot: Accel Magnitude
ax_plot.set_facecolor("#1e293b")
ax_plot.set_title("IronLoop — Live Accelerometer Stream", color="#f8fafc", fontsize=13, fontweight="bold")
ax_plot.set_ylabel("|a| Magnitude (m/s²)", color="#94a3b8", fontsize=10)
ax_plot.tick_params(colors="#94a3b8")
ax_plot.axhline(9.80665, color="#22c55e", linewidth=1.0, linestyle="--", label="1g (9.81 m/s²)")
line_mag, = ax_plot.plot([], [], color="#38bdf8", linewidth=1.8, label="|a| total")
ax_plot.legend(loc="upper right", facecolor="#1e293b", labelcolor="#f8fafc", fontsize=9)
ax_plot.grid(True, color="#334155", linestyle=":", alpha=0.6)

# Bottom plot: 3-Axis Accel
ax_components.set_facecolor("#1e293b")
ax_components.set_xlabel("Relative Time (s)", color="#94a3b8", fontsize=10)
ax_components.set_ylabel("Accel Axes (m/s²)", color="#94a3b8", fontsize=10)
ax_components.tick_params(colors="#94a3b8")
line_x, = ax_components.plot([], [], color="#ef4444", linewidth=1.2, label="Ax")
line_y, = ax_components.plot([], [], color="#22c55e", linewidth=1.2, label="Ay")
line_z, = ax_components.plot([], [], color="#3b82f6", linewidth=1.2, label="Az")
ax_components.legend(loc="upper right", facecolor="#1e293b", labelcolor="#f8fafc", fontsize=9)
ax_components.grid(True, color="#334155", linestyle=":", alpha=0.6)

status_label = ax_plot.text(0.02, 0.90, "Status: Initializing...", transform=ax_plot.transAxes,
                            color="#f59e0b", fontsize=10, fontweight="bold")

def on_window_close(event):
    global is_app_running
    is_app_running = False

fig.canvas.mpl_connect("close_event", on_window_close)

def update_plot():
    try:
        status_label.set_text(f"Status: {status_text} | Samples: {total_rx} | Errors: {crc_errors}")

        with data_lock:
            if len(times_ms) < 2:
                return

            t0 = times_ms[0]
            raw_t = list(times_ms)
            mags = list(magnitudes)
            ax_x = list(accel_x)
            ax_y = list(accel_y)
            ax_z = list(accel_z)

        # Thread-safe length synchronization
        min_len = min(len(raw_t), len(mags), len(ax_x), len(ax_y), len(ax_z))
        if min_len < 2:
            return

        xs = [(t - t0) / 1000.0 for t in raw_t[:min_len]]
        mags = mags[:min_len]
        ax_x = ax_x[:min_len]
        ax_y = ax_y[:min_len]
        ax_z = ax_z[:min_len]

        line_mag.set_data(xs, mags)
        line_x.set_data(xs, ax_x)
        line_y.set_data(xs, ax_y)
        line_z.set_data(xs, ax_z)

        x_max = xs[-1]
        x_min = max(0.0, x_max - WINDOW_S)
        ax_plot.set_xlim(x_min, max(x_min + 1.0, x_max + 0.5))

        # Auto-scale Y
        all_vals = mags + ax_x + ax_y + ax_z
        if all_vals:
            ymin = min(-2.0, min(all_vals) - 2.0)
            ymax = max(15.0, max(all_vals) + 2.0)
            ax_plot.set_ylim(min(0.0, min(mags) - 1.0), max(15.0, max(mags) + 2.0))
            ax_components.set_ylim(ymin, ymax)
    except Exception:
        pass

# ── BLE Async Worker ──────────────────────────────────────────────────────
async def ble_worker():
    global is_connected, status_text, is_app_running
    while is_app_running:
        status_text = "Scanning for 'IronLoop'..."
        print(f"\n[INFO] {status_text}")
        try:
            def _match(d, adv):
                if d.name and "ironloop" in d.name.lower():
                    return True
                if adv.local_name and "ironloop" in adv.local_name.lower():
                    return True
                if adv.service_uuids and any(u.lower() == SERVICE_UUID.lower() for u in adv.service_uuids):
                    return True
                return False

            device = await BleakScanner.find_device_by_filter(_match, timeout=8.0)
            if not device:
                status_text = "Device 'IronLoop' not found. Retrying..."
                print(f"[WARN] {status_text}")
                await asyncio.sleep(1.5)
                continue

            status_text = f"Connecting to {device.address}..."
            print(f"[INFO] {status_text}")

            async with BleakClient(device) as client:
                is_connected = True
                dev_name = device.name or "IronLoop"
                status_text = f"Connected to {dev_name} (MTU: {client.mtu_size})"
                print(f"[INFO] {status_text}")

                # Send 0x01 START_SESSION command if command char is available
                try:
                    await client.write_gatt_char(CMD_CHAR_UUID, bytearray([0x01]), response=True)
                    print("[INFO] Sent START_SESSION command (0x01)")
                except Exception as e:
                    print(f"[DEBUG] CMD write: {e}")

                print(f"[INFO] Subscribing to IMU stream ({IMU_CHAR_UUID})...")
                await client.start_notify(IMU_CHAR_UUID, on_notify)
                status_text = "STREAMING ACTIVE"
                print("[INFO] Subscribed successfully! Streaming IMU data...\n")

                while client.is_connected and is_app_running:
                    await asyncio.sleep(0.3)

        except asyncio.CancelledError:
            break
        except Exception as e:
            status_text = f"Connection error: {e}"
            print(f"\n[ERR] BLE Error: {e}")
            await asyncio.sleep(2)
        finally:
            is_connected = False

# ── Main Entry ────────────────────────────────────────────────────────────
async def main():
    global is_app_running
    ble_task = asyncio.create_task(ble_worker())

    plt.tight_layout()
    plt.show(block=False)

    try:
        while is_app_running and plt.fignum_exists(fig.number):
            update_plot()
            try:
                fig.canvas.draw_idle()
                fig.canvas.flush_events()
            except Exception:
                break
            await asyncio.sleep(0.04)
    except KeyboardInterrupt:
        print("\n[INFO] Stopping on user interrupt...")
    finally:
        is_app_running = False
        ble_task.cancel()
        try:
            await ble_task
        except (asyncio.CancelledError, Exception):
            pass
        try:
            plt.close("all")
        except Exception:
            pass

    # Print summary
    elapsed = time.time() - t_start if t_start else 0
    rate = total_rx / elapsed if elapsed > 0 else 0
    print(f"\n{'-'*55}")
    print(f"  Samples received : {total_rx}")
    print(f"  CRC errors       : {crc_errors}")
    print(f"  Elapsed time     : {elapsed:.1f} s")
    print(f"  Effective rate   : {rate:.1f} Hz")
    print(f"{'-'*55}\n")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
