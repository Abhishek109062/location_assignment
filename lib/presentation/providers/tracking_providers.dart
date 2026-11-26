import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/location_database.dart';
import '../../data/datasources/remote/location_api_client.dart';
import '../../data/models/location_record.dart';
import '../../data/repositories/location_repository.dart';
import '../../services/background_tracking_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/location_service.dart';
import '../../services/sync_service.dart';
import '../../services/tracking_session_store.dart';

// ---------------------------------------------------------------------------
// Infrastructure (singletons for app lifetime)
// ---------------------------------------------------------------------------

final locationDatabaseProvider = Provider<LocationDatabase>((ref) {
  final db = LocationDatabase();
  ref.onDispose(db.close);
  return db;
});

final locationApiClientProvider = Provider<LocationApiClient>((ref) {
  return MockLocationApiClient();
});

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(
    database: ref.watch(locationDatabaseProvider),
    apiClient: ref.watch(locationApiClientProvider),
  );
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  ref.onDispose(service.dispose);
  return service;
});

final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(service.stopTracking);
  return service;
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    repository: ref.watch(locationRepositoryProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final trackingSessionStoreProvider = Provider<TrackingSessionStore>((ref) {
  return TrackingSessionStore();
});

final backgroundTrackingFacadeProvider =
    Provider<BackgroundTrackingFacade>((ref) {
  return BackgroundTrackingFacade();
});

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

class TrackingUiState {
  const TrackingUiState({
    this.isTracking = false,
    this.useSimulation = true,
    this.isOnline = true,
    this.forceOffline = false,
    this.isSyncing = false,
    this.records = const [],
    this.visibleLimit = TrackingController.pageSize,
    this.totalCount = 0,
    this.pendingCount = 0,
    this.statusMessage,
    this.errorMessage,
  });

  final bool isTracking;
  final bool useSimulation;
  final bool isOnline;
  final bool forceOffline;
  final bool isSyncing;
  final List<LocationRecord> records;
  /// How many newest rows to load from SQLite.
  final int visibleLimit;
  final int totalCount;
  final int pendingCount;
  final String? statusMessage;
  final String? errorMessage;

  bool get hasMore => records.length < totalCount;

  TrackingUiState copyWith({
    bool? isTracking,
    bool? useSimulation,
    bool? isOnline,
    bool? forceOffline,
    bool? isSyncing,
    List<LocationRecord>? records,
    int? visibleLimit,
    int? totalCount,
    int? pendingCount,
    String? statusMessage,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TrackingUiState(
      isTracking: isTracking ?? this.isTracking,
      useSimulation: useSimulation ?? this.useSimulation,
      isOnline: isOnline ?? this.isOnline,
      forceOffline: forceOffline ?? this.forceOffline,
      isSyncing: isSyncing ?? this.isSyncing,
      records: records ?? this.records,
      visibleLimit: visibleLimit ?? this.visibleLimit,
      totalCount: totalCount ?? this.totalCount,
      pendingCount: pendingCount ?? this.pendingCount,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class TrackingController extends Notifier<TrackingUiState> {
  static const int pageSize = 10;

  StreamSubscription<LocationRecord>? _trackingSub;
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<SyncReport>? _syncSub;
  StreamSubscription<Map<String, dynamic>?>? _bgLocationSub;
  StreamSubscription<Map<String, dynamic>?>? _bgSyncSub;
  StreamSubscription<Map<String, dynamic>?>? _bgErrorSub;
  Timer? _refreshTimer;
  AppLifecycleListener? _lifecycle;
  bool _lifecycleBusy = false;
  bool _handedOffToBackground = false;

  @override
  TrackingUiState build() {
    // Only pause/resume — onHide+onPause both fire on Android and caused
    // double handoff (UI + background collectors running together).
    _lifecycle = AppLifecycleListener(
      onPause: _onAppPaused,
      onResume: _onAppResumed,
    );

    ref.onDispose(() {
      _trackingSub?.cancel();
      _connectivitySub?.cancel();
      _syncSub?.cancel();
      _bgLocationSub?.cancel();
      _bgSyncSub?.cancel();
      _bgErrorSub?.cancel();
      _refreshTimer?.cancel();
      _lifecycle?.dispose();
    });

    Future.microtask(_bootstrap);
    return const TrackingUiState();
  }

  Future<void> _bootstrap() async {
    final connectivity = ref.read(connectivityServiceProvider);
    final sync = ref.read(syncServiceProvider);
    final session = ref.read(trackingSessionStoreProvider);

    // Restore Force offline BEFORE sync starts — otherwise a relaunch while
    // Force offline was on would immediately upload and clear the queue.
    final useSim = await session.useSimulation();
    final forceOffline = await session.forceOffline();
    connectivity.setForceOffline(forceOffline);

    await connectivity.start();

    state = state.copyWith(
      isOnline: connectivity.isOnline,
      forceOffline: connectivity.forceOffline,
      useSimulation: useSim,
    );

    await sync.start();

    _connectivitySub = connectivity.onStatusChanged.listen((online) async {
      state = state.copyWith(
        isOnline: online,
        forceOffline: connectivity.forceOffline,
        statusMessage: online
            ? 'Back online — syncing…'
            : 'Offline — queuing locally',
      );
      await _refreshRecords();
    });

    _syncSub = sync.onSyncReport.listen((report) async {
      if (!report.hasWork) return;
      state = state.copyWith(
        isSyncing: false,
        statusMessage:
            'Synced ${report.succeeded} (${report.duplicates} duplicates skipped), '
            '${report.failed} failed',
      );
      await _refreshRecords();
    });

    if (supportsBackgroundTracking) {
      final facade = ref.read(backgroundTrackingFacadeProvider);
      final resumed = await facade.resumeIfNeeded();
      if (resumed) {
        _listenToBackgroundEvents();
        _startRefreshTimer();
        // App is visible again after kill — take collection back in the UI.
        await session.setUiCollecting(true);
        await facade.notifyUiResumed();
        await _startForegroundCollector();
        state = state.copyWith(
          isTracking: true,
          statusMessage: 'Resumed tracking after relaunch',
        );
      }
    }

    await _refreshRecords();
  }

  void _onAppPaused() {
    if (!state.isTracking) return;
    unawaited(_handOffToBackground());
  }

  void _onAppResumed() {
    if (!state.isTracking) return;
    unawaited(_takeOverFromBackground());
  }

  Future<void> _handOffToBackground() async {
    if (!state.isTracking || _handedOffToBackground || _lifecycleBusy) return;
    _lifecycleBusy = true;
    try {
      // ignore: avoid_print
      print('[LocationTracker][UI] app paused — handing off to background');

      // Stop UI collector fully BEFORE enabling background collection.
      await _trackingSub?.cancel();
      _trackingSub = null;
      await ref.read(locationServiceProvider).stopTracking();

      await ref.read(trackingSessionStoreProvider).setUiCollecting(false);
      _handedOffToBackground = true;

      if (supportsBackgroundTracking) {
        final facade = ref.read(backgroundTrackingFacadeProvider);
        if (!await facade.isRunning()) {
          await facade.start(
            useSimulation: state.useSimulation,
            forceOffline: state.forceOffline,
          );
          _listenToBackgroundEvents();
        }
        await facade.notifyUiPaused();
      }

      state = state.copyWith(
        statusMessage: 'Background collecting while minimized',
      );
    } finally {
      _lifecycleBusy = false;
    }
  }

  Future<void> _takeOverFromBackground() async {
    if (!state.isTracking || !_handedOffToBackground || _lifecycleBusy) return;
    _lifecycleBusy = true;
    try {
      // Stop background collectors before starting UI again.
      if (supportsBackgroundTracking) {
        await ref.read(backgroundTrackingFacadeProvider).notifyUiResumed();
      }
      await ref.read(trackingSessionStoreProvider).setUiCollecting(true);
      _handedOffToBackground = false;

      await _startForegroundCollector();
      await _refreshRecords();
      state = state.copyWith(statusMessage: 'Tracking');
    } finally {
      _lifecycleBusy = false;
    }
  }

  void _listenToBackgroundEvents() {
    final facade = ref.read(backgroundTrackingFacadeProvider);
    _bgLocationSub?.cancel();
    _bgSyncSub?.cancel();
    _bgErrorSub?.cancel();

    _bgLocationSub = facade.onLocationSaved().listen((_) {
      unawaited(_refreshRecords());
    });
    _bgSyncSub = facade.onSyncDone().listen((_) {
      unawaited(_refreshRecords());
    });
    _bgErrorSub = facade.onError().listen((event) {
      state = state.copyWith(
        errorMessage: event?['message']?.toString() ?? 'Background error',
      );
    });
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshRecords(),
    );
  }

  Future<void> _refreshRecords() async {
    try {
      final repo = ref.read(locationRepositoryProvider);
      // Page of newest rows only — Show more raises [visibleLimit].
      final page = await repo.watchRecent(limit: state.visibleLimit);
      final total = await repo.totalCount();
      final pending = await repo.pendingCount();
      state = state.copyWith(
        records: page,
        totalCount: total,
        pendingCount: pending,
      );
    } catch (e) {
      // Transient DB reopen races during start/stop should not crash the UI.
      // ignore: avoid_print
      print('[LocationTracker][UI] refresh skipped: $e');
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore) return;
    state = state.copyWith(visibleLimit: state.visibleLimit + pageSize);
    await _refreshRecords();
  }

  /// Original foreground collection path — drives live "Recent locations" updates.
  Future<void> _startForegroundCollector() async {
    final location = ref.read(locationServiceProvider);
    location.setUseSimulation(state.useSimulation);

    await _trackingSub?.cancel();
    await location.stopTracking();

    _trackingSub = location.startTracking().listen(
      (record) async {
        try {
          final repo = ref.read(locationRepositoryProvider);
          await repo.saveLocally(record);

          if (ref.read(connectivityServiceProvider).isOnline) {
            unawaited(ref.read(syncServiceProvider).syncPending());
          }

          await _refreshRecords();
        } catch (e) {
          // ignore: avoid_print
          print('[LocationTracker][UI] save skipped: $e');
        }
      },
      onError: (Object error) {
        state = state.copyWith(errorMessage: error.toString());
      },
    );
  }

  Future<void> startTracking() async {
    if (state.isTracking) return;

    state = state.copyWith(clearError: true);

    if (supportsBackgroundTracking) {
      // Requests notification + location (required for location FGS on Android).
      final permissionError = await ensureBackgroundPermissions(
        useSimulation: state.useSimulation,
      );
      if (permissionError != null) {
        state = state.copyWith(errorMessage: permissionError);
        return;
      }

      final facade = ref.read(backgroundTrackingFacadeProvider);
      await facade.start(
        useSimulation: state.useSimulation,
        forceOffline: state.forceOffline,
      );
      _listenToBackgroundEvents();
    } else {
      if (!state.useSimulation) {
        final error =
            await ref.read(locationServiceProvider).ensurePermissions();
        if (error != null) {
          state = state.copyWith(errorMessage: error);
          return;
        }
      }
      await ref.read(trackingSessionStoreProvider).setTrackingActive(true);
      await ref.read(trackingSessionStoreProvider).setUiCollecting(true);
    }

    // Original path: UI isolate writes points so the list updates immediately.
    await ref.read(trackingSessionStoreProvider).setUiCollecting(true);
    _handedOffToBackground = false;
    await _startForegroundCollector();
    _startRefreshTimer();

    state = state.copyWith(
      isTracking: true,
      statusMessage: 'Tracking',
    );
  }

  Future<void> stopTracking() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _handedOffToBackground = false;
    await _trackingSub?.cancel();
    _trackingSub = null;
    await ref.read(locationServiceProvider).stopTracking();
    await ref.read(trackingSessionStoreProvider).setUiCollecting(false);

    if (supportsBackgroundTracking) {
      await ref.read(backgroundTrackingFacadeProvider).stop();
    } else {
      await ref.read(trackingSessionStoreProvider).setTrackingActive(false);
    }

    state = state.copyWith(
      isTracking: false,
      statusMessage: 'Tracking stopped',
    );
    await _refreshRecords();
  }

  void setUseSimulation(bool value) {
    if (state.isTracking) return;
    ref.read(locationServiceProvider).setUseSimulation(value);
    unawaited(ref.read(trackingSessionStoreProvider).setUseSimulation(value));
    state = state.copyWith(useSimulation: value);
  }

  void setForceOffline(bool value) {
    ref.read(connectivityServiceProvider).setForceOffline(value);
    unawaited(ref.read(trackingSessionStoreProvider).setForceOffline(value));
    if (supportsBackgroundTracking) {
      unawaited(
        ref.read(backgroundTrackingFacadeProvider).updateForceOffline(value),
      );
    }
    state = state.copyWith(
      forceOffline: value,
      isOnline: ref.read(connectivityServiceProvider).isOnline,
      statusMessage: value
          ? 'Forced offline — records will queue'
          : 'Forced offline disabled',
    );
  }

  Future<void> syncNow() async {
    state = state.copyWith(isSyncing: true, statusMessage: 'Syncing…');
    final report = await ref.read(syncServiceProvider).syncPending();
    state = state.copyWith(
      isSyncing: false,
      statusMessage: report.hasWork
          ? 'Synced ${report.succeeded}, failed ${report.failed}'
          : (ref.read(connectivityServiceProvider).isOnline
              ? 'Nothing pending to sync'
              : 'Cannot sync while offline'),
    );
    await _refreshRecords();
  }

}

final trackingControllerProvider =
    NotifierProvider<TrackingController, TrackingUiState>(
  TrackingController.new,
);
