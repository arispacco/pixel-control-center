import 'package:flutter/material.dart';

import '../../models/connection_mode.dart';
import '../../models/device_info.dart';
import '../../models/discovered_peer.dart';
import '../theme.dart';

/// Renders a responsive summary card displaying the device name, serial,
/// battery level, active connection mode badge, and discovered Wi-Fi LAN peers.
class DeviceStatusCard extends StatelessWidget {
  /// Information model representing the active or selected Android handset.
  final DeviceInfo? device;

  /// Reachable peers detected on the local Wi-Fi or Hotspot network (ARP / Gateway / mDNS).
  final List<DiscoveredPeer> lanPeers;

  /// Whether a background scan or ADB refresh is currently executing.
  final bool isScanning;

  /// Callback triggered when the refresh button is pressed.
  final VoidCallback onRefresh;

  /// Creates a [DeviceStatusCard] widget.
  const DeviceStatusCard({
    super.key,
    required this.device,
    this.lanPeers = const [],
    required this.isScanning,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final topPeer = lanPeers.isNotEmpty ? lanPeers.first : null;
    final headerText = device != null
        ? device!.displayName
        : topPeer != null
            ? 'Téléphone détecté sur le Wi-Fi : ${topPeer.ip}'
            : 'Aucun appareil ADB détecté';
    final subtitleText = device != null
        ? 'S/N: ${device!.serial}${device!.sdkInt != null ? ' • API ${device!.sdkInt}' : ''}'
        : lanPeers.isNotEmpty
            ? 'Réseau local : ${lanPeers.map((p) => p.summaryLabel).join('  •  ')}'
            : 'Compatible tous smartphones Android (Samsung, Xiaomi, Tecno, Infinix, Pixel…) par Wi-Fi ou USB';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (device != null || topPeer != null
                        ? AppTheme.primary
                        : Colors.white54)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                topPeer != null && device == null
                    ? Icons.wifi_tethering
                    : Icons.phone_android,
                size: 32,
                color: device != null || topPeer != null
                    ? AppTheme.primary
                    : Colors.white70,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headerText,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitleText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ],
              ),
            ),
            if (device != null) ...[
              _buildConnectionBadge(device!),
              const SizedBox(width: 12),
              _buildBatteryBadge(device!),
              const SizedBox(width: 12),
            ] else if (topPeer != null) ...[
              _buildLanPeerBadge(topPeer),
              const SizedBox(width: 12),
            ],
            IconButton(
              icon: isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: 'Rafraîchir et scanner le Wi-Fi',
              onPressed: isScanning ? null : onRefresh,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanPeerBadge(DiscoveredPeer peer) {
    final isCastReady = peer.castHttpPort != null;
    final color = isCastReady ? AppTheme.secondary : AppTheme.wifiColor;
    final label = isCastReady
        ? 'Cast :${peer.castHttpPort}'
        : peer.isGateway
            ? 'Hotspot'
            : 'Wi-Fi LAN';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCastReady ? Icons.cast_connected : Icons.wifi,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionBadge(DeviceInfo dev) {
    final isUsb = dev.connectionMode == ConnectionMode.usb;
    final color = isUsb ? AppTheme.usbColor : AppTheme.wifiColor;
    final label = isUsb ? 'USB' : 'Wi-Fi';
    final icon = isUsb ? Icons.usb : Icons.wifi;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryBadge(DeviceInfo dev) {
    final level = dev.batteryLevel ?? 0;
    final status = dev.batteryStatus ?? '';
    final isCharging = status.toLowerCase().contains('charge');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCharging ? Icons.battery_charging_full : Icons.battery_std,
            size: 14,
            color: Colors.amber,
          ),
          const SizedBox(width: 6),
          Text(
            '$level%',
            style: const TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
