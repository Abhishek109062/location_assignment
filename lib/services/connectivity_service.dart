import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Observes device network reachability and supports a manual offline override
/// so reviewers can demo the queue without toggling Airplane Mode.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final _controller = StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _forceOffline = false;
  bool _lastDeviceOnline = true;

  bool get forceOffline => _forceOffline;

  /// Effective online state (device AND not force-offline).
  bool get isOnline => !_forceOffline && _lastDeviceOnline;

  Stream<bool> get onStatusChanged => _controller.stream;

  Future<void> start() async {
    final initial = await _connectivity.checkConnectivity();
    _lastDeviceOnline = _isOnline(initial);
    _emit();

    _sub = _connectivity.onConnectivityChanged.listen((results) {
      _lastDeviceOnline = _isOnline(results);
      _emit();
    });
  }

  void setForceOffline(bool value) {
    _forceOffline = value;
    _emit();
  }

  bool _isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(isOnline);
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}
