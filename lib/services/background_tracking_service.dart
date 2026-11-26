import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../data/datasources/local/location_database.dart';
import '../data/datasources/remote/location_api_client.dart';
import '../data/models/location_record.dart';
import '../data/repositories/location_repository.dart';
import 'tracking_session_store.dart';

const _notificationChannelId = 'location_tracking';
const _notificationId = 7331;

void _bgLog(String message) {
  developer.log(message, name: 'LocationTracker');
  // ignore: avoid_print — intentional so `flutter run` shows background activity
  print('[LocationTracker][BG] $message');
}

/// Whether this platform can host the assignment background service.
bool get supportsBackgroundTracking =>
    !Platform.isWindows &&
    !Platform.isLinux &&
    !Platform.isMacOS &&
    (Platform.isAndroid || Platform.isIOS);

Future<void> initializeBackgroundTracking() async {
  if (!supportsBackgroundTracking) return;

  final notifications = FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    final androidPlugin = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _notificationChannelId,
        'Location Tracking',
        description:
            'Shown while location tracking runs in the background',
        importance: Importance.low,
      ),
    );
  }

  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: backgroundOnStart,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: _notificationChannelId,
      initialNotificationTitle: 'Location Tracker',
      initialNotificationContent: 'Tracking location…',
      foregroundServiceNotificationId: _notificationId,
      foregroundServiceTypes: const [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: backgroundOnStart,
      onBackground: onIosBackground,
    ),
  );
}

Future<String?> ensureBackgroundPermissions({
  required bool useSimulation,
}) async {
  if (Platform.isAndroid) {
    final androidPlugin = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final allowed =
        await androidPlugin?.requestNotificationsPermission() ?? true;
    if (allowed == false) {
      return 'Notification permission is required for background tracking on Android.';
    }

    // Android 14+ (and targetSdk 36): a foregroundServiceType="location"
    // service CANNOT start unless fine/coarse location is already granted —
    // even if we only emit simulated coordinates.
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return 'Location permission is required to start the background tracking service.';
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location permission permanently denied. Open Settings to enable it.';
    }
  }

  if (!useSimulation) {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location services are disabled. Enable GPS and try again.';
    }

    if (!Platform.isAndroid) {
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
    }
  }

  return null;
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void backgroundOnStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    await service.setForegroundNotificationInfo(
      title: 'Location Tracker',
      content: 'Tracking in background…',
    );
  }

  final session = TrackingSessionStore();
  // Critical: reload prefs so we see the UI isolate's writes.
  final active = await session.isTrackingActive();
  if (!active) {
    await service.stopSelf();
    return;
  }

  final database = LocationDatabase();
  final api = MockLocationApiClient(latency: const Duration(milliseconds: 80));
  final repository = LocationRepository(database: database, apiClient: api);
  await repository.prepareForSync();

  final uuid = const Uuid();
  final random = Random();
  var simLat = 28.6139;
  var simLng = 77.2090;

  StreamSubscription<Position>? positionSub;
  Timer? simTimer;
  Timer? syncTimer;
  var collecting = false;

  Future<void> persist(LocationRecord record) async {
    await repository.saveLocally(record);
    _bgLog(
      'saved ${record.id.substring(0, 8)}… '
      '(${record.latitude.toStringAsFixed(5)}, '
      '${record.longitude.toStringAsFixed(5)})',
    );
    service.invoke('location_saved', {
      'id': record.id,
      'latitude': record.latitude,
      'longitude': record.longitude,
    });
  }

  Future<void> syncPending() async {
    if (await session.forceOffline()) return;
    final pending = await repository.pendingRecords();
    for (final item in pending) {
      if (await session.forceOffline()) break;
      await repository.syncOne(item);
    }
    service.invoke('sync_done');
  }

  Future<void> stopCollectors() async {
    await positionSub?.cancel();
    positionSub = null;
    simTimer?.cancel();
    simTimer = null;
    collecting = false;
  }

  Future<void> startCollectors() async {
    // UI isolate owns collection while the app is visible — avoid duplicates.
    if (await session.isUiCollecting()) {
      _bgLog('UI is collecting — background collectors on standby');
      await stopCollectors();
      return;
    }

    if (collecting) {
      _bgLog('collectors already running');
      return;
    }

    collecting = true;
    final useSim = await session.useSimulation();
    _bgLog(
      useSim
          ? 'starting BACKGROUND simulated GPS collector'
          : 'starting BACKGROUND device GPS collector',
    );

    if (useSim) {
      Future<void> emitSim() async {
        if (await session.isUiCollecting()) return;
        simLat += (random.nextDouble() - 0.5) * 0.0003;
        simLng += (random.nextDouble() - 0.5) * 0.0003;
        await persist(
          LocationRecord(
            id: uuid.v4(),
            latitude: simLat,
            longitude: simLng,
            accuracy: 5 + random.nextDouble() * 15,
            recordedAt: DateTime.now().toUtc(),
          ),
        );
        await syncPending();
      }

      await emitSim();
      simTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        unawaited(emitSim());
      });
    } else {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        service.invoke('tracking_error', {
          'message': 'Location permission missing in background',
        });
        collecting = false;
        return;
      }

      late final LocationSettings settings;
      if (Platform.isAndroid) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 3),
        );
      } else if (Platform.isIOS) {
        settings = AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          activityType: ActivityType.otherNavigation,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      } else {
        settings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        );
      }

      positionSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen((position) {
        unawaited(() async {
          if (await session.isUiCollecting()) return;
          await persist(
            LocationRecord(
              id: uuid.v4(),
              latitude: position.latitude,
              longitude: position.longitude,
              accuracy: position.accuracy,
              recordedAt: position.timestamp.toUtc(),
            ),
          );
          await syncPending();
        }());
      });
    }

    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Location Tracker',
        content: 'Background collection active',
      );
    }
  }

  service.on('stopService').listen((event) async {
    final keepSession = event?['keepSession'] == true;
    if (!keepSession) {
      await session.setTrackingActive(false);
    }
    await stopCollectors();
    syncTimer?.cancel();
    // Do NOT close SQLite here — sqflite close is process-wide and would
    // break the UI isolate mid insert/query (database_closed).
    await service.stopSelf();
  });

  service.on('update_force_offline').listen((event) async {
    await session.setForceOffline(event?['value'] == true);
  });

  service.on('ui_paused').listen((event) async {
    _bgLog('UI paused/minimized — taking over collection');
    await session.setUiCollecting(false);
    // Ensure a clean single collector (idempotent).
    await stopCollectors();
    await startCollectors();
  });

  service.on('ui_resumed').listen((event) async {
    _bgLog('UI resumed — stopping background collectors (UI owns GPS now)');
    await session.setUiCollecting(true);
    await stopCollectors();
    await syncPending();
  });

  syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
    unawaited(syncPending());
  });

  // If UI is not collecting (killed / already backgrounded), start now.
  if (!await session.isUiCollecting()) {
    await startCollectors();
  } else if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: 'Location Tracker',
      content: 'Ready — UI collecting, background standby',
    );
  }
}

