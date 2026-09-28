"""
ble_protocol_decoder.py  —  Batched BLE Packet Decoder (Stage 6)
─────────────────────────────────────────────────────────────────
Decodes 78-byte batched BLE notification packets matching 02_ARCHITECTURE.md:

Header (12 bytes):
  - protocol_version (uint8, 0x02)
  - packet_type (uint8, 0x01)
  - sequence_number (uint16 LE)
  - base_timestamp_ms (uint32 LE)
  - sample_count (uint8, 5)
  - device_status (uint8 bitfield)
  - battery_mv (uint16 LE)

Payload (65 bytes):
  - 5 samples * { int16 ax, ay, az, int16 gx, gy, gz, uint8 dt_ms }

Footer (1 byte):
  - CRC-8/MAXIM over bytes 0..76
"""

from dataclasses import dataclass
from typing import List, Optional, Tuple
import struct

# Wire constants
PROTOCOL_VERSION = 2
PKT_TYPE_IMU_BATCH = 1
SAMPLES_PER_BATCH = 5

HEADER_FMT = "<BBHIBBH"  # ver (u8), type (u8), seq (u16), base_ts (u32), count (u8), status (u8), batt_mv (u16)
HEADER_SIZE = struct.calcsize(HEADER_FMT)  # 12 bytes

SAMPLE_FMT = "<hhhhhhB"  # ax, ay, az, gx, gy, gz, dt_ms
SAMPLE_SIZE = struct.calcsize(SAMPLE_FMT)  # 13 bytes

BATCHED_PKT_SIZE = HEADER_SIZE + (SAMPLES_PER_BATCH * SAMPLE_SIZE) + 1  # 78 bytes

ACCEL_SCALE = 1000.0  # raw int16 -> m/s²
GYRO_SCALE  = 100.0   # raw int16 -> °/s

# Status bitfield definitions
STATUS_FLAG_CALIBRATED     = (1 << 0)
STATUS_FLAG_LOW_BATT       = (1 << 1)
STATUS_FLAG_SESSION_ACTIVE = (1 << 2)
STATUS_FLAG_CALIBRATING    = (1 << 3)


def crc8_maxim(data: bytes) -> int:
    """CRC-8/1-Wire (Dallas/Maxim). Poly=0x31, Init=0x00, RefIn=RefOut=True."""
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8C if crc & 0x01 else crc >> 1
    return crc


@dataclass
class DecodedSample:
    """Individual physical-unit IMU sample."""
    ts_ms: float
    ax: float  # m/s²
    ay: float  # m/s²
    az: float  # m/s²
    gx: float  # °/s
    gy: float  # °/s
    gz: float  # °/s
    seq: int


@dataclass
class DecodedBatch:
    """Complete decoded batch of samples from a single BLE notification."""
    protocol_version: int
    packet_type: int
    sequence_number: int
    base_timestamp_ms: int
    sample_count: int
    device_status: int
    battery_mv: int
    is_calibrated: bool
    is_low_battery: bool
    is_session_active: bool
    is_calibrating: bool
    samples: List[DecodedSample]


class BatchedPacketDecoder:
    """Stateful decoder tracking packet loss and sequence continuity."""

    def __init__(self):
        self.last_seq: Optional[int] = None
        self.total_packets_rx: int = 0
        self.total_samples_rx: int = 0
        self.crc_errors: int = 0
        self.dropped_packets: int = 0

    def reset(self):
        self.last_seq = None
        self.total_packets_rx = 0
        self.total_samples_rx = 0
        self.crc_errors = 0
        self.dropped_packets = 0

    def decode(self, data: bytes) -> Optional[DecodedBatch]:
        """
        Decode raw 78-byte BLE packet into a DecodedBatch.
        Returns None on CRC or length mismatch.
        """
        if len(data) != BATCHED_PKT_SIZE:
            return None

        # Verify CRC8
        received_crc = data[-1]
        computed_crc = crc8_maxim(data[:-1])
        if received_crc != computed_crc:
            self.crc_errors += 1
            return None

        # Parse Header
        ver, ptype, seq, base_ts, count, status, batt_mv = struct.unpack(
            HEADER_FMT, data[:HEADER_SIZE]
        )

        # Track sequence gap / packet loss
        if self.last_seq is not None:
            expected = (self.last_seq + 1) % 65536
            if seq != expected:
                gap = (seq - expected) % 65536
                self.dropped_packets += gap

        self.last_seq = seq
        self.total_packets_rx += 1

        # Parse Samples
        samples: List[DecodedSample] = []
        offset = HEADER_SIZE
        for _ in range(min(count, SAMPLES_PER_BATCH)):
            ax_raw, ay_raw, az_raw, gx_raw, gy_raw, gz_raw, dt_ms = struct.unpack(
                SAMPLE_FMT, data[offset : offset + SAMPLE_SIZE]
            )
            offset += SAMPLE_SIZE

            sample_ts = base_ts + dt_ms
            samples.append(
                DecodedSample(
                    ts_ms=float(sample_ts),
                    ax=ax_raw / ACCEL_SCALE,
                    ay=ay_raw / ACCEL_SCALE,
                    az=az_raw / ACCEL_SCALE,
                    gx=gx_raw / GYRO_SCALE,
                    gy=gy_raw / GYRO_SCALE,
                    gz=gz_raw / GYRO_SCALE,
                    seq=seq,
                )
            )

        self.total_samples_rx += len(samples)

        return DecodedBatch(
            protocol_version=ver,
            packet_type=ptype,
            sequence_number=seq,
            base_timestamp_ms=base_ts,
            sample_count=len(samples),
            device_status=status,
            battery_mv=batt_mv,
            is_calibrated=bool(status & STATUS_FLAG_CALIBRATED),
            is_low_battery=bool(status & STATUS_FLAG_LOW_BATT),
            is_session_active=bool(status & STATUS_FLAG_SESSION_ACTIVE),
            is_calibrating=bool(status & STATUS_FLAG_CALIBRATING),
            samples=samples,
        )
