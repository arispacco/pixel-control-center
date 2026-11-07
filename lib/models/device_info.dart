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

  /// Hardware manufacturer or brand reported by Android (`google`, `samsung`,
  /// `xiaomi`, `tecno`, `infinix`, `oppo`, etc.).
  final String? brand;

  /// Android API SDK level (`26` for Android 8.0 through `36+`), if queried.
  final int? sdkInt;

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
    this.brand,
    this.sdkInt,
  });

  /// Whether this handset is currently bridged through a physical USB cable.
  bool get isUsb => connectionMode == ConnectionMode.usb;

  /// Whether this handset is currently reachable through a local TCP/IP socket.
  bool get isWifi => connectionMode == ConnectionMode.wifi;

  /// Whether this handset is a Google Pixel device requiring Tensor-specific
  /// display encoder workarounds when turning the screen off.
  bool get isGooglePixel {
    final normalizedBrand = (brand ?? '').trim().toLowerCase();
    final normalizedModel = model.trim().toLowerCase();
    return normalizedBrand == 'google' || normalizedModel.contains('pixel');
  }

  /// Human-friendly label combining manufacturer brand and model without duplication.
  String get displayName {
    final rawBrand = (brand ?? '').trim();
    if (rawBrand.isEmpty) {
      return model;
    }
    if (model.toLowerCase().contains(rawBrand.toLowerCase())) {
      return model;
    }
    final capitalized =
        '${rawBrand[0].toUpperCase()}${rawBrand.substring(1).toLowerCase()}';
    return '$capitalized $model';
  }

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
    String? brand,
    int? sdkInt,
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
      brand: brand ?? this.brand,
      sdkInt: sdkInt ?? this.sdkInt,
    );
  }

  @override
  String toString() {
    return 'DeviceInfo(serial: $serial, model: $model, mode: ${connectionMode.name}, battery: $batteryLevel%)';
  }
}
