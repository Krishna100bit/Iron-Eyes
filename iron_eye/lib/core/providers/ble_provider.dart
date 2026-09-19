import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/imu_sample.dart';
import '../ble/ble_packet_parser.dart';

// ── IronLoop GATT UUIDs ───────────────────────────────────────────────────────
// These are placeholder UUIDs matching 02_ARCHITECTURE.md — update when firmware
// team finalises the 128-bit base.
const _serviceUuid = '0000a000-0000-1000-8000-00805f9b34fb';
const _streamCharUuid = '0000a001-0000-1000-8000-00805f9b34fb';
const _commandCharUuid = '0000a002-0000-1000-8000-00805f9b34fb';


// ── BLE Commands ──────────────────────────────────────────────────────────────
class BleCmd {
  static const startSession = [0x01];
  static const stopSession = [0x02];
  static const calibrate = [0x03];
  static const ping = [0x05];
}

// ── Connection State ──────────────────────────────────────────────────────────
enum BleConnectionState { disconnected, scanning, connecting, connected, streaming }

class BleState {
  final BleConnectionState connection;
  final String? deviceName;
  final String? deviceId;
  final int batteryMv;
  final bool isDeviceCalibrated;
  final bool lowBattery;
  final double packetLossPercent;
  final List<ScanResult> scanResults;

  const BleState({
    this.connection = BleConnectionState.disconnected,
    this.deviceName,
    this.deviceId,
    this.batteryMv = 0,
    this.isDeviceCalibrated = false,
    this.lowBattery = false,
    this.packetLossPercent = 0,
    this.scanResults = const [],
  });

  int get batteryPercent {
    if (batteryMv <= 0) return 0;
    // Typical LiPo: 4200 mv = 100%, 3300 mv = 0%
    return ((batteryMv - 3300) / (4200 - 3300) * 100).clamp(0, 100).round();
  }

  bool get isConnected =>
      connection == BleConnectionState.connected ||
      connection == BleConnectionState.streaming;

  bool get isScanning => connection == BleConnectionState.scanning;

  BleState copyWith({
    BleConnectionState? connection,
    String? deviceName,
    String? deviceId,
    int? batteryMv,
    bool? isDeviceCalibrated,
    bool? lowBattery,
    double? packetLossPercent,
    List<ScanResult>? scanResults,
  }) =>
      BleState(
        connection: connection ?? this.connection,
        deviceName: deviceName ?? this.deviceName,
        deviceId: deviceId ?? this.deviceId,
        batteryMv: batteryMv ?? this.batteryMv,
        isDeviceCalibrated: isDeviceCalibrated ?? this.isDeviceCalibrated,
        lowBattery: lowBattery ?? this.lowBattery,
        packetLossPercent: packetLossPercent ?? this.packetLossPercent,
        scanResults: scanResults ?? this.scanResults,
      );
}

// ── BLE Notifier ──────────────────────────────────────────────────────────────
class BleNotifier extends StateNotifier<BleState> {
  BleNotifier() : super(const BleState()) {
    _listenToAdapterState();
  }

  BluetoothDevice? _device;
  BluetoothCharacteristic? _commandChar;

  final _parser = BlePacketParser();

  // Stream of decoded IMU samples — ImuPipeline subscribes to this
  final _sampleController = StreamController<ImuSample>.broadcast();
  Stream<ImuSample> get sampleStream => _sampleController.stream;

  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  void _listenToAdapterState() {
    _adapterSub = FlutterBluePlus.adapterState.listen((adapterState) {
      if (adapterState != BluetoothAdapterState.on) {
        if (state.isConnected) _cleanupConnection();
      }
    });
  }

  // ── Scanning ──────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    if (state.isScanning) return;

    // Request BLE permissions
    final status = await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    if (!status.isGranted) return;

