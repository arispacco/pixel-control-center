import 'dart:convert';
import 'dart:io';

import '../models/connection_mode.dart';
import '../models/device_info.dart';

/// Captures a handset's prior display brightness settings so they can be
/// restored accurately after a dimmed mirroring session ends.
class ScreenBrightnessSnapshot {
  /// Saved `screen_brightness` value (typically 0..255).
  final int brightness;

  /// Saved `screen_brightness_mode` (`1` for adaptive/auto, `0` for manual).
  final int? mode;

  /// Creates a [ScreenBrightnessSnapshot].
  const ScreenBrightnessSnapshot({
    required this.brightness,
    this.mode,
  });
}

/// Provides asynchronous process operations and command utilities for the
/// Android Debug Bridge (ADB) daemon across all Android OEMs (Samsung, Xiaomi,
/// Tecno, Infinix, Oppo, Vivo, OnePlus, Google Pixel, etc.).
class AdbService {
  /// Executable name or absolute file path to the `adb` binary.
  final String adbPath;

  /// Creates an [AdbService] instance, locating the binary from standard
  /// directories or PATH.
  AdbService({String? customAdbPath})
      : adbPath = customAdbPath ?? findBundledExecutable('adb');

  /// Dynamically locates `adb` or `scrcpy` across WinGet installations,
  /// Android SDK Platform-Tools, or the system `PATH`.
  static String findBundledExecutable(String baseName) {
    if (!Platform.isWindows) {
      return baseName;
    }

    final exeName = '$baseName.exe';
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    if (localAppData.isNotEmpty) {
      final wingetPackages = Directory(
        '$localAppData\\Microsoft\\WinGet\\Packages',
      );
      if (wingetPackages.existsSync()) {
        try {
          final scrcpyPackages = wingetPackages
              .listSync()
              .whereType<Directory>()
              .where(
                (dir) => dir.path
                    .toLowerCase()
                    .contains('genymobile.scrcpy'),
              )
              .toList();

          for (final pkgDir in scrcpyPackages) {
            final directExe = File('${pkgDir.path}\\$exeName');
            if (directExe.existsSync()) {
              return directExe.path;
            }

            final versionDirs = pkgDir
                .listSync()
                .whereType<Directory>()
                .toList()
              ..sort((a, b) => b.path.compareTo(a.path));
            for (final subDir in versionDirs) {
              final nestedExe = File('${subDir.path}\\$exeName');
              if (nestedExe.existsSync()) {
                return nestedExe.path;
              }
            }
          }
        } catch (_) {
          // Fall back to SDK or PATH if directory traversal is restricted.
        }
      }

      if (baseName == 'adb') {
        final sdkAdb = File(
          '$localAppData\\Android\\Sdk\\platform-tools\\adb.exe',
        );
        if (sdkAdb.existsSync()) {
          return sdkAdb.path;
        }
      }
    }

    return exeName;
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

  /// Fetches battery percentage, manufacturer brand, and Android SDK version
  /// for the specified [device].
  Future<DeviceInfo> enrichDeviceTelemetry(DeviceInfo device) async {
    final target = getDeviceTargetFlags(device);
    final results = await Future.wait([
      execute([...target, 'shell', 'dumpsys', 'battery']),
      execute([...target, 'shell', 'getprop', 'ro.product.brand']),
      execute([...target, 'shell', 'getprop', 'ro.build.version.sdk']),
      execute([...target, 'shell', 'getprop', 'ro.product.model']),
    ]);

    final batteryResult = results[0];
    int? level = device.batteryLevel;
    String? status = device.batteryStatus;

    if (batteryResult.exitCode == 0) {
      final output = batteryResult.stdout as String;
      for (final line in LineSplitter.split(output)) {
        final trimmed = line.trim();
        if (trimmed.startsWith('level:')) {
          level = int.tryParse(trimmed.substring(6).trim());
        } else if (trimmed.startsWith('status:')) {
          final code = int.tryParse(trimmed.substring(7).trim());
          status = _decodeBatteryStatus(code);
        }
      }
    }

    String? brand = device.brand;
    if (results[1].exitCode == 0) {
      final rawBrand = (results[1].stdout as String).trim();
      if (rawBrand.isNotEmpty) {
        brand = rawBrand;
      }
    }

    int? sdkInt = device.sdkInt;
    if (results[2].exitCode == 0) {
      sdkInt = int.tryParse((results[2].stdout as String).trim()) ?? sdkInt;
    }

    String model = device.model;
    if (results[3].exitCode == 0) {
      final propModel = (results[3].stdout as String).trim();
      if (propModel.isNotEmpty &&
          (model == 'Android Device' || model.isEmpty)) {
        model = propModel;
      }
    }

    return device.copyWith(
      model: model,
      batteryLevel: level,
      batteryStatus: status,
      brand: brand,
      sdkInt: sdkInt,
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

  /// Captures the phone's current brightness and adaptive brightness mode,
  /// switches temporarily to manual mode, and lowers backlight to 0.
  ///
  /// Used automatically for Google Tensor devices (where `POWER_MODE_OFF`
  /// blanks the video encoder) or when software dimming is explicitly requested.
  Future<ScreenBrightnessSnapshot> captureAndDimScreen(DeviceInfo device) async {
    final target = getDeviceTargetFlags(device);
    final reads = await Future.wait([
      execute([...target, 'shell', 'settings', 'get', 'system', 'screen_brightness']),
      execute([
        ...target,
        'shell',
        'settings',
        'get',
        'system',
        'screen_brightness_mode',
      ]),
    ]);

    final parsedBrightness = reads[0].exitCode == 0
        ? int.tryParse((reads[0].stdout as String).trim())
        : null;
    final parsedMode = reads[1].exitCode == 0
        ? int.tryParse((reads[1].stdout as String).trim())
        : null;

    final safeBrightness =
        (parsedBrightness != null && parsedBrightness > 5) ? parsedBrightness : 120;

    if (parsedMode == 1) {
      await execute([
        ...target,
        'shell',
        'settings',
        'put',
        'system',
        'screen_brightness_mode',
        '0',
      ]);
    }

    await execute([
      ...target,
      'shell',
      'settings',
      'put',
      'system',
      'screen_brightness',
      '0',
    ]);

    return ScreenBrightnessSnapshot(
      brightness: safeBrightness,
      mode: parsedMode,
    );
  }

  /// Restores the phone's exact prior brightness and adaptive brightness mode
  /// captured by [captureAndDimScreen].
  Future<void> restoreScreenBrightness(
    DeviceInfo device,
    ScreenBrightnessSnapshot? snapshot,
  ) async {
    final target = getDeviceTargetFlags(device);
    final restoredBrightness = (snapshot?.brightness ?? 120).toString();
    await execute([
      ...target,
      'shell',
      'settings',
      'put',
      'system',
      'screen_brightness',
      restoredBrightness,
    ]);

    if (snapshot?.mode != null) {
      await execute([
        ...target,
        'shell',
        'settings',
        'put',
        'system',
        'screen_brightness_mode',
        snapshot!.mode.toString(),
      ]);
    }
  }

  /// Applies or clears a simple software brightness override (`0` vs `120`).
  Future<bool> setScreenBrightness(DeviceInfo device, {bool dim = true}) async {
    final target = getDeviceTargetFlags(device);
    final brightnessValue = dim ? '0' : '120';
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
