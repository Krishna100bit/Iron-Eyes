"""
test_batched_pipeline.py  —  Unit & Integration Tests for Phase-3 Batched Protocol
───────────────────────────────────────────────────────────────────────────────────
Tests:
  1. 78-byte Batched Packet Encoding & Decoding (Header, 5x Samples, CRC8)
  2. CRC-8 Validation & Corrupted Packet Rejection
  3. Packet Loss & Sequence Number Gap Tracking
  4. End-to-End VBT Pipeline Processing with Batched Data
"""

import struct
import sys
from pathlib import Path
import numpy as np

SRC_DIR = Path(__file__).resolve().parent.parent / "src"
sys.path.insert(0, str(SRC_DIR))

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

from ble_protocol_decoder import (
    BatchedPacketDecoder,
    crc8_maxim,
    BATCHED_PKT_SIZE,
    HEADER_SIZE,
    SAMPLE_SIZE,
    SAMPLES_PER_BATCH,
)
from pipeline import process_session
from config import DEFAULT_CONFIG


def encode_test_batch(
    seq: int,
    base_ts: int,
    samples_data: list,
    status: int = 0x05,
    batt_mv: int = 4150,
) -> bytes:
    """Helper to simulate firmware batched packet encoding in Python."""
    buf = bytearray(BATCHED_PKT_SIZE)
    # Header (12 bytes)
    struct.pack_into("<BBHIBBH", buf, 0, 2, 1, seq, base_ts, SAMPLES_PER_BATCH, status, batt_mv)

    offset = HEADER_SIZE
    for s in samples_data:
        ax_i16 = int(round(s["ax"] * 1000.0))
        ay_i16 = int(round(s["ay"] * 1000.0))
        az_i16 = int(round(s["az"] * 1000.0))
        gx_i16 = int(round(s["gx"] * 100.0))
        gy_i16 = int(round(s["gy"] * 100.0))
        gz_i16 = int(round(s["gz"] * 100.0))
        dt_ms = int(s["dt_ms"])
        struct.pack_into("<hhhhhhB", buf, offset, ax_i16, ay_i16, az_i16, gx_i16, gy_i16, gz_i16, dt_ms)
        offset += SAMPLE_SIZE

    # CRC8 over bytes 0..76
    crc = crc8_maxim(buf[:-1])
    buf[-1] = crc
    return bytes(buf)


def test_batched_packet_decode():
    """Verify 78-byte packet unpacking and physical scaling."""
    decoder = BatchedPacketDecoder()

    test_samples = [
        {"ax": 0.0, "ay": 0.0, "az": 9.807, "gx": 0.0, "gy": 0.0, "gz": 0.0, "dt_ms": 0},
        {"ax": 0.1, "ay": -0.2, "az": 9.850, "gx": 1.5, "gy": -2.0, "gz": 0.5, "dt_ms": 10},
        {"ax": -0.1, "ay": 0.3, "az": 9.780, "gx": -1.0, "gy": 1.2, "gz": -0.8, "dt_ms": 20},
        {"ax": 0.05, "ay": 0.0, "az": 9.810, "gx": 0.2, "gy": 0.1, "gz": 0.0, "dt_ms": 30},
        {"ax": 0.0, "ay": -0.05, "az": 9.800, "gx": 0.0, "gy": -0.3, "gz": 0.1, "dt_ms": 40},
    ]

    raw_pkt = encode_test_batch(seq=42, base_ts=10000, samples_data=test_samples)
    assert len(raw_pkt) == 78, f"Packet size must be 78 bytes, got {len(raw_pkt)}"

    batch = decoder.decode(raw_pkt)
    assert batch is not None, "Failed to decode valid batch packet"
    assert batch.sequence_number == 42
    assert batch.base_timestamp_ms == 10000
    assert batch.sample_count == 5
    assert batch.battery_mv == 4150
    assert batch.is_calibrated is True
    assert batch.is_session_active is True

    assert len(batch.samples) == 5
    s0 = batch.samples[0]
    assert s0.ts_ms == 10000.0
    assert np.isclose(s0.az, 9.807, atol=1e-3)

    s1 = batch.samples[1]
    assert s1.ts_ms == 10010.0
    assert np.isclose(s1.ax, 0.1, atol=1e-3)
    assert np.isclose(s1.gx, 1.5, atol=1e-2)

    print("  [OK] Batched packet decode test passed (78 bytes, 5 samples).")