    state = state.copyWith(
      connection: BleConnectionState.scanning,
      scanResults: [],
    );

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      // Filter to devices advertising our service, or named IronPuck
      final filtered = results
          .where((r) =>
              r.device.platformName.toLowerCase().contains('iron') ||
              r.advertisementData.serviceUuids
                  .any((u) => u.toString().toLowerCase() == _serviceUuid))
          .toList();
      state = state.copyWith(scanResults: filtered);
    });

    await FlutterBluePlus.startScan(
      withServices: [], // scan all — filter above
      timeout: const Duration(seconds: 10),
    );

    await Future.delayed(const Duration(seconds: 10));
    if (state.isScanning) {
      await FlutterBluePlus.stopScan();
      state = state.copyWith(connection: BleConnectionState.disconnected);
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    if (state.isScanning) {
      state = state.copyWith(connection: BleConnectionState.disconnected);
    }
  }

  // ── Connection ────────────────────────────────────────────────────────────

  Future<void> connect(ScanResult result) async {
    await stopScan();
    state = state.copyWith(
      connection: BleConnectionState.connecting,
      deviceName: result.device.platformName,
      deviceId: result.device.remoteId.str,
      scanResults: [],
    );

    _device = result.device;

    try {
      await _device!.connect(autoConnect: false,
          timeout: const Duration(seconds: 15));

      _connectionSub = _device!.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _cleanupConnection();
          _autoReconnect();
        }
      });

      await _discoverAndSubscribe();
    } catch (_) {
      _cleanupConnection();
    }
  }

  Future<void> _discoverAndSubscribe() async {
    if (_device == null) return;

    final services = await _device!.discoverServices();
    BluetoothService? imuService;
    for (final svc in services) {
      if (svc.serviceUuid.toString().toLowerCase() == _serviceUuid) {
        imuService = svc;
        break;
      }
    }

    // Fallback: use first service (for testing with generic BLE device)
    imuService ??= services.isNotEmpty ? services.first : null;
    if (imuService == null) {
      _cleanupConnection();
      return;
    }

    for (final char in imuService.characteristics) {
      final uuid = char.characteristicUuid.toString().toLowerCase();
      if (uuid == _streamCharUuid || char.properties.notify) {
        await char.setNotifyValue(true);
        char.lastValueStream.listen(_onStreamData);
      }
      if (uuid == _commandCharUuid || char.properties.write) {
        _commandChar = char;
      }
    }

    state = state.copyWith(connection: BleConnectionState.streaming);
  }

  void _onStreamData(List<int> bytes) {
    if (bytes.isEmpty) return;
    final packet = _parser.parsePacket(bytes);
    if (packet == null) return;

    // Update state with device metadata from packet
    state = state.copyWith(
      batteryMv: packet.batteryMv > 0 ? packet.batteryMv : state.batteryMv,
      isDeviceCalibrated: packet.calibrated,
      lowBattery: packet.lowBattery,
      packetLossPercent: _parser.packetLossPercent,
    );

    // Emit each decoded sample
    for (final sample in packet.samples) {
      _sampleController.add(sample);
    }
  }

  // ── Commands ──────────────────────────────────────────────────────────────

  Future<void> sendCommand(List<int> cmd) async {
    if (_commandChar == null) return;
    try {
      await _commandChar!.write(cmd, withoutResponse: false);
    } catch (_) {}
  }

  Future<void> sendCalibrate() => sendCommand(BleCmd.calibrate);
  Future<void> sendStartSession() => sendCommand(BleCmd.startSession);
  Future<void> sendStopSession() => sendCommand(BleCmd.stopSession);

  // ── Auto-Reconnect ────────────────────────────────────────────────────────

  int _reconnectAttempts = 0;

  Future<void> _autoReconnect() async {
    if (_reconnectAttempts >= 3 || _device == null) {
      _cleanupConnection();
      return;
    }
    _reconnectAttempts++;
    await Future.delayed(Duration(seconds: 2 * _reconnectAttempts));
    try {
      await _device!.connect(autoConnect: false,
          timeout: const Duration(seconds: 10));
      await _discoverAndSubscribe();
      _reconnectAttempts = 0;
    } catch (_) {
      await _autoReconnect();
    }
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    _reconnectAttempts = 99; // prevent auto-reconnect
    await _device?.disconnect();
    _cleanupConnection();
  }

  void _cleanupConnection() {
    _connectionSub?.cancel();
    _commandChar = null;
    _device = null;
    _reconnectAttempts = 0;
    _parser.reset();
    state = state.copyWith(
      connection: BleConnectionState.disconnected,
      deviceName: null,
      deviceId: null,
      batteryMv: 0,
      isDeviceCalibrated: false,
    );
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    _scanSub?.cancel();
    _connectionSub?.cancel();
    _sampleController.close();
    super.dispose();
  }
}

final bleProvider =
    StateNotifierProvider<BleNotifier, BleState>((ref) => BleNotifier());
