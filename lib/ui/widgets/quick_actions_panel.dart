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

  /// Callback to open the zero-ADB live Wi-Fi Cast receiver screen.
  final VoidCallback onStartCast;

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
    required this.onStartCast,
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
            Row(
              children: [
                const Icon(
                  Icons.cast_connected,
                  size: 18,
                  color: AppTheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Diffusion Simple en Direct (Grand Public — Sans Mode Débogage)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Affiche uniquement l\'image du téléphone en direct par Wi-Fi sans activer les Options développeur ni ADB. Le tactile du téléphone reste libre.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onStartCast,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text(
                'Ouvrir le Récepteur Cast Wi-Fi Direct (Sans Débogage)',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1),
            ),
            Text(
              'Contrôle Complet depuis le PC (Mode Débogage ADB — Écran Cassé / Avancé)',
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
                  label: const Text('Contrôler par Câble (USB ADB)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.usbColor,
                    foregroundColor: Colors.white,
                  ),
                ),
                FilledButton.icon(
                  onPressed: isMirroring ? null : onStartWifi,
                  icon: const Icon(Icons.wifi),
                  label: const Text('Contrôler sans Fil (Wi-Fi ADB)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.wifiColor,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isMirroring ? null : onStartScreenOff,
                  icon: const Icon(Icons.brightness_low),
                  label: const Text('Mode Écran Éteint (OLED)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.secondary,
                    side: const BorderSide(color: AppTheme.secondary),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onAutoConnectWifi,
                  icon: const Icon(Icons.autorenew),
                  label: const Text('Détection Auto ADB Wi-Fi'),
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
