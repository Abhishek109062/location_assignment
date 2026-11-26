import 'package:flutter_test/flutter_test.dart';
import 'package:location_tracker/data/models/location_record.dart';

void main() {
  test('round-trips through map serialization', () {
    final original = LocationRecord(
      id: 'abc-123',
      latitude: 12.34,
      longitude: 56.78,
      accuracy: 4.5,
      recordedAt: DateTime.utc(2026, 3, 1, 10, 30),
      syncStatus: SyncStatus.pending,
      retryCount: 2,
    );

    final restored = LocationRecord.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.latitude, original.latitude);
    expect(restored.longitude, original.longitude);
    expect(restored.accuracy, original.accuracy);
    expect(restored.recordedAt, original.recordedAt);
    expect(restored.syncStatus, SyncStatus.pending);
    expect(restored.retryCount, 2);
  });

  test('API payload includes idempotency id', () {
    final record = LocationRecord(
      id: 'idem-1',
      latitude: 1,
      longitude: 2,
      accuracy: 3,
      recordedAt: DateTime.utc(2026, 1, 1),
    );

    expect(record.toApiPayload()['id'], 'idem-1');
  });
}
