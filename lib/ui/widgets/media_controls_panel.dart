import 'package:flutter/material.dart';

import '../../models/device_info.dart';
import '../theme.dart';

/// Provides quick hardware remote key dispatches for volume, power, back,
/// and home navigation.
class MediaControlsPanel extends StatelessWidget {
  /// Target handset receiving keyevents.
  final DeviceInfo? device;

  /// Dispatches the keycode to the target device.
  final ValueChanged<int> onSendKeyEvent;

  /// Creates a [MediaControlsPanel] widget.
  const MediaControlsPanel({
    super.key,
    required this.device,
    required this.onSendKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = device != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Télécommande & Navigation',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.volume_up, size: 16),
                  label: const Text('Volume +'),
                  onPressed: enabled ? () => onSendKeyEvent(24) : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.volume_down, size: 16),
                  label: const Text('Volume -'),
                  onPressed: enabled ? () => onSendKeyEvent(25) : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.power_settings_new, size: 16),
                  label: const Text('Écran On/Off'),
                  onPressed: enabled ? () => onSendKeyEvent(26) : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.home, size: 16),
                  label: const Text('Accueil'),
                  onPressed: enabled ? () => onSendKeyEvent(3) : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Retour'),
                  onPressed: enabled ? () => onSendKeyEvent(4) : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.screen_rotation, size: 16),
                  label: const Text('Rotation'),
                  onPressed: enabled ? () => onSendKeyEvent(176) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
