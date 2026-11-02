import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/device_info.dart';
import 'adb_service.dart';

/// Provides zero-configuration discovery of Android devices on the local area
/// network using a multi-tiered heuristic strategy.
class NetworkDiscoveryService {
  /// ADB service instance used for device and shell inspection.
  final AdbService adbService;

  /// Default TCP port assigned to wireless ADB.
  static const int defaultAdbPort = 5555;

  /// Creates a [NetworkDiscoveryService] bound to the given [adbService].
  const NetworkDiscoveryService({required this.adbService});

  /// Executes the 4-tier discovery sequence to identify the phone's local IP.
  ///
  /// Returns the discovered IPv4 address string, or `null` if unreachable.
  Future<String?> discoverDeviceIp({DeviceInfo? knownUsbDevice}) async {
    // Tier 1: Check existing wireless ADB connections.
    final existingIp = await _checkActiveAdbConnections();
    if (existingIp != null) {
      return existingIp;
    }

    // Tier 2: Query IP directly from USB-connected device if available.
    final usbIp = await _queryUsbDeviceIp(knownUsbDevice);
    if (usbIp != null) {
      return usbIp;
    }

    // Tier 3: Query ADB mDNS service discovery daemon.
    final mdnsIp = await _queryMdnsServices();
    if (mdnsIp != null) {
      return mdnsIp;
    }

    // Tier 4: Parallel subnet socket probe on port 5555.
    return _probeLocalSubnets();
  }

  /// Checks if any connected ADB device already exposes a valid TCP/IP endpoint.
  Future<String?> _checkActiveAdbConnections() async {
    final devices = await adbService.getConnectedDevices();
    for (final device in devices) {
      if (device.isWifi && device.ipAddress != null) {
        return device.ipAddress;
      }
    }
    return null;
  }

  /// Queries the wireless interface of a physical USB device via ADB shell.
  Future<String?> _queryUsbDeviceIp(DeviceInfo? knownUsbDevice) async {
    DeviceInfo? target = knownUsbDevice;
    if (target == null) {
      final devices = await adbService.getConnectedDevices();
      for (final device in devices) {
        if (device.isUsb) {
          target = device;
          break;
        }
      }
    }

    if (target == null) {
      return null;
    }

    final targetFlags = adbService.getDeviceTargetFlags(target);
    final result = await adbService.execute([
      ...targetFlags,
      'shell',
      'ip',
      'addr',
      'show',
      'wlan0',
    ]);

    if (result.exitCode == 0) {
      final output = result.stdout as String;
      final match = RegExp(r'inet\s+(\d+\.\d+\.\d+\.\d+)/\d+').firstMatch(output);
      if (match != null) {
        return match.group(1);
      }
    }

    // Secondary route query fallback.
    final routeResult = await adbService.execute([
      ...targetFlags,
      'shell',
      'ip',
      'route',
    ]);
    if (routeResult.exitCode == 0) {
      final output = routeResult.stdout as String;
      final match = RegExp(r'src\s+(\d+\.\d+\.\d+\.\d+)').firstMatch(output);
      if (match != null) {
        return match.group(1);
      }
    }

    return null;
  }

  /// Inspects mDNS service registrations reported by the ADB daemon.
  Future<String?> _queryMdnsServices() async {
    final result = await adbService.execute(['mdns', 'services']);
    if (result.exitCode != 0) {
      return null;
    }

    final output = result.stdout as String;
    for (final line in LineSplitter.split(output)) {
      final match = RegExp(r'(\d+\.\d+\.\d+\.\d+):5555').firstMatch(line);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  /// Scans the local network subnets for responsive ADB listening ports.
  Future<String?> _probeLocalSubnets() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      final candidateIps = <String>[];

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final hostIp = addr.address;
          if (hostIp.startsWith('127.') || hostIp.startsWith('169.254.')) {
            continue;
          }

          final lastDot = hostIp.lastIndexOf('.');
          if (lastDot == -1) continue;
          final prefix = hostIp.substring(0, lastDot);

          // Populate the /24 subnet addresses (1..254).
          for (int i = 1; i <= 254; i++) {
            final candidate = '$prefix.$i';
            if (candidate != hostIp) {
              candidateIps.add(candidate);
            }
          }
        }
      }

      // Concurrently probe candidate IPs in chunks of 32.
      const chunkSize = 32;
      for (int i = 0; i < candidateIps.length; i += chunkSize) {
        final end = (i + chunkSize < candidateIps.length)
            ? i + chunkSize
            : candidateIps.length;
        final chunk = candidateIps.sublist(i, end);

        final futures = chunk.map(_probeSingleIp);
        final results = await Future.wait(futures);

        for (final resolvedIp in results) {
          if (resolvedIp != null) {
            return resolvedIp;
          }
        }
      }
    } catch (_) {
      // Gracefully catch permission or network socket restrictions.
    }
    return null;
  }

  /// Attempts a fast TCP socket connection to [ipAddress] on port 5555.
  Future<String?> _probeSingleIp(String ipAddress) async {
    try {
      final socket = await Socket.connect(
        ipAddress,
        defaultAdbPort,
        timeout: const Duration(milliseconds: 180),
      );
      socket.destroy();
      return ipAddress;
    } catch (_) {
      return null;
    }
  }

  /// Discovers the handset IP and initiates a wireless ADB connection.
  Future<bool> autoConnect() async {
    final discoveredIp = await discoverDeviceIp();
    if (discoveredIp == null) {
      return false;
    }
    return adbService.connectWifi(discoveredIp, port: defaultAdbPort);
  }
}
