/// Sync lifecycle for a locally stored GPS sample.
enum SyncStatus {
  pending,
  syncing,
  synced,
  failed,
}

/// A single GPS fix stored locally and optionally uploaded to the API.
///
/// [id] is a client-generated UUID. The backend treats it as an idempotency
/// key so the same record is never applied twice if a retry succeeds after
/// a network timeout.
class LocationRecord {
  const LocationRecord({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.recordedAt,
    this.syncStatus = SyncStatus.pending,
    this.syncedAt,
    this.retryCount = 0,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime recordedAt;
  final SyncStatus syncStatus;
  final DateTime? syncedAt;
  final int retryCount;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'recorded_at': recordedAt.toIso8601String(),
      'sync_status': syncStatus.name,
      'synced_at': syncedAt?.toIso8601String(),
      'retry_count': retryCount,
    };
  }

  factory LocationRecord.fromMap(Map<String, dynamic> map) {
    return LocationRecord(
      id: map['id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: (map['accuracy'] as num).toDouble(),
      recordedAt: DateTime.parse(map['recorded_at'] as String),
      syncStatus: SyncStatus.values.byName(map['sync_status'] as String),
      syncedAt: map['synced_at'] != null
          ? DateTime.parse(map['synced_at'] as String)
          : null,
      retryCount: map['retry_count'] as int? ?? 0,
    );
  }

  /// Payload sent to the mock REST API.
  Map<String, dynamic> toApiPayload() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }

  @override
  String toString() =>
      'LocationRecord(id: $id, lat: $latitude, lng: $longitude, status: ${syncStatus.name})';
}
