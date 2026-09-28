"""
packet_parser.py  —  IronLoop BLE Packet Decoder & Sequence Tracker
───────────────────────────────────────────────────────────────────
Decodes:
  1. Stream Packets (78 bytes, protocol_version=1):
     Header (12B) + 5 Samples (65B) + CRC-8/MAXIM (1B)
  2. Status Packets (4 bytes):
     device_status (u8), battery_mv (u16 LE), last_command_ack (u8)

Tracks packet continuity, packet loss percentage, and formats engineering units.
"""

import struct
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

# ── Wire Constants ─────────────────────────────────────────────────────────
PROTOCOL_VERSION_EXPECTED = 1
PKT_TYPE_IMU_BATCH        = 1
SAMPLES_PER_BATCH         = 5

HEADER_FMT  = "<BBHIBBH"   # ver(u8), type(u8), seq(u16), base_ts(u32), count(u8), status(u8), batt_mv(u16)
HEADER_SIZE = struct.calcsize(HEADER_FMT)  # 12 bytes

SAMPLE_FMT  = "<hhhhhhB"   # ax, ay, az, gx, gy, gz (i16), dt_ms(u8)
SAMPLE_SIZE = struct.calcsize(SAMPLE_FMT)  # 13 bytes

STREAM_PKT_SIZE = HEADER_SIZE + (SAMPLES_PER_BATCH * SAMPLE_SIZE) + 1  # 78 bytes

STATUS_FMT  = "<BHB"       # status(u8), batt_mv(u16), ack(u8)
STATUS_SIZE = struct.calcsize(STATUS_FMT)  # 4 bytes

ACCEL_SCALE = 1000.0       # raw i16 -> m/s²
GYRO_SCALE  = 100.0        # raw i16 -> °/s

# ── Status Bit Flags ───────────────────────────────────────────────────────
STATUS_FLAG_CALIBRATED     = (1 << 0)  # Bit 0
STATUS_FLAG_LOW_BATT       = (1 << 1)  # Bit 1
STATUS_FLAG_SESSION_ACTIVE = (1 << 2)  # Bit 2
STATUS_FLAG_SENSOR_FAULT   = (1 << 3)  # Bit 3


def crc8_maxim(data: bytes) -> int:
    """CRC-8/1-Wire (Dallas/Maxim). Poly=0x31, Init=0x00, RefIn=RefOut=True."""
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8C if crc & 0x01 else crc >> 1
    return crc


@dataclass
class ParsedSample:
    """Individual physical-unit IMU sample."""
    timestamp_ms: float
    ax_ms2: float
    ay_ms2: float
    az_ms2: float
    gx_dps: float
    gy_dps: float
    gz_dps: float
    sequence_number: int


@dataclass
class ParsedStreamBatch:
    """Decoded 5-sample batch with packet header metadata."""
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
    has_sensor_fault: bool = False
    samples: List[ParsedSample] = field(default_factory=list)


@dataclass
class ParsedStatusPacket:
    """Decoded 4-byte status notification / response."""
    device_status: int
    battery_mv: int
    last_command_ack: int
    is_calibrated: bool
    is_low_battery: bool
    is_session_active: bool
    has_sensor_fault: bool = False


class PacketParser:
    """Stateful parser managing sequence continuity and packet loss metrics."""

    def __init__(self):
        self.last_sequence: Optional[int] = None
        self.total_packets_received: int = 0
        self.total_samples_received: int = 0
        self.total_packets_dropped: int = 0
        self.crc_errors: int = 0

    def reset(self):
        self.last_sequence = None
        self.total_packets_received = 0
        self.total_samples_received = 0
        self.total_packets_dropped = 0
        self.crc_errors = 0

    @property
    def packet_loss_percentage(self) -> float:
        total_expected = self.total_packets_received + self.total_packets_dropped
        if total_expected == 0:
            return 0.0
        return (self.total_packets_dropped / total_expected) * 100.0

    def parse_stream_packet(self, data: bytes) -> Optional[ParsedStreamBatch]:
        """
        Validates CRC, checks sequence continuity, and unpacks a 78-byte Stream packet.
        Returns None if CRC fails or length is incorrect.
        """
        if len(data) != STREAM_PKT_SIZE:
            return None

        # Verify CRC-8 over bytes 0..76
        received_crc = data[-1]
        computed_crc = crc8_maxim(data[:-1])
        if received_crc != computed_crc:
            self.crc_errors += 1
            return None

        # Unpack Header
        ver, ptype, seq, base_ts, count, status, batt_mv = struct.unpack(
            HEADER_FMT, data[:HEADER_SIZE]
        )

        # Track sequence continuity (16-bit wraparound)
        if self.last_sequence is not None:
            expected = (self.last_sequence + 1) % 65536
            if seq != expected:
                gap = (seq - expected) % 65536
                self.total_packets_dropped += gap

        self.last_sequence = seq
        self.total_packets_received += 1

        is_cal = bool(status & STATUS_FLAG_CALIBRATED)
        is_low = bool(status & STATUS_FLAG_LOW_BATT)
        is_active = bool(status & STATUS_FLAG_SESSION_ACTIVE)
        has_fault = bool(status & STATUS_FLAG_SENSOR_FAULT)

        # Unpack Samples
        samples: List[ParsedSample] = []
        offset = HEADER_SIZE
        for _ in range(min(count, SAMPLES_PER_BATCH)):
            ax, ay, az, gx, gy, gz, dt_ms = struct.unpack(
                SAMPLE_FMT, data[offset : offset + SAMPLE_SIZE]
            )
            offset += SAMPLE_SIZE

            sample_ts = base_ts + dt_ms
            samples.append(
                ParsedSample(
                    timestamp_ms=float(sample_ts),
                    ax_ms2=ax / ACCEL_SCALE,
                    ay_ms2=ay / ACCEL_SCALE,
                    az_ms2=az / ACCEL_SCALE,
                    gx_dps=gx / GYRO_SCALE,
                    gy_dps=gy / GYRO_SCALE,
                    gz_dps=gz / GYRO_SCALE,
                    sequence_number=seq,
                )
            )
            self.total_samples_received += 1

        return ParsedStreamBatch(
            protocol_version=ver,
            packet_type=ptype,
            sequence_number=seq,
            base_timestamp_ms=base_ts,
            sample_count=count,
            device_status=status,
            battery_mv=batt_mv,
            is_calibrated=is_cal,
            is_low_battery=is_low,
            is_session_active=is_active,
            has_sensor_fault=has_fault,
            samples=samples,
        )

    def parse_status_packet(self, data: bytes) -> Optional[ParsedStatusPacket]:
        """Unpack a 4-byte Status Characteristic packet."""
        if len(data) != STATUS_SIZE:
            return None

        status, batt_mv, ack = struct.unpack(STATUS_FMT, data)
        return ParsedStatusPacket(
            device_status=status,
            battery_mv=batt_mv,
            last_command_ack=ack,
            is_calibrated=bool(status & STATUS_FLAG_CALIBRATED),
            is_low_battery=bool(status & STATUS_FLAG_LOW_BATT),
            is_session_active=bool(status & STATUS_FLAG_SESSION_ACTIVE),
            has_sensor_fault=bool(status & STATUS_FLAG_SENSOR_FAULT),
        )
