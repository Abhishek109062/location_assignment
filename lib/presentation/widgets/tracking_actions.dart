import 'package:flutter/material.dart';

/// Start/Stop actions that stack on narrow widths and sit in a row on wider ones.
class TrackingActions extends StatelessWidget {
  const TrackingActions({
    super.key,
    required this.isTracking,
    required this.onStart,
    required this.onStop,
  });

  final bool isTracking;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        final startLabel = narrow ? 'Start' : 'Start tracking';

        final startButton = FilledButton.icon(
          onPressed: isTracking ? null : onStart,
          icon: const Icon(Icons.play_arrow),
          label: Text(startLabel, overflow: TextOverflow.ellipsis),
        );
        final stopButton = OutlinedButton.icon(
          onPressed: isTracking ? onStop : null,
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 48, child: startButton),
              const SizedBox(height: 10),
              SizedBox(height: 48, child: stopButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: SizedBox(height: 48, child: startButton)),
            const SizedBox(width: 12),
            Expanded(child: SizedBox(height: 48, child: stopButton)),
          ],
        );
      },
    );
  }
}
