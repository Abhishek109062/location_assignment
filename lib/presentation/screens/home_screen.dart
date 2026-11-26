import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tracking_providers.dart';
import '../widgets/location_tile.dart';
import '../widgets/status_banner.dart';
import '../widgets/tracking_actions.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trackingControllerProvider);
    final controller = ref.read(trackingControllerProvider.notifier);
    final theme = Theme.of(context);
    final pendingCount = state.pendingCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Tracker'),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            onPressed: state.isSyncing ? null : controller.syncNow,
            icon: state.isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
          ),
        ],
      ),
      body: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const ClampingScrollPhysics(),
          children: [
            StatusBanner(state: state),
            const SizedBox(height: 16),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Controls', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use simulated GPS'),
                      subtitle: const Text(
                        'Simulated points still need location permission on '
                        'Android (required for the background service)',
                      ),
                      value: state.useSimulation,
                      onChanged: state.isTracking
                          ? null
                          : controller.setUseSimulation,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Force offline'),
                      subtitle: const Text(
                        'Simulate no internet — points queue locally',
                      ),
                      value: state.forceOffline,
                      onChanged: controller.setForceOffline,
                    ),
                    const SizedBox(height: 12),
                    TrackingActions(
                      isTracking: state.isTracking,
                      onStart: controller.startTracking,
                      onStop: controller.stopTracking,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Locations', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              pendingCount > 0
                  ? '$pendingCount waiting to sync · '
                      '${state.records.length} of ${state.totalCount} shown'
                  : state.totalCount == 0
                      ? 'No locations yet'
                      : '${state.records.length} of ${state.totalCount} shown'
                          ' · all synced',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (state.records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No locations yet. Start tracking to begin.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              ...state.records.map((r) => LocationTile(record: r)),
              if (state.hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 16),
                  child: Center(
                    child: TextButton(
                      onPressed: controller.loadMore,
                      child: Text(
                        'Show more (${state.totalCount - state.records.length} left)',
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
