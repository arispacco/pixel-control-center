import 'package:flutter/material.dart';

import '../../models/device_info.dart';
import '../theme.dart';

/// Provides primary action buttons to launch mirroring sessions or trigger
/// automatic wireless network discovery.
class QuickActionsPanel extends StatelessWidget {
  /// Currently selected or detected handset.
  final DeviceInfo? device;

  /// Whether a scrcpy mirroring session is actively streaming.
  final bool isMirroring;

  /// Callback to start mirroring over USB with standard parameters.
  final VoidCallback onStartUsb;

  /// Callback to start mirroring over local Wi-Fi.
  final VoidCallback onStartWifi;

  /// Callback to start mirroring with physical screen dimming active.
  final VoidCallback onStartScreenOff;

  /// Callback to initiate multi-tier dynamic IP discovery and connection.
  final VoidCallback onAutoConnectWifi;

  /// Callback to terminate the active mirroring session.
  final VoidCallback onStopMirroring;

  /// Creates a [QuickActionsPanel] widget.
  const QuickActionsPanel({
    super.key,
    required this.device,
    required this.isMirroring,
    required this.onStartUsb,
    required this.onStartWifi,
    required this.onStartScreenOff,
    required this.onAutoConnectWifi,
    required this.onStopMirroring,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actions Rapides',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: isMirroring ? null : onStartUsb,
                  icon: const Icon(Icons.usb),
                  label: const Text('Afficher Écran (USB)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.usbColor,
                    foregroundColor: Colors.white,
                  ),
                ),
                FilledButton.icon(
                  onPressed: isMirroring ? null : onStartWifi,
                  icon: const Icon(Icons.wifi),
                  label: const Text('Afficher Écran (Wi-Fi)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.wifiColor,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isMirroring ? null : onStartScreenOff,
                  icon: const Icon(Icons.brightness_low),
                  label: const Text('Mode Écran Éteint'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.secondary,
                    side: const BorderSide(color: AppTheme.secondary),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onAutoConnectWifi,
                  icon: const Icon(Icons.autorenew),
                  label: const Text('Détection & Auto-Connexion Wi-Fi'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                  ),
                ),
                if (isMirroring)
                  FilledButton.icon(
                    onPressed: onStopMirroring,
                    icon: const Icon(Icons.stop_circle),
                    label: const Text('Arrêter la Session'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
