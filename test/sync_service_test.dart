import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:location_tracker/data/datasources/local/location_database.dart';
import 'package:location_tracker/data/datasources/remote/location_api_client.dart';
import 'package:location_tracker/data/models/location_record.dart';
import 'package:location_tracker/data/repositories/location_repository.dart';
import 'package:location_tracker/services/connectivity_service.dart';
import 'package:location_tracker/services/sync_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  late Directory tempDir;
  late LocationDatabase database;
  late MockLocationApiClient api;
  late LocationRepository repository;
  late _MockConnectivity connectivity;
  late SyncService syncService;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('location_tracker_test_');
    database = LocationDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${tempDir.path}/test.db',
    );
    api = MockLocationApiClient(latency: Duration.zero);
    repository = LocationRepository(database: database, apiClient: api);
    connectivity = _MockConnectivity();
    when(() => connectivity.isOnline).thenReturn(true);
    when(() => connectivity.onStatusChanged)
        .thenAnswer((_) => const Stream<bool>.empty());

    syncService = SyncService(
      repository: repository,
      connectivity: connectivity,
    );
  });

  tearDown(() async {
    await syncService.dispose();
    await database.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  LocationRecord sample(String id) {
    return LocationRecord(
      id: id,
      latitude: 28.61,
      longitude: 77.20,
      accuracy: 10,
      recordedAt: DateTime.utc(2026, 1, 1, 12),
    );
  }

  test('stores records locally while offline and syncs when online', () async {
    when(() => connectivity.isOnline).thenReturn(false);

    await repository.saveLocally(sample('a'));
    await repository.saveLocally(sample('b'));

    expect(await repository.pendingCount(), 2);
    expect(await repository.syncedCount(), 0);

    // Offline sync is a no-op.
    final offlineReport = await syncService.syncPending();
    expect(offlineReport.attempted, 0);
    expect(api.requestCount, 0);

    when(() => connectivity.isOnline).thenReturn(true);
    final report = await syncService.syncPending();

    expect(report.attempted, 2);
    expect(report.succeeded, 2);
    expect(report.failed, 0);
    expect(await repository.pendingCount(), 0);
    expect(await repository.syncedCount(), 2);
    expect(api.acceptedIds, {'a', 'b'});
  });

  test('does not re-upload already synced records (no duplicates)', () async {
    await repository.saveLocally(sample('same-id'));

    final first = await syncService.syncPending();
    expect(first.succeeded, 1);
    expect(api.requestCount, 1);

    final second = await syncService.syncPending();
    expect(second.attempted, 0);
    expect(api.requestCount, 1);
    expect(api.acceptedIds.length, 1);
  });

  test('retries failed uploads without duplicating successful ones', () async {
    await repository.saveLocally(sample('ok-1'));
    await repository.saveLocally(sample('fail-then-ok'));

    api.failNext(1);

    final firstPass = await syncService.syncPending();
    expect(firstPass.succeeded, 1);
    expect(firstPass.failed, 1);
    expect(await repository.pendingCount(), 1);
    expect(await repository.syncedCount(), 1);

    final secondPass = await syncService.syncPending();
    expect(secondPass.attempted, 1);
    expect(secondPass.succeeded, 1);
    expect(secondPass.failed, 0);
    expect(await repository.pendingCount(), 0);
    expect(api.acceptedIds, {'ok-1', 'fail-then-ok'});
  });

  test('server-side duplicate response still marks local record synced', () async {
    // Pretend the server already accepted this idempotency key (e.g. prior
    // upload timed out after the server committed).
    final seededApi = MockLocationApiClient(
      latency: Duration.zero,
      seedAcceptedIds: {'already-there'},
    );
    final seededRepo = LocationRepository(
      database: database,
      apiClient: seededApi,
    );
    final seededSync = SyncService(
      repository: seededRepo,
      connectivity: connectivity,
    );

    await seededRepo.saveLocally(sample('already-there'));
    final report = await seededSync.syncPending();

    expect(report.succeeded, 1);
    expect(report.duplicates, 1);
    expect(await seededRepo.pendingCount(), 0);
    expect(await seededRepo.syncedCount(), 1);

    await seededSync.dispose();
  });
}
