import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/location_record.dart';

class LocationTile extends StatelessWidget {
  const LocationTile({super.key, required this.record});

  final LocationRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat('dd MMM yyyy · HH:mm:ss')
        .format(record.recordedAt.toLocal());
    final (icon, color, label) = switch (record.syncStatus) {
      SyncStatus.pending => (Icons.schedule, Colors.orange, 'Pending'),
      SyncStatus.syncing => (Icons.sync, Colors.blue, 'Syncing'),
      SyncStatus.synced => (Icons.check_circle_outline, Colors.green, 'Synced'),
      SyncStatus.failed => (
          Icons.error_outline,
          Colors.red,
          'Failed (retry ${record.retryCount})',
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Latitude',
              value: record.latitude.toStringAsFixed(6),
            ),
            _InfoRow(
              label: 'Longitude',
              value: record.longitude.toStringAsFixed(6),
            ),
            _InfoRow(label: 'Time', value: time),
            _InfoRow(
              label: 'Accuracy',
              value: '±${record.accuracy.toStringAsFixed(1)} m',
            ),
            const SizedBox(height: 4),
            Text(
              'ID',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              record.id,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
