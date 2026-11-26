import 'package:flutter/material.dart';

import '../providers/tracking_providers.dart';

/// Fixed-height connectivity / status banner so Start/Stop never jumps layout.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.state});

  final TrackingUiState state;

  @override
  Widget build(BuildContext context) {
    final online = state.isOnline;
    final color = online ? Colors.green.shade700 : Colors.orange.shade800;
    final bg = online ? Colors.green.shade50 : Colors.orange.shade50;
    final detail = state.errorMessage ?? state.statusMessage ?? '';
    final detailColor = state.errorMessage != null
        ? Colors.red.shade700
        : Theme.of(context).colorScheme.onSurface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Icon(
                  online ? Icons.wifi : Icons.wifi_off,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  online ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                AnimatedOpacity(
                  opacity: state.isTracking ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const IgnorePointer(
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      labelPadding: EdgeInsets.only(right: 8),
                      avatar: Icon(Icons.gps_fixed, size: 16),
                      label: Text('Tracking'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                detail.isEmpty ? 'Ready' : detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: detail.isEmpty
                      ? Theme.of(context).hintColor
                      : detailColor,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
