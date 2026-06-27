import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  bool _isOnline = true;
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();
  
  Timer? _offlineDebounceTimer;
  bool _offlineNotificationShown = false;

  Stream<bool> get connectivityStream => _connectivityController.stream;
  bool get isOnline => _isOnline;

  Future<void> initialize() async {
    final result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result);

    _connectivity.onConnectivityChanged.listen((result) {
      _updateConnectionStatus(result);
    });
  }

  void _updateConnectionStatus(List<ConnectivityResult> result) {
    final wasOnline = _isOnline;
    _isOnline = !result.contains(ConnectivityResult.none);
    
    if (wasOnline != _isOnline) {
      if (!_isOnline) {
        // Going offline - start debounce timer
        _offlineDebounceTimer?.cancel();
        _offlineDebounceTimer = Timer(const Duration(seconds: 10), () {
          _offlineNotificationShown = true;
          _connectivityController.add(false);
        });
      } else {
        // Coming back online
        _offlineDebounceTimer?.cancel();
        _offlineDebounceTimer = null;
        
        // Only show online notification if offline notification was shown
        if (_offlineNotificationShown) {
          _offlineNotificationShown = false;
          _connectivityController.add(true);
        }
      }
    }
  }

  Future<bool> checkConnection() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);
    return _isOnline;
  }

  void dispose() {
    _offlineDebounceTimer?.cancel();
    _connectivityController.close();
  }
}
