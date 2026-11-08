import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/device_info.dart';
import '../models/discovered_peer.dart';
import 'adb_service.dart';

/// Provides zero-configuration discovery of Android devices on local Wi-Fi and
/// Mobile Hotspot networks across both ADB (classic `:5555` + Android 11+
/// dynamic mDNS ports) and Zero-ADB Wi-Fi Cast (`:8080`), plus ARP/Gateway
/// liveness detection.
class NetworkDiscoveryService {
  /// ADB service instance used for device and shell inspection.
  final AdbService adbService;

  /// Default TCP port assigned to classic `adb tcpip` wireless debugging.
  static const int defaultAdbPort = 5555;

  /// Default HTTP port served by the zero-ADB `Android Wi-Fi Cast` companion app.
  static const int defaultCastHttpPort = 8080;

  /// Creates a [NetworkDiscoveryService] bound to the given [adbService].
  const NetworkDiscoveryService({required this.adbService});

  /// Discovers all reachable peers, wireless ADB endpoints, and active Wi-Fi
  /// Cast streams on the current Wi-Fi / Hotspot network.
  ///
  /// Ordered by highest actionability first:
  /// 1. Active Wi-Fi ADB sessions
  /// 2. USB-bridged phone Wi-Fi / Hotspot IPs
  /// 3. Android 11–17 Wireless Debugging mDNS dynamic endpoints (`ip:port`)
  /// 4. Active `Android Wi-Fi Cast` (`:8080`) or `adb tcpip` (`:5555`) hosts
  /// 5. Reachable Hotspot Default Gateway & ARP table neighbors on the Wi-Fi LAN
  Future<List<DiscoveredPeer>> discoverLanPeers({
    DeviceInfo? knownUsbDevice,
    bool scanFullSubnet = true,
  }) async {
    final peersByIp = <String, DiscoveredPeer>{};

    void upsertPeer(DiscoveredPeer candidate) {
      final existing = peersByIp[candidate.ip];
      if (existing == null) {
        peersByIp[candidate.ip] = candidate;
      } else {
        peersByIp[candidate.ip] = existing.copyWith(
          adbPort: candidate.adbPort ?? existing.adbPort,
          castHttpPort: candidate.castHttpPort ?? existing.castHttpPort,
          isGateway: existing.isGateway || candidate.isGateway,
          isReachable: existing.isReachable || candidate.isReachable,
        );
      }
    }

    // Tier 1: Existing wireless ADB connections (any port).
    for (final peer in await _checkActiveAdbConnections()) {
      upsertPeer(peer);
    }

    // Tier 2: Query Wi-Fi / Hotspot IP directly from a USB-connected phone.
    final usbIp = await _queryUsbDeviceIp(knownUsbDevice);
    if (usbIp != null) {
      final has5555 = await _isTcpPortOpen(usbIp, defaultAdbPort, timeoutMs: 220);
      final has8080 = await _isTcpPortOpen(
        usbIp,
        defaultCastHttpPort,
        timeoutMs: 220,
      );
      upsertPeer(
        DiscoveredPeer(
          ip: usbIp,
          adbPort: has5555 ? defaultAdbPort : null,
          castHttpPort: has8080 ? defaultCastHttpPort : null,
          source: 'usb-wlan',
        ),
      );
    }

    // Tier 3: Android 11+ Wireless Debugging mDNS services (preserves dynamic port!).
    for (final mdnsPeer in await _queryMdnsServices()) {
      upsertPeer(mdnsPeer);
    }

    // Tier 4: Gateway + ARP table fast check (~150 ms) before full /24 sweep.
    final localSubnets = await _getPhysicalLanHostIps();
    final gateways = await _getDefaultGateways(localSubnets);
    final arpIps = await _getArpNeighborIps(localSubnets);

    final priorityIps = <String>{
      ...gateways,
      ...arpIps,
    }.where((ip) => !localSubnets.contains(ip)).toList();

    final priorityResults = await Future.wait(
      priorityIps.map(
        (ip) => _inspectCandidateHost(
          ip,
          isGateway: gateways.contains(ip),
          checkPingIfPortsClosed: true,
        ),
      ),
    );
    for (final peer in priorityResults) {
      if (peer != null) {
        upsertPeer(peer);
      }
    }

    // Tier 5: Full /24 subnet scan for open ADB (:5555) or Wi-Fi Cast (:8080)
    // in case ARP cache was cold for a newly joined device.
    final hasActionableService = peersByIp.values.any(
      (p) => p.adbPort != null || p.castHttpPort != null,
    );
    if (scanFullSubnet && !hasActionableService) {
      final scanned = await _scanSubnetServicePorts(
        localSubnets,
        alreadyChecked: priorityIps.toSet(),
        gateways: gateways,
      );
      for (final peer in scanned) {
        upsertPeer(peer);
      }
    }

    final sorted = peersByIp.values.toList()
      ..sort((a, b) => _peerPriorityScore(b).compareTo(_peerPriorityScore(a)));
    return sorted;
  }

