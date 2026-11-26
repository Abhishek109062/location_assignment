import 'package:shared_preferences/shared_preferences.dart';

/// Persists tracking session flags so a killed app can resume on next launch.
///
/// Always [reload]s before reads so the background isolate sees writes made
/// by the UI isolate (SharedPreferences caches per-isolate).
class TrackingSessionStore {
  static const trackingActiveKey = 'tracking_active';
  static const useSimulationKey = 'use_simulation';
  static const forceOfflineKey = 'force_offline';
  static const uiCollectingKey = 'ui_collecting';

  Future<SharedPreferences> _freshPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  Future<void> setTrackingActive(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(trackingActiveKey, value);
  }

  Future<bool> isTrackingActive() async {
    final prefs = await _freshPrefs();
    return prefs.getBool(trackingActiveKey) ?? false;
  }

  Future<void> setUseSimulation(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(useSimulationKey, value);
  }

  Future<bool> useSimulation() async {
    final prefs = await _freshPrefs();
    return prefs.getBool(useSimulationKey) ?? true;
  }

  Future<void> setForceOffline(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(forceOfflineKey, value);
  }

  Future<bool> forceOffline() async {
    final prefs = await _freshPrefs();
    return prefs.getBool(forceOfflineKey) ?? false;
  }

  /// When true, the UI isolate is already writing GPS points — the background
  /// isolate skips collecting to avoid duplicates, but still can sync.
  Future<void> setUiCollecting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(uiCollectingKey, value);
  }

  Future<bool> isUiCollecting() async {
    final prefs = await _freshPrefs();
    return prefs.getBool(uiCollectingKey) ?? false;
  }
}
