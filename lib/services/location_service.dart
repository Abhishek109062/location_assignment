import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../data/models/location_record.dart';

/// Emits GPS samples either from the platform location APIs or a simulator.
class LocationService {
  LocationService({Uuid? uuid, Random? random})
      : _uuid = uuid ?? const Uuid(),
        _random = random ?? Random();

  final Uuid _uuid;
  final Random _random;

  StreamSubscription<Position>? _realSub;
  Timer? _simTimer;
  bool _useSimulation = true;

  /// Rough Delhi coordinates as a default simulation origin.
  double _simLat = 28.6139;
  double _simLng = 77.2090;

  void setUseSimulation(bool value) {
    _useSimulation = value;
  }

  /// Ensures location services + permissions are usable for foreground tracking.
  Future<String?> ensurePermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location services are disabled. Enable GPS and try again.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Location permission denied.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return 'Location permission permanently denied. Open Settings to enable it.';
    }

    return null;
  }

  /// Starts a stream of [LocationRecord]s.
  ///
  /// Real mode uses Geolocator distance/time filters.
  /// Simulation mode walks a small random path every [interval].
  Stream<LocationRecord> startTracking({
    Duration interval = const Duration(seconds: 3),
  }) {
    late final StreamController<LocationRecord> controller;
    controller = StreamController<LocationRecord>(
      onListen: () async {
        if (_useSimulation) {
          _startSimulation(controller, interval);
        } else {
          final error = await ensurePermissions();
          if (error != null) {
            controller.addError(Exception(error));
            await controller.close();
            return;
          }
          await _startReal(controller, interval);
        }
      },
      onCancel: stopTracking,
    );
    return controller.stream;
  }

  Future<void> _startReal(
    StreamController<LocationRecord> controller,
    Duration interval,
  ) async {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _realSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        if (!controller.isClosed) {
          controller.add(_fromPosition(position));
        }
      },
      onError: controller.addError,
    );

    // Also emit an immediate fix so the UI isn't empty for several seconds.
    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      if (!controller.isClosed) {
        controller.add(_fromPosition(current));
      }
    } catch (_) {
      // Stream will continue delivering updates.
    }

    // Keep interval referenced for API symmetry with simulation.
    assert(interval > Duration.zero);
  }

  void _startSimulation(
    StreamController<LocationRecord> controller,
    Duration interval,
  ) {
    void emit() {
      // ~5–25 meter jitter per tick.
      _simLat += (_random.nextDouble() - 0.5) * 0.0003;
      _simLng += (_random.nextDouble() - 0.5) * 0.0003;
      if (!controller.isClosed) {
        final record = LocationRecord(
          id: _uuid.v4(),
          latitude: _simLat,
          longitude: _simLng,
          accuracy: 5 + _random.nextDouble() * 15,
          recordedAt: DateTime.now().toUtc(),
        );
        // ignore: avoid_print
        print(
          '[LocationTracker][UI] sim point '
          '(${record.latitude.toStringAsFixed(5)}, '
          '${record.longitude.toStringAsFixed(5)})',
        );
        controller.add(record);
      }
    }

    emit();
    _simTimer = Timer.periodic(interval, (_) => emit());
  }

  LocationRecord _fromPosition(Position position) {
    return LocationRecord(
      id: _uuid.v4(),
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      recordedAt: position.timestamp.toUtc(),
    );
  }

  Future<void> stopTracking() async {
    await _realSub?.cancel();
    _realSub = null;
    _simTimer?.cancel();
    _simTimer = null;
  }
}