  int _peerPriorityScore(DiscoveredPeer p) {
    var score = 0;
    if (p.castHttpPort != null) score += 100;
    if (p.adbPort != null) score += 90;
    if (p.source == 'usb-wlan') score += 50;
    if (p.isGateway) score += 20;
    if (p.isReachable) score += 10;
    return score;
  }

  /// Discovers the best wireless ADB endpoint (`ip` + `adbPort`), or falls back
  /// to a USB-discovered IP so the caller can switch USB into TCP/IP mode.
  Future<DiscoveredPeer?> discoverAdbEndpoint({
    DeviceInfo? knownUsbDevice,
  }) async {
    final peers = await discoverLanPeers(knownUsbDevice: knownUsbDevice);
    for (final peer in peers) {
      if (peer.adbPort != null || peer.source == 'usb-wlan') {
        return peer;
      }
    }
    return peers.isNotEmpty ? peers.first : null;
  }

  /// Legacy helper returning the top discovered IPv4 address on the LAN.
  Future<String?> discoverDeviceIp({DeviceInfo? knownUsbDevice}) async {
    final best = await discoverAdbEndpoint(knownUsbDevice: knownUsbDevice);
    return best?.ip;
  }

  /// Checks if any connected ADB device already exposes a valid TCP/IP endpoint.
  Future<List<DiscoveredPeer>> _checkActiveAdbConnections() async {
    final devices = await adbService.getConnectedDevices();
    final found = <DiscoveredPeer>[];
    for (final device in devices) {
      if (device.isWifi && device.ipAddress != null) {
        found.add(
          DiscoveredPeer(
            ip: device.ipAddress!,
            adbPort: device.port,
            source: 'adb-active',
          ),
        );
      }
    }
    return found;
  }

