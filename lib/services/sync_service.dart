import 'dart:async';

import '../data/datasources/remote/location_api_client.dart';
import '../data/repositories/location_repository.dart';
import 'connectivity_service.dart';

/// Outcome summary for one sync pass.
class SyncReport {
  const SyncReport({
    required this.attempted,
    required this.succeeded,
    required this.duplicates,
    required this.failed,
  });

  final int attempted;
  final int succeeded;
  final int duplicates;
  final int failed;

  bool get hasWork => attempted > 0;
}

/// Drains the offline queue when connectivity returns.
///
/// Guarantees:
/// - Only one sync pass runs at a time (mutex via [_syncing]).
/// - Each record has a stable client UUID; successful/duplicate uploads are
///   marked synced locally so they are never re-uploaded.
/// - Transient failures bump [LocationRecord.retryCount] and leave the row
///   eligible for the next pass.
class SyncService {
  SyncService({
    required LocationRepository repository,
    required ConnectivityService connectivity,
  })  : _repository = repository,
        _connectivity = connectivity;

  final LocationRepository _repository;
  final ConnectivityService _connectivity;

  final _reportController = StreamController<SyncReport>.broadcast();
  StreamSubscription<bool>? _connectivitySub;
  bool _syncing = false;
  bool _started = false;

  Stream<SyncReport> get onSyncReport => _reportController.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _repository.prepareForSync();

    _connectivitySub = _connectivity.onStatusChanged.listen((online) {
      if (online) {
        unawaited(syncPending());
      }
    });

    if (_connectivity.isOnline) {
      await syncPending();
    }
  }

  /// Manual trigger (e.g. pull-to-refresh / "Sync now" button).
  Future<SyncReport> syncPending() async {
    if (_syncing) {
      return const SyncReport(
        attempted: 0,
        succeeded: 0,
        duplicates: 0,
        failed: 0,
      );
    }
    if (!_connectivity.isOnline) {
      return const SyncReport(
        attempted: 0,
        succeeded: 0,
        duplicates: 0,
        failed: 0,
      );
    }

    _syncing = true;
    var succeeded = 0;
    var duplicates = 0;
    var failed = 0;

    try {
      final pending = await _repository.pendingRecords();
      for (final record in pending) {
        // Bail if we went offline mid-batch.
        if (!_connectivity.isOnline) break;

        final result = await _repository.syncOne(record);
        switch (result) {
          case UploadSuccess(:final duplicate):
            succeeded++;
            if (duplicate) duplicates++;
          case UploadFailure():
            failed++;
        }
      }

      final report = SyncReport(
        attempted: pending.length,
        succeeded: succeeded,
        duplicates: duplicates,
        failed: failed,
      );
      if (!_reportController.isClosed) {
        _reportController.add(report);
      }
      return report;
    } finally {
      _syncing = false;
    }
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    await _reportController.close();
  }
}
