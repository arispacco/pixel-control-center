import 'connection_mode.dart';

/// Represents the hardware specifications, network addresses, and power
/// telemetry of an Android handset discovered by ADB.
class DeviceInfo {
  /// Unique device hardware identifier or network target endpoint.
  final String serial;

  /// Human-readable hardware model designation reported by Android build props.
  final String model;

  /// Physical transport or network protocol used for ADB communication.
  final ConnectionMode connectionMode;

  /// Current battery charge percentage ranging from 0 to 100, or `null` if not
  /// yet retrieved.
  final int? batteryLevel;

  /// Operating power state reported by the device battery service (such as
  /// 'Charging', 'Discharging', or 'Full').
  final String? batteryStatus;

  /// Wi-Fi IPv4 address assigned to the wireless network interface on the device.
  final String? ipAddress;

  /// Network TCP port configured for the ADB daemon (typically 5555).
  final int port;

  /// Whether the device is fully authorized and receptive to shell commands.
  final bool isOnline;

  /// Creates a validated [DeviceInfo] instance representing a discovered device.
  const DeviceInfo({
    required this.serial,
    required this.model,
    required this.connectionMode,
    this.batteryLevel,
    this.batteryStatus,
    this.ipAddress,
    this.port = 5555,
    this.isOnline = true,
  });

  /// Whether this handset is currently bridged through a physical USB cable.
  bool get isUsb => connectionMode == ConnectionMode.usb;

  /// Whether this handset is currently reachable through a local TCP/IP socket.
  bool get isWifi => connectionMode == ConnectionMode.wifi;

  /// Returns a copy of this [DeviceInfo] with the given fields replaced by the
  /// non-null parameter values.
  DeviceInfo copyWith({
    String? serial,
    String? model,
    ConnectionMode? connectionMode,
    int? batteryLevel,
    String? batteryStatus,
    String? ipAddress,
    int? port,
    bool? isOnline,
  }) {
    return DeviceInfo(
      serial: serial ?? this.serial,
      model: model ?? this.model,
      connectionMode: connectionMode ?? this.connectionMode,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      batteryStatus: batteryStatus ?? this.batteryStatus,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  @override
  String toString() {
    return 'DeviceInfo(serial: $serial, model: $model, mode: ${connectionMode.name}, battery: $batteryLevel%)';
  }
}
