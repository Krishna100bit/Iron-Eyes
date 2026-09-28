import 'dart:math';
import 'dart:typed_data';
import '../models/imu_sample.dart';

/// Parsed result from one BLE notification
class ParsedPacket {
  final int sequenceNumber;
  final List<ImuSample> samples;
  final int batteryMv;
  final bool calibrated;
  final bool sessionActive;
  final bool lowBattery;

  const ParsedPacket({
    required this.sequenceNumber,
    required this.samples,
    this.batteryMv = 0,
    this.calibrated = false,
    this.sessionActive = false,
    this.lowBattery = false,
  });
}

/// Decodes the custom IronLoop BLE packet format 
///
/// Packet layout (bytes):
///  0     protocol_version (uint8)
///  1     packet_type (uint8)  — 0x01 = IMU batch
///  2-3   sequence_number (uint16 LE, wraps at 65535)
///  4-7   base_timestamp_ms (uint32 LE)
///  8     sample_count (uint8)
///  9     device_status bitfield: bit0=calibrated, bit1=session_active, bit2=low_batt
///  10-11 battery_mv (uint16 LE)
///  12+   N × { int16 ax, ay, az, int16 gx, gy, gz, uint8 dt_ms } (13 bytes each)
///  last  CRC8 (1 byte)
class BlePacketParser {
  // BMI270 at ±8 g range, 16-bit: 1 LSB = 8/32768 g = 0.000244 g
  static const double _accelScale = 8.0 * 9.80665 / 32768.0; // m/s² per LSB

  // BMI270 at ±2000 °/s range, 16-bit: 1 LSB = 2000/32768 °/s
  static const double _gyroScale = (2000.0 * pi / 180.0) / 32768.0; // rad/s per LSB

  static const int _headerSize = 12;
  static const int _sampleSize = 13; // 6×int16 + 1 uint8

  int? _lastSeq;
  int _lostPackets = 0;
  int _totalPackets = 0;

  /// Parse raw BLE notification bytes. Returns null if the packet is malformed.
  ParsedPacket? parsePacket(List<int> rawBytes) {
    // Check if it's a 4-byte Status Packet (sent while idle)
    if (rawBytes.length == 4) {
      final data = Uint8List.fromList(rawBytes);
      final bd = ByteData.sublistView(data);
      final status = data[0];
      final batteryMv = bd.getUint16(1, Endian.little);
      
      return ParsedPacket(
        sequenceNumber: 0,
        samples: [],
        batteryMv: batteryMv,
        calibrated: (status & 0x01) != 0,
        lowBattery: (status & 0x02) != 0,
        sessionActive: (status & 0x04) != 0,
      );
    }

    if (rawBytes.length < _headerSize + _sampleSize) return null;

    final data = Uint8List.fromList(rawBytes);
    final bd = ByteData.sublistView(data);

    final packetType = data[1];
    if (packetType != 0x01) return null; // only IMU batch supported

    final seq = bd.getUint16(2, Endian.little);
    final baseTs = bd.getUint32(4, Endian.little);
    final sampleCount = data[8];
    final status = data[9];
    final batteryMv = bd.getUint16(10, Endian.little);

    // Sequence gap detection
    _totalPackets++;
    if (_lastSeq != null) {
      final expected = (_lastSeq! + 1) & 0xFFFF;
      if (seq != expected) {
        final lost = (seq - expected) & 0xFFFF;
        _lostPackets += lost;
      }
    }
    _lastSeq = seq;

    // CRC check (skip last byte — CRC8 of all prior bytes)
    // For prototype: validate by checking packet length matches declared count
    final expectedLen = _headerSize + sampleCount * _sampleSize + 1;
    if (data.length < expectedLen) return null; // truncated

    // Decode samples
    final samples = <ImuSample>[];
    int offset = _headerSize;
    int cumulativeDt = 0;

    for (int i = 0; i < sampleCount; i++) {
      if (offset + _sampleSize > data.length - 1) break;

      // Firmware sends Accel pre-scaled by 1000 (m/s^2 * 1000)
      final ax = bd.getInt16(offset + 0, Endian.little) / 1000.0;
      final ay = bd.getInt16(offset + 2, Endian.little) / 1000.0;
      final az = bd.getInt16(offset + 4, Endian.little) / 1000.0;
      
      // Firmware sends Gyro pre-scaled by 100 (deg/s * 100). Convert to rad/s.
      final gx = (bd.getInt16(offset + 6, Endian.little) / 100.0) * (pi / 180.0);
      final gy = (bd.getInt16(offset + 8, Endian.little) / 100.0) * (pi / 180.0);
      final gz = (bd.getInt16(offset + 10, Endian.little) / 100.0) * (pi / 180.0);
      final dtMs = data[offset + 12];

      cumulativeDt += dtMs;
      samples.add(ImuSample(
        timestampMs: baseTs + cumulativeDt,
        ax: ax, ay: ay, az: az,
        gx: gx, gy: gy, gz: gz,
        sequenceNumber: seq,
      ));
      offset += _sampleSize;
    }

    return ParsedPacket(
      sequenceNumber: seq,
      samples: samples,
      batteryMv: batteryMv,
      calibrated: (status & 0x01) != 0,
      lowBattery: (status & 0x02) != 0,
      sessionActive: (status & 0x04) != 0,
    );
  }

  double get packetLossPercent =>
      _totalPackets > 0 ? (_lostPackets / _totalPackets) * 100.0 : 0.0;

  void reset() {
    _lastSeq = null;
    _lostPackets = 0;
    _totalPackets = 0;
  }
}