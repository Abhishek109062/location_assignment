import '../../models/location_record.dart';

/// Result of attempting to upload one location record.
sealed class UploadResult {
  const UploadResult();
}

class UploadSuccess extends UploadResult {
  const UploadSuccess({required this.duplicate});

  /// True when the server already had this idempotency key.
  final bool duplicate;
}

class UploadFailure extends UploadResult {
  const UploadFailure(this.message);

  final String message;
}

/// Contract for the remote location API.
abstract class LocationApiClient {
  Future<UploadResult> upload(LocationRecord record);
}

/// In-memory mock REST API that mimics `POST /locations`.
///
/// Stores accepted IDs so retries of the same payload return success with
/// [UploadSuccess.duplicate] = true — the key to preventing duplicate uploads.
class MockLocationApiClient implements LocationApiClient {
  MockLocationApiClient({
    this.latency = const Duration(milliseconds: 120),
    Set<String>? seedAcceptedIds,
  }) : _acceptedIds = {...?seedAcceptedIds};

  /// Artificial delay to feel like a network round-trip.
  final Duration latency;

  final Set<String> _acceptedIds;
  int _requestCount = 0;
  int _forcedFailuresRemaining = 0;

  int get requestCount => _requestCount;
  Set<String> get acceptedIds => Set.unmodifiable(_acceptedIds);

  /// Force the next [count] requests to fail (useful in tests).
  void failNext(int count) => _forcedFailuresRemaining = count;

  @override
  Future<UploadResult> upload(LocationRecord record) async {
    _requestCount++;
    await Future<void>.delayed(latency);

    if (_forcedFailuresRemaining > 0) {
      _forcedFailuresRemaining--;
      return const UploadFailure('Simulated transient network error');
    }

    final alreadySeen = _acceptedIds.contains(record.id);
    _acceptedIds.add(record.id);
    return UploadSuccess(duplicate: alreadySeen);
  }
}
