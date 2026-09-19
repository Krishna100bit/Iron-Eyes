import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/providers/ble_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_container.dart';
import 'calibration_screen.dart';

class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleProvider);
    final notifier = ref.read(bleProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, ble, notifier),
            Expanded(
              child: ble.isConnected
                  ? _buildConnectedCard(ble, notifier)
                  : _buildScanView(ble, notifier),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(
      BuildContext context, BleState ble, BleNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VBT SENSOR',
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // Connection status chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: ble.isConnected
                  ? AppTheme.primary.withOpacity(0.12)
                  : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: ble.isConnected
                    ? AppTheme.primary
                    : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Transform.scale(
                    scale: ble.isConnected ? _pulse.value : 1.0,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ble.isConnected
                            ? AppTheme.primary
                            : Colors.white38,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  ble.isConnected ? 'Connected' : 'Disconnected',
                  style: GoogleFonts.outfit(
                    color: ble.isConnected ? AppTheme.primary : Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Scan View ──────────────────────────────────────────────────────────────
  Widget _buildScanView(BleState ble, BleNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Scan animation ring
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: ble.isScanning
                      ? AppTheme.primary.withOpacity(_pulse.value * 0.8)
                      : Colors.white.withOpacity(0.08),
                  width: 2,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surface,
                  border: Border.all(
                    color: ble.isScanning
                        ? AppTheme.primary.withOpacity(0.4)
                        : Colors.white.withOpacity(0.06),
                  ),
                ),
                child: Icon(
                  ble.isScanning
                      ? Icons.radar_rounded
                      : Icons.bluetooth_rounded,
                  color: ble.isScanning ? AppTheme.primary : Colors.white38,
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            ble.isScanning ? 'Scanning for devices…' : 'No device connected',
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Text(
            ble.isScanning
                ? 'Showing VBT sensors nearby'
                : 'Tap Scan to find your VBT sensor',
            style:
                GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 24),

          // Scan / Stop button
          GestureDetector(
            onTap: ble.isScanning ? notifier.stopScan : notifier.startScan,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
              decoration: BoxDecoration(
                gradient: ble.isScanning
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)]),
                color: ble.isScanning ? AppTheme.surface : null,
                borderRadius: BorderRadius.circular(14),
                border: ble.isScanning
                    ? Border.all(color: Colors.white24)
                    : null,
              ),
              child: Text(
                ble.isScanning ? 'Stop Scan' : 'Scan for Device',
                style: GoogleFonts.outfit(
                    color: ble.isScanning ? Colors.white54 : Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // Scan results list
          if (ble.scanResults.isNotEmpty) ...[
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Nearby Devices',
                  style: GoogleFonts.outfit(
                      color: Colors.white54, fontSize: 12, letterSpacing: 1)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: ble.scanResults.length,
                itemBuilder: (_, i) =>
                    _DeviceTile(result: ble.scanResults[i], notifier: notifier),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }

  // ── Connected View ─────────────────────────────────────────────────────────
  Widget _buildConnectedCard(BleState ble, BleNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 16),
          GlassContainer(
            blur: 20,
            opacity: 0.08,
            borderColor: AppTheme.primary.withOpacity(0.3),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.sensors_rounded,
                    color: AppTheme.primary, size: 48),
                const SizedBox(height: 12),
                Text(ble.deviceName ?? 'VBT Sensor',
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(ble.deviceId ?? '',
                    style: GoogleFonts.outfit(
                        color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _InfoChip(
                      label: 'Battery',
                      value: '${ble.batteryPercent}%',
                      icon: _batteryIcon(ble.batteryPercent),
                      color: ble.batteryPercent < 20
                          ? Colors.red
                          : AppTheme.primary,
                    ),
                    _InfoChip(
                      label: 'Packet Loss',
                      value:
                          '${ble.packetLossPercent.toStringAsFixed(1)}%',
                      icon: Icons.wifi_outlined,
                      color: ble.packetLossPercent > 5
                          ? Colors.orange
                          : AppTheme.primary,
                    ),
                    _InfoChip(
                      label: 'Calibrated',
                      value: ble.isDeviceCalibrated ? 'Yes' : 'No',
                      icon: ble.isDeviceCalibrated
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      color: ble.isDeviceCalibrated
                          ? AppTheme.primary
                          : Colors.orange,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Calibrate button
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CalibrationScreen()),
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text('🎯  Calibrate Sensor',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),

                // Disconnect button
                GestureDetector(
                  onTap: () async {
                    await notifier.disconnect();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Text('Disconnect',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _batteryIcon(int percent) {
    if (percent > 80) return Icons.battery_full_rounded;
    if (percent > 50) return Icons.battery_5_bar_rounded;
    if (percent > 20) return Icons.battery_3_bar_rounded;
    return Icons.battery_1_bar_rounded;
  }
}

// ── Device Tile ───────────────────────────────────────────────────────────────
class _DeviceTile extends StatelessWidget {
  final ScanResult result;
  final BleNotifier notifier;
  const _DeviceTile({required this.result, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isEmpty
        ? 'Unknown Device'
        : result.device.platformName;
    final rssi = result.rssi;

    return GestureDetector(
      onTap: () => notifier.connect(result),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            const Icon(Icons.sensors_rounded, color: AppTheme.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(result.device.remoteId.str,
                      style:
                          GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            // RSSI indicator
            Column(
              children: [
                Icon(Icons.signal_wifi_4_bar_rounded,
                    color: rssi > -60
                        ? AppTheme.primary
                        : rssi > -80
                            ? Colors.orange
                            : Colors.red,
                    size: 18),
                Text('$rssi dBm',
                    style:
                        GoogleFonts.outfit(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _InfoChip(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.outfit(
                color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        Text(label,
            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10)),
      ],
    );
  }
}
