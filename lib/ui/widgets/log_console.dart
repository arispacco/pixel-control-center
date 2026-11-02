import 'package:flutter/material.dart';

/// Renders a scrollable real-time log terminal displaying process output from
/// ADB commands and scrcpy mirroring sessions.
class LogConsole extends StatelessWidget {
  /// History of log lines received from scrcpy or discovery services.
  final List<String> logs;

  /// Callback to clear the active log history.
  final VoidCallback onClear;

  /// Creates a [LogConsole] widget.
  const LogConsole({
    super.key,
    required this.logs,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.terminal, size: 18, color: Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      'Journal d\'activité (Logs)',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: logs.isEmpty ? null : onClear,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Effacer'),
                ),
              ],
            ),
            const Divider(),
            Container(
              height: 180,
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
              ),
              child: logs.isEmpty
                  ? const Center(
                      child: Text(
                        'En attente d\'activité...',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        // Display newest entries first.
                        final logIndex = logs.length - 1 - index;
                        final line = logs[logIndex];
                        Color color = Colors.white70;

                        if (line.contains('[ERROR]')) {
                          color = Colors.redAccent;
                        } else if (line.contains('[WARN]')) {
                          color = Colors.orangeAccent;
                        } else if (line.contains('[RUN]')) {
                          color = Colors.lightBlueAccent;
                        } else if (line.contains('[INFO]')) {
                          color = Colors.greenAccent;
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1.0),
                          child: Text(
                            line,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: color,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