  /// Queries the wireless or hotspot interface of a physical USB device via ADB.
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
    for (final iface in const ['wlan0', 'swlan0', 'wlan1', 'ap0']) {
      final result = await adbService.execute([
        ...targetFlags,
        'shell',
        'ip',
        'addr',
        'show',
        iface,
      ]);

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final match =
            RegExp(r'inet\s+(\d+\.\d+\.\d+\.\d+)/\d+').firstMatch(output);
        if (match != null) {
          return match.group(1);
        }
      }
    }

    // Secondary route query fallback prioritizing Wi-Fi / hotspot interfaces
    // over cellular data interfaces (rmnet / ccmni).
    final routeResult = await adbService.execute([
      ...targetFlags,
      'shell',
      'ip',
      'route',
    ]);
    if (routeResult.exitCode == 0) {
      final output = routeResult.stdout as String;
      String? fallbackRouteIp;
      for (final line in LineSplitter.split(output)) {
        final match = RegExp(r'src\s+(\d+\.\d+\.\d+\.\d+)').firstMatch(line);
        if (match == null) continue;
        final ip = match.group(1)!;
        final lower = line.toLowerCase();
        if (lower.contains('wlan') ||
            lower.contains('swlan') ||
            lower.contains('ap') ||
            lower.contains('rndis')) {
          return ip;
        }
        if (!lower.contains('rmnet') && !lower.contains('ccmni')) {
          fallbackRouteIp ??= ip;
        }
      }
      if (fallbackRouteIp != null) {
        return fallbackRouteIp;
      }
    }

    return null;
  }

  /// Parses `adb mdns services` output, preserving dynamic Android 11+ ports
  /// (e.g. `_adb-tls-connect._tcp. 192.168.1.45:41823`) instead of assuming 5555.
  List<DiscoveredPeer> parseMdnsServicesOutput(String output) {
    final connectPeers = <DiscoveredPeer>[];
    for (final line in LineSplitter.split(output)) {
      if (line.contains('_adb-tls-pairing._tcp')) {
        // Pairing port requires a 6-digit pairing code, not `adb connect`.
        continue;
      }
      final match = RegExp(r'(\d+\.\d+\.\d+\.\d+):(\d+)').firstMatch(line);
      if (match == null) continue;
      final ip = match.group(1)!;
      final port = int.tryParse(match.group(2)!);
      if (ip == '127.0.0.1' || port == null || port <= 0) continue;

      connectPeers.add(
        DiscoveredPeer(
          ip: ip,
          adbPort: port,
          source: 'adb-mdns',
        ),
      );
    }
    return connectPeers;
  }

  Future<List<DiscoveredPeer>> _queryMdnsServices() async {
    final result = await adbService.execute(['mdns', 'services']);
    if (result.exitCode != 0) {
      return const [];
    }
    return parseMdnsServicesOutput(result.stdout as String);
  }

  /// Parses IPv4 Default Gateways from `ipconfig` (Windows) or `ip route` (Linux).
  Set<String> parseDefaultGateways(
    String commandOutput, {
    Set<String>? allowedPrefixes,
  }) {
    final gateways = <String>{};
    for (final line in LineSplitter.split(commandOutput)) {
      final lower = line.toLowerCase();
      final isGatewayLine = lower.contains('gateway') ||
          lower.contains('passerelle') ||
          lower.startsWith('default via ');
      if (!isGatewayLine) continue;

      for (final m in RegExp(r'(\d+\.\d+\.\d+\.\d+)').allMatches(line)) {
        final ip = m.group(1)!;
        if (!_isValidUnicastLanIp(ip)) continue;
        if (allowedPrefixes != null &&
            allowedPrefixes.isNotEmpty &&
            !allowedPrefixes.contains(_subnetPrefix(ip))) {
          continue;
        }
        gateways.add(ip);
      }
    }
    return gateways;
  }

  /// Parses unicast neighbor IPv4 addresses from `arp -a` or `ip neigh` output.
  Set<String> parseArpNeighbors(
    String arpOutput, {
    Set<String>? allowedPrefixes,
  }) {
    final neighbors = <String>{};
    for (final line in LineSplitter.split(arpOutput)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.toLowerCase().startsWith('interface') ||
          trimmed.toLowerCase().contains('incomplete') ||
          trimmed.toLowerCase().contains('failed')) {
        continue;
      }

      final match = RegExp(r'(\d+\.\d+\.\d+\.\d+)').firstMatch(trimmed);
      if (match == null) continue;
      final ip = match.group(1)!;
      if (!_isValidUnicastLanIp(ip)) continue;

      if (allowedPrefixes != null &&
          allowedPrefixes.isNotEmpty &&
          !allowedPrefixes.contains(_subnetPrefix(ip))) {
        continue;
      }
      neighbors.add(ip);
    }
    return neighbors;
  }

  bool _isValidUnicastLanIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return false;

    final first = octets[0]!;
    final last = octets[3]!;
    if (first == 0 || first == 127 || first >= 224) return false;
    if (first == 169 && octets[1] == 254) return false;
    if (last == 0 || last == 255) return false;
    return true;
  }

  String _subnetPrefix(String ip) {
    final idx = ip.lastIndexOf('.');
    return idx > 0 ? ip.substring(0, idx) : ip;
  }

  Future<List<String>> _getPhysicalLanHostIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final primary = <String>[];
      final fallback = <String>[];

      for (final iface in interfaces) {
        final lower = iface.name.toLowerCase();
        final isVirtual = lower.contains('vethernet') ||
            lower.contains('wsl') ||
            lower.contains('docker') ||
            lower.contains('vmware') ||
            lower.contains('virtualbox') ||
            lower.contains('hyper-v') ||
            lower.contains('loopback');

        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (!_isValidUnicastLanIp(ip)) continue;
          if (isVirtual) {
            fallback.add(ip);
          } else {
            primary.add(ip);
          }
        }
      }
      return primary.isNotEmpty ? primary : fallback;
    } catch (_) {
      return const [];
    }
  }

  Future<Set<String>> _getDefaultGateways(List<String> hostIps) async {
    final prefixes = hostIps.map(_subnetPrefix).toSet();
    try {
      final result = Platform.isWindows
          ? await Process.run('ipconfig', const [])
          : await Process.run('ip', const ['route']);
      if (result.exitCode != 0) return const {};
      return parseDefaultGateways(
        result.stdout.toString(),
        allowedPrefixes: prefixes,
      );
    } catch (_) {
      return const {};
    }
  }

  Future<Set<String>> _getArpNeighborIps(List<String> hostIps) async {
    final prefixes = hostIps.map(_subnetPrefix).toSet();
    try {
      final result = await Process.run('arp', const ['-a']);
      if (result.exitCode != 0) return const {};
      return parseArpNeighbors(
        result.stdout.toString(),
        allowedPrefixes: prefixes,
      );
    } catch (_) {
      return const {};
    }
  }

  Future<DiscoveredPeer?> _inspectCandidateHost(
    String ip, {
    required bool isGateway,
    required bool checkPingIfPortsClosed,
  }) async {
    final checks = await Future.wait([
      _isTcpPortOpen(ip, defaultAdbPort, timeoutMs: 220),
      _isTcpPortOpen(ip, defaultCastHttpPort, timeoutMs: 220),
    ]);
    final adbOpen = checks[0];
    final castOpen = checks[1];

    if (adbOpen || castOpen) {
      return DiscoveredPeer(
        ip: ip,
        adbPort: adbOpen ? defaultAdbPort : null,
        castHttpPort: castOpen ? defaultCastHttpPort : null,
        isGateway: isGateway,
        isReachable: true,
        source: castOpen ? 'cast-http' : 'lan-adb',
      );
    }

    if (!checkPingIfPortsClosed) {
      return null;
    }

    final alive = await _pingHostOnce(ip);
    if (!alive) return null;

    return DiscoveredPeer(
      ip: ip,
      isGateway: isGateway,
      isReachable: true,
      source: isGateway ? 'hotspot-gateway' : 'arp-peer',
    );
  }

  Future<bool> _isTcpPortOpen(
    String ip,
    int port, {
    int timeoutMs = 180,
  }) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _pingHostOnce(String ip) async {
    try {
      final args = Platform.isWindows
          ? ['-n', '1', '-w', '300', ip]
          : ['-c', '1', '-W', '1', ip];
      final res = await Process.run('ping', args);
      final out = res.stdout.toString().toLowerCase();
      return out.contains('ttl=');
    } catch (_) {
      return false;
    }
  }

  Future<List<DiscoveredPeer>> _scanSubnetServicePorts(
    List<String> hostIps, {
    required Set<String> alreadyChecked,
    required Set<String> gateways,
  }) async {
    final found = <DiscoveredPeer>[];
    final candidateIps = <String>[];

    for (final hostIp in hostIps) {
      final prefix = _subnetPrefix(hostIp);
      for (int i = 1; i <= 254; i++) {
        final ip = '$prefix.$i';
        if (ip != hostIp && !alreadyChecked.contains(ip)) {
          candidateIps.add(ip);
        }
      }
    }

    const chunkSize = 48;
    for (int i = 0; i < candidateIps.length; i += chunkSize) {
      final end = (i + chunkSize < candidateIps.length)
          ? i + chunkSize
          : candidateIps.length;
      final chunk = candidateIps.sublist(i, end);

      final results = await Future.wait(
        chunk.map(
          (ip) => _inspectCandidateHost(
            ip,
            isGateway: gateways.contains(ip),
            checkPingIfPortsClosed: false,
          ),
        ),
      );

      for (final peer in results) {
        if (peer != null) {
          found.add(peer);
        }
      }
      if (found.isNotEmpty) {
        break;
      }
    }

    return found;
  }

  /// Discovers the handset endpoint and initiates a wireless ADB connection
  /// using the exact detected port (`5555` or dynamic Android 11+ mDNS port).
  Future<bool> autoConnect() async {
    final endpoint = await discoverAdbEndpoint();
    if (endpoint == null || endpoint.adbPort == null) {
      return false;
    }
    return adbService.connectWifi(endpoint.ip, port: endpoint.adbPort!);
  }
}
