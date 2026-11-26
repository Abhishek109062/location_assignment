import '../datasources/local/location_database.dart';
import '../datasources/remote/location_api_client.dart';
import '../models/location_record.dart';

/// Single entry point for location persistence and upload.
///
/// UI and services talk only to this repository so storage/API details stay
/// swappable (important for testing and for swapping the mock API later).
class LocationRepository {
  LocationRepository({
    required LocationDatabase database,
    required LocationApiClient apiClient,
  })  : _db = database,
        _api = apiClient;

  final LocationDatabase _db;
  final LocationApiClient _api;

  Future<void> saveLocally(LocationRecord record) => _db.insert(record);

  Future<List<LocationRecord>> watchRecent({int limit = 10}) =>
      _db.getAll(limit: limit);

  Future<List<LocationRecord>> pendingRecords() => _db.getPending();

  Future<int> totalCount() => _db.countAll();

  Future<int> pendingCount() async {
    final pending = await _db.countByStatus(SyncStatus.pending);
    final failed = await _db.countByStatus(SyncStatus.failed);
    final syncing = await _db.countByStatus(SyncStatus.syncing);
    return pending + failed + syncing;
  }

  Future<int> syncedCount() => _db.countByStatus(SyncStatus.synced);

  Future<void> prepareForSync() => _db.resetStuckSyncing();

  /// Uploads one record and updates local sync state.
  ///
  /// On success (including server-side duplicates) the row is marked synced
  /// so it will never be uploaded again.
  Future<UploadResult> syncOne(LocationRecord record) async {
    await _db.markSyncing(record.id);
    final result = await _api.upload(record);

    switch (result) {
      case UploadSuccess():
        await _db.markSynced(record.id);
      case UploadFailure():
        await _db.markFailed(record.id);
    }
    return result;
  }
}
