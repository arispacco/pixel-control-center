import 'package:flutter/material.dart';

import '../../models/connection_mode.dart';
import '../../models/device_info.dart';
import '../theme.dart';

/// Renders a responsive summary card displaying the device name, serial,
/// battery level, and active connection mode badge.
class DeviceStatusCard extends StatelessWidget {
  /// Information model representing the active or selected Android handset.
  final DeviceInfo? device;

  /// Whether a background scan or ADB refresh is currently executing.
  final bool isScanning;

  /// Callback triggered when the refresh button is pressed.
  final VoidCallback onRefresh;

  /// Creates a [DeviceStatusCard] widget.
  const DeviceStatusCard({
    super.key,
    required this.device,
    required this.isScanning,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.phone_android,
                size: 32,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device?.model ?? 'Aucun appareil détecté',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    device != null
                        ? 'S/N: ${device!.serial}'
                        : 'Connectez votre Pixel par USB ou activez le Wi-Fi',
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
            ],
            IconButton(
              icon: isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: 'Rafraîchir les appareils',
              onPressed: isScanning ? null : onRefresh,
            ),
          ],
        ),
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
