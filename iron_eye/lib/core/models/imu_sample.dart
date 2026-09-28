/// One decoded IMU sample from the IronLoop firmware.
/// All values are already scaled to physical units.
class ImuSample {
  /// Device clock timestamp in ms (from base_timestamp + dt accumulation)
  final int timestampMs;

  /// Linear acceleration in body frame, m/s²
  final double ax, ay, az;

  /// Angular velocity in body frame, rad/s
  final double gx, gy, gz;

  /// The BLE packet sequence number this sample belongs to
  final int sequenceNumber;

  const ImuSample({
    required this.timestampMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.sequenceNumber,
  });

  @override
  String toString() =>
      'ImuSample(t=$timestampMs ms, a=[$ax,$ay,$az] m/s², g=[$gx,$gy,$gz] rad/s)';
}