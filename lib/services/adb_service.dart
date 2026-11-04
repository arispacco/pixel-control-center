import 'dart:convert';
import 'dart:io';

import '../models/connection_mode.dart';
import '../models/device_info.dart';

/// Provides asynchronous process operations and command utilities for the
/// Android Debug Bridge (ADB) daemon.
///
/// Encapsulates device discovery, power telemetry, and Google Pixel hardware
/// quirks such as virtual keyboard passthrough and OLED brightness adjustments.
class AdbService {
  /// Executable name or absolute file path to the `adb` binary.
  final String adbPath;

  /// Creates an [AdbService] instance, locating the binary from standard
  /// directories or PATH.
  AdbService({String? customAdbPath})
      : adbPath = customAdbPath ?? _findAdbExecutable();

  /// Locates the `adb` executable on the host file system.
  static String _findAdbExecutable() {
    if (Platform.isWindows) {
      // Check Winget default installation path for scrcpy bundle.
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final wingetPath =
          '$localAppData\\Microsoft\\WinGet\\Packages\\Genymobile.scrcpy_Microsoft.Winget.Source_8wekyb3d8bbwe\\scrcpy-win64-v5.0.1\\adb.exe';
      if (File(wingetPath).existsSync()) {
        return wingetPath;
      }
      return 'adb.exe';
    }
    return 'adb';
  }

  /// Executes an ADB command with the given argument list.
  ///
  /// Returns the completed [ProcessResult] once the command finishes.
  Future<ProcessResult> execute(List<String> arguments) async {
    try {
      return await Process.run(adbPath, arguments);
    } catch (e) {
      return ProcessResult(0, -1, '', 'Failed to spawn adb: $e');
    }
  }

  /// Retrieves the list of currently recognized Android devices attached via
  /// USB or local Wi-Fi TCP/IP sockets.
  Future<List<DeviceInfo>> getConnectedDevices() async {
    final result = await execute(['devices', '-l']);
    if (result.exitCode != 0) {
      return [];
    }

    final output = result.stdout as String;
    return parseDevicesOutput(output);
  }

  /// Parses the raw text output of `adb devices -l` into strongly typed
  /// [DeviceInfo] objects.
  List<DeviceInfo> parseDevicesOutput(String output) {
    final devices = <DeviceInfo>[];
    final lines = LineSplitter.split(output);

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('List of devices attached')) {
        continue;
      }

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }

      final serial = parts[0];
      final state = parts[1];
      if (state != 'device' ||
          serial.startsWith('emulator-') ||
          serial.startsWith('127.0.0.1')) {
        continue;
      }

      String model = 'Android Device';
      for (final part in parts) {
        if (part.startsWith('model:')) {
          model = part.substring(6).replaceAll('_', ' ');
        }
      }

      final isWifi = serial.contains(':');
      final mode = isWifi ? ConnectionMode.wifi : ConnectionMode.usb;
      String? ip;
      int port = 5555;

      if (isWifi) {
        final netParts = serial.split(':');
        ip = netParts[0];
        if (netParts.length > 1) {
          port = int.tryParse(netParts[1]) ?? 5555;
        }
      }

      devices.add(DeviceInfo(
        serial: serial,
        model: model,
        connectionMode: mode,
        ipAddress: ip,
        port: port,
        isOnline: true,
      ));
    }

    return devices;
  }

  /// Builds the proper targeting flag (`-d` for USB or `-s <serial>` for Wi-Fi)
  /// to eliminate ADB device ambiguity when multiple endpoints exist.
  List<String> getDeviceTargetFlags(DeviceInfo device) {
    if (device.isUsb) {
      return ['-d'];
    }
    return ['-s', device.serial];
  }

  /// Fetches battery percentage and operating state for the specified [device].
  Future<DeviceInfo> enrichDeviceTelemetry(DeviceInfo device) async {
    final target = getDeviceTargetFlags(device);
    final result = await execute([...target, 'shell', 'dumpsys', 'battery']);

    if (result.exitCode != 0) {
      return device;
    }

    final output = result.stdout as String;
    int? level;
    String? status;

    for (final line in LineSplitter.split(output)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('level:')) {
        level = int.tryParse(trimmed.substring(6).trim());
      } else if (trimmed.startsWith('status:')) {
        final code = int.tryParse(trimmed.substring(7).trim());
        status = _decodeBatteryStatus(code);
      }
    }

    return device.copyWith(
      batteryLevel: level,
      batteryStatus: status,
    );
  }

  /// Converts Android battery integer status codes to descriptive strings.
  String _decodeBatteryStatus(int? code) {
    switch (code) {
      case 2:
        return 'En charge';
      case 3:
        return 'Décharge';
      case 4:
        return 'Pas en charge';
      case 5:
        return 'Pleine';
      default:
        return 'Inconnu';
    }
  }

  /// Applies the software brightness workaround on Google Pixel devices.
  ///
  /// Lowers physical brightness to 0 to prevent OLED wear without blanking
  /// the Tensor hardware encoder buffer. Setting [dim] to `false` restores
  /// normal visibility (brightness 100).
  Future<bool> setScreenBrightness(DeviceInfo device, {bool dim = true}) async {
    final target = getDeviceTargetFlags(device);
    final brightnessValue = dim ? '0' : '100';
    final result = await execute([
      ...target,
      'shell',
      'settings',
      'put',
      'system',
      'screen_brightness',
      brightnessValue,
    ]);
    return result.exitCode == 0;
  }

  /// Configures Android settings so that the on-screen software keyboard remains
  /// visible even when scrcpy UHID keyboard forwarding is active.
  Future<bool> ensureVirtualKeyboardVisible(DeviceInfo device) async {
    final target = getDeviceTargetFlags(device);
    final result = await execute([
      ...target,
      'shell',
      'settings',
      'put',
      'secure',
      'show_ime_with_hard_keyboard',
      '1',
    ]);
    return result.exitCode == 0;
  }

  /// Terminates lingering background mirroring daemon processes on the phone
  /// to eliminate ghost virtual displays.
  Future<bool> terminateRemoteServerProcesses(DeviceInfo device) async {
    final target = getDeviceTargetFlags(device);
    final result = await execute([
      ...target,
      'shell',
      'pkill',
      '-9',
      '-f',
      'app_process',
    ]);
    return result.exitCode == 0;
  }

  /// Switches the ADB daemon on the USB-connected device into TCP/IP listening
  /// mode on the specified [port].
  Future<bool> switchDeviceToTcpip(DeviceInfo device, {int port = 5555}) async {
    final target = getDeviceTargetFlags(device);
    final result = await execute([...target, 'tcpip', port.toString()]);
    return result.exitCode == 0;
  }

  /// Connects to a device via its Wi-Fi [ipAddress] and TCP [port].
  Future<bool> connectWifi(String ipAddress, {int port = 5555}) async {
    final endpoint = '$ipAddress:$port';
    final result = await execute(['connect', endpoint]);
    if (result.exitCode != 0) {
      return false;
    }
    final output = result.stdout as String;
    return output.contains('connected to');
  }

  /// Disconnects an active TCP/IP wireless ADB connection.
  Future<bool> disconnectWifi(String ipAddress, {int port = 5555}) async {
    final endpoint = '$ipAddress:$port';
    final result = await execute(['disconnect', endpoint]);
    return result.exitCode == 0;
  }

  /// Dispatches an Android input keyevent to the target device.
  Future<bool> sendKeyEvent(DeviceInfo device, int keyCode) async {
    final target = getDeviceTargetFlags(device);
    final result = await execute([
      ...target,
      'shell',
      'input',
      'keyevent',
      keyCode.toString(),
    ]);
    return result.exitCode == 0;
  }

  /// Dismisses the Android lock screen keyguard if the phone is locked.
  Future<bool> unlockKeyguard(DeviceInfo device) async {
    final target = getDeviceTargetFlags(device);
    final result = await execute([
      ...target,
      'shell',
      'wm',
      'dismiss-keyguard',
    ]);
    return result.exitCode == 0;
  }
}