def test_crc_error_rejection():
    """Verify that bit flips trigger CRC rejection."""
    decoder = BatchedPacketDecoder()
    test_samples = [{"ax": 0, "ay": 0, "az": 9.81, "gx": 0, "gy": 0, "gz": 0, "dt_ms": i * 10} for i in range(5)]

    raw_pkt = bytearray(encode_test_batch(seq=1, base_ts=0, samples_data=test_samples))
    raw_pkt[15] ^= 0xFF  # Corrupt payload byte

    result = decoder.decode(bytes(raw_pkt))
    assert result is None, "Corrupted packet was incorrectly accepted"
    assert decoder.crc_errors == 1

    print("  [OK] CRC error rejection test passed.")


def test_packet_loss_tracking():
    """Verify detection of sequence gaps."""
    decoder = BatchedPacketDecoder()
    test_samples = [{"ax": 0, "ay": 0, "az": 9.81, "gx": 0, "gy": 0, "gz": 0, "dt_ms": i * 10} for i in range(5)]

    p1 = encode_test_batch(seq=10, base_ts=0, samples_data=test_samples)
    p2 = encode_test_batch(seq=13, base_ts=150, samples_data=test_samples)  # Gap of 2 packets (seq 11, 12 missing)

    decoder.decode(p1)
    decoder.decode(p2)
    assert decoder.dropped_packets == 2

    print("  [OK] Packet loss tracking test passed.")


def test_batched_end_to_end_vbt():
    """Verify end-to-end VBT pipeline with decoded batched packets."""
    from test_vbt_pipeline import generate_synthetic_squat_set

    sim = generate_synthetic_squat_set(n_reps=3)
    decoder = BatchedPacketDecoder()

    # Pack synthetic data into 5-sample batches and decode
    all_decoded_samples = []
    n = len(sim["ts_ms"])

    seq = 0
    for i in range(0, n - 5, 5):
        batch_samples = []
        base_ts = int(sim["ts_ms"][i])
        for j in range(5):
            idx = i + j
            batch_samples.append({
                "ax": sim["ax"][idx],
                "ay": sim["ay"][idx],
                "az": sim["az"][idx],
                "gx": sim["gx"][idx],
                "gy": sim["gy"][idx],
                "gz": sim["gz"][idx],
                "dt_ms": int(sim["ts_ms"][idx] - base_ts),
            })
        raw_pkt = encode_test_batch(seq=seq, base_ts=base_ts, samples_data=batch_samples)
        batch = decoder.decode(raw_pkt)
        all_decoded_samples.extend(batch.samples)
        seq += 1

    # Feed decoded samples into VBT pipeline
    sample_dict = {
        "ts_ms": [s.ts_ms for s in all_decoded_samples],
        "ax": [s.ax for s in all_decoded_samples],
        "ay": [s.ay for s in all_decoded_samples],
        "az": [s.az for s in all_decoded_samples],
        "gx": [s.gx for s in all_decoded_samples],
        "gy": [s.gy for s in all_decoded_samples],
        "gz": [s.gz for s in all_decoded_samples],
        "seq": [s.seq for s in all_decoded_samples],
    }

    res = process_session(sample_dict, config=DEFAULT_CONFIG)
    assert len(res.reps) == 3, f"Expected 3 reps, got {len(res.reps)}"
    for r in res.reps:
        assert 0.35 <= r.mean_concentric_velocity <= 1.20
        assert r.data_quality == "CLEAN"

    print(f"  [OK] End-to-end batched VBT pipeline test passed (3 reps detected: MCV={res.reps[0].mean_concentric_velocity:.3f} m/s).")


def run_all_tests():
    print("\n========================================================")
    print("  RUNNING PHASE-3 BATCHED PROTOCOL TEST SUITE")
    print("========================================================")
    test_batched_packet_decode()
    test_crc_error_rejection()
    test_packet_loss_tracking()
    test_batched_end_to_end_vbt()
    print("========================================================")
    print("  ALL PHASE-3 TESTS PASSED (4/4)")
    print("========================================================\n")


if __name__ == "__main__":
    run_all_tests()