class BackgroundTrackingFacade {
  final _service = FlutterBackgroundService();
  final _session = TrackingSessionStore();

  Future<bool> isRunning() => _service.isRunning();

  Stream<Map<String, dynamic>?> onLocationSaved() =>
      _service.on('location_saved');

  Stream<Map<String, dynamic>?> onSyncDone() => _service.on('sync_done');

  Stream<Map<String, dynamic>?> onError() => _service.on('tracking_error');

  Future<void> start({
    required bool useSimulation,
    required bool forceOffline,
  }) async {
    // Stop any stale instance WITHOUT clearing the session flag.
    if (await _service.isRunning()) {
      _service.invoke('stopService', {'keepSession': true});
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }

    await _session.setUseSimulation(useSimulation);
    await _session.setForceOffline(forceOffline);
    await _session.setUiCollecting(true);
    await _session.setTrackingActive(true);

    await _service.startService();
  }

  Future<void> stop() async {
    await _session.setTrackingActive(false);
    await _session.setUiCollecting(false);
    if (await _service.isRunning()) {
      _service.invoke('stopService');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> notifyUiPaused() async {
    await _session.setUiCollecting(false);
    if (await _service.isRunning()) {
      _service.invoke('ui_paused');
    }
  }

  Future<void> notifyUiResumed() async {
    await _session.setUiCollecting(true);
    if (await _service.isRunning()) {
      _service.invoke('ui_resumed');
    }
  }

  Future<void> updateForceOffline(bool value) async {
    await _session.setForceOffline(value);
    if (await _service.isRunning()) {
      _service.invoke('update_force_offline', {'value': value});
    }
  }

  Future<bool> resumeIfNeeded() async {
    final shouldTrack = await _session.isTrackingActive();
    if (!shouldTrack) return false;

    await _session.setUiCollecting(false);

    final permissionError = await ensureBackgroundPermissions(
      useSimulation: await _session.useSimulation(),
    );
    if (permissionError != null) return true;

    if (await _service.isRunning()) {
      _service.invoke('stopService', {'keepSession': true});
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    await _session.setTrackingActive(true);
    await _service.startService();
    return true;
  }
}
