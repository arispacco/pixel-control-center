/// Represents a reachable device or service endpoint discovered on the local
/// Wi-Fi or Mobile Hotspot network.
class DiscoveredPeer {
  /// IPv4 address of the discovered device on the local subnet.
  final String ip;

  /// Open wireless ADB TCP port (`5555` or dynamic Android 11+ mDNS port),
  /// or `null` if no ADB socket responded on this host.
  final int? adbPort;

  /// Open zero-ADB Wi-Fi Cast HTTP MJPEG port (typically `8080`), or `null`
  /// if no active cast stream server was detected on this host.
  final int? castHttpPort;

  /// Whether this IP is the active Wi-Fi Default Gateway (for example, an
  /// Android phone sharing its Mobile Hotspot with the PC).
  final bool isGateway;

  /// Whether the host answered an ARP/ICMP/TCP liveness check on the LAN.
  final bool isReachable;

  /// Discovery mechanism that identified this peer (`adb-active`, `usb-wlan`,
  /// `adb-mdns`, `cast-http`, `lan-adb`, `hotspot-gateway`, `arp-peer`).
  final String source;

  /// Creates a [DiscoveredPeer] record.
  const DiscoveredPeer({
    required this.ip,
    this.adbPort,
    this.castHttpPort,
    this.isGateway = false,
    this.isReachable = true,
    this.source = 'lan',
  });

  /// Human-readable role summary displayed in the desktop UI.
  String get summaryLabel {
    if (castHttpPort != null) {
      return '$ip:$castHttpPort (Cast Wi-Fi actif)';
    }
    if (adbPort != null) {
      return '$ip:$adbPort (ADB sans fil prêt)';
    }
    if (isGateway) {
      return '$ip (Passerelle / Téléphone Hotspot)';
    }
    return '$ip (Appareil actif sur le Wi-Fi)';
  }

  /// Returns a copy with updated properties.
  DiscoveredPeer copyWith({
    String? ip,
    int? adbPort,
    int? castHttpPort,
    bool? isGateway,
    bool? isReachable,
    String? source,
  }) {
    return DiscoveredPeer(
      ip: ip ?? this.ip,
      adbPort: adbPort ?? this.adbPort,
      castHttpPort: castHttpPort ?? this.castHttpPort,
      isGateway: isGateway ?? this.isGateway,
      isReachable: isReachable ?? this.isReachable,
      source: source ?? this.source,
    );
  }
}
