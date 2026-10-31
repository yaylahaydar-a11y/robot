import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:fluttertoast/fluttertoast.dart';

class BluetoothProvider extends ChangeNotifier {
  BluetoothConnection? _connection;
  bool _isConnected = false;
  bool _isConnecting = false;

  // Robot state (Single Source of Truth)
  bool _robotEnabled = true;
  bool _fireDetected = false;
  String _fireDirection = 'NONE';
  int _leftSensor = 0;
  int _middleSensor = 0;
  int _rightSensor = 0;
  bool _manualMode = false;
  bool _pumpActive = false;
  bool _emergencyActive = false;
  bool _isMoving = false;
  
  // Transition State (for logic triggers)
  bool _lastFireBit = false;

  // Robustness & Sync
  bool _isWaitingForSync = false;
  String? _lastPendingCommand;
  Timer? _syncRescueTimer;
  int _lastTimestamp = 0;
  DateTime _lastHeartbeatTime = DateTime.now();

  // UI state
  final List<String> _alerts = [];
  final List<String> _commandHistory = [];
  final List<String> _rawLogs = [];

  // Communication
  String _incompleteBuffer = '';
  Timer? _watchdogTimer;
  Timer? _movingDebounceTimer;

  StreamSubscription<Uint8List>? _dataSubscription;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get robotEnabled => _robotEnabled;
  bool get fireDetected => _fireDetected;
  String get fireDirection => _fireDirection;
  int get leftSensor => _leftSensor;
  int get middleSensor => _middleSensor;
  int get rightSensor => _rightSensor;
  bool get manualMode => _manualMode;
  bool get pumpActive => _pumpActive;
  bool get isEmergencyActive => _emergencyActive;
  bool get isMoving => _isMoving;
  bool get isWaitingForSync => _isWaitingForSync;
  List<String> get alerts => _alerts;
  List<String> get commandHistory => _commandHistory;
  List<String> get rawLogs => _rawLogs;

  BluetoothProvider() {
    _startWatchdog();
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isConnected) return;
      final diff = DateTime.now().difference(_lastHeartbeatTime).inSeconds;
      
      // Arduino sends SENSOR_STATUS every 500ms in ALL modes.
      if (diff >= 8) {
        _handleDisconnection("Robot connection lost (8s)");
      }
    });
  }

  Future<void> connect(BluetoothDevice device) async {
    if (_isConnecting) return;
    _resetInternalState();
    _isConnecting = true;
    notifyListeners();

    try {
      _connection = await BluetoothConnection.toAddress(device.address);
      _isConnected = true;
      _lastHeartbeatTime = DateTime.now();
      _startListening();
      
      // Settle hardware link
      await Future.delayed(const Duration(milliseconds: 500));
      _executeRawCommand("robot_on");
      _executeRawCommand("manual_off");
      
      Fluttertoast.showToast(msg: "✓ Linked to Robot", backgroundColor: Colors.green);
    } catch (e) {
      _isConnected = false;
      Fluttertoast.showToast(msg: "Link Failed: $e", backgroundColor: Colors.red);
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  void _resetInternalState() {
    _fireDetected = false; _fireDirection = 'NONE'; _isMoving = false;
    _isWaitingForSync = false; _lastPendingCommand = null;
    _incompleteBuffer = ''; _alerts.clear(); _lastFireBit = false;
  }

  void _startListening() {
    _dataSubscription?.cancel();
    _dataSubscription = _connection?.input?.listen((Uint8List data) {
      _processReceivedData(utf8.decode(data, allowMalformed: true));
    }, onError: (e) => _handleDisconnection("Stream Error"), onDone: () => _handleDisconnection("Disconnected"));
  }

  void _processReceivedData(String chunk) {
    _incompleteBuffer += chunk;
    while (_incompleteBuffer.contains('\n')) {
      int idx = _incompleteBuffer.indexOf('\n');
      String msg = _incompleteBuffer.substring(0, idx).trim();
      _incompleteBuffer = _incompleteBuffer.substring(idx + 1);
      
      // Robust JSON detection
      if (msg.isNotEmpty && msg.startsWith('{') && msg.endsWith('}')) {
        _handleJsonMessage(msg);
      }
    }
  }

  void _handleJsonMessage(String msg) {
    try {
      final data = jsonDecode(msg);
      _lastHeartbeatTime = DateTime.now();
      
      _rawLogs.insert(0, msg);
      if (_rawLogs.length > 50) _rawLogs.removeLast();

      // Millis overflow handling
      int ts = data['ts'] ?? data['timestamp'] ?? 0;
      if (ts != 0) {
        if (ts < _lastTimestamp && (_lastTimestamp - ts < 10000)) return; 
        _lastTimestamp = ts;
      }

      final type = data['type'] ?? '';

      // Command Handshake
      if (type == 'ACK') {
        _isWaitingForSync = false;
        _lastPendingCommand = null;
        _syncRescueTimer?.cancel();
        return;
      }

      switch (type) {
        case 'FIRE_ALERT':
          _processFireEvent(data['sensor'] ?? 'UNKNOWN');
          break;
        case 'FIRE_CLEARED':
          _processFireCleared();
          break;
        case 'PUMP_STATUS':
          _pumpActive = (data['status'] == 'ON');
          _addAlert("💧 Pump: ${data['status']}", Colors.blue);
          _isWaitingForSync = false;
          break;
        case 'MODE_CHANGE':
          _manualMode = (data['mode'] == 'manual');
          _addAlert("⚙️ Mode: ${data['mode'].toUpperCase()}", Colors.purple);
          _isWaitingForSync = false;
          break;
        case 'EMERGENCY':
          _emergencyActive = true;
          _setMoving(false, immediate: true);
          _addAlert("🚨 EMERGENCY STOP", Colors.red);
          break;
        case 'SENSOR_STATUS':
          _updateRobotStateFromHeartbeat(data);
          break;
      }
      notifyListeners();
    } catch (e) {
      // Noise tolerance
    }
  }

  void _updateRobotStateFromHeartbeat(Map<String, dynamic> data) {
    _leftSensor = data['left'] ?? _leftSensor;
    _middleSensor = data['middle'] ?? _middleSensor;
    _rightSensor = data['right'] ?? _rightSensor;
    
    // 🛡️ STATE-DRIVEN ALERT ENGINE (Suspenders)
    // If the heartbeat shows fire but we haven't triggered an alert yet, trigger it now.
    bool fireBitNow = (data['fire'] == 1);
    if (fireBitNow && !_lastFireBit) {
       // Fire just appeared in the heartbeat stream
       String direction = 'UNKNOWN';
       if (data.containsKey('fdir')) {
          direction = data['fdir'] == 'L' ? 'LEFT' : (data['fdir'] == 'M' ? 'MIDDLE' : 'RIGHT');
       } else {
          if (_leftSensor == 1) direction = 'LEFT';
          else if (_middleSensor == 1) direction = 'MIDDLE';
          else if (_rightSensor == 1) direction = 'RIGHT';
       }
       _processFireEvent(direction);
    } else if (!fireBitNow && _lastFireBit) {
       // Fire just disappeared from the heartbeat stream
       _processFireCleared();
    }
    _lastFireBit = fireBitNow;

    _pumpActive = (data['pump'] == 1);
    _manualMode = (data['mode'] == 'manual');
    _emergencyActive = (data['emergency'] == 1);
    _robotEnabled = (data['enabled'] == 1);
    _setMoving(data['moving'] == 1);
  }

  void _processFireEvent(String sensor) {
    _fireDetected = true;
    _fireDirection = sensor;
    _addAlert("🔥 FIRE DETECTED: $_fireDirection", Colors.red);
  }

  void _processFireCleared() {
    _fireDetected = false;
    _fireDirection = 'NONE';
    _addAlert("✅ FIRE CLEARED", Colors.green);
  }

  void _addAlert(String msg, Color color) {
    // Deduplicate alerts within same 1-second window
    final ts = DateTime.now().toString().split(' ')[1].substring(0, 8);
    String entry = "[$ts] $msg";
    if (_alerts.isNotEmpty && _alerts.first.contains(msg)) return; 
    
    _alerts.insert(0, entry);
    if (_alerts.length > 50) _alerts.removeLast();
  }

  void _setMoving(bool moving, {bool immediate = false}) {
    if (immediate) { _movingDebounceTimer?.cancel(); _isMoving = moving; return; }
    if (moving == _isMoving) return;
    _movingDebounceTimer?.cancel();
    _movingDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      _isMoving = moving; notifyListeners();
    });
  }

  void sendCommand(String cmd) {
    if (!_isConnected || _connection == null) return;
    
    bool isMovement = (cmd.length == 1 && "fblrs".contains(cmd));
    if (_isWaitingForSync && !isMovement && !cmd.contains('manual')) return;

    _lastPendingCommand = cmd;
    if (!isMovement) _isWaitingForSync = true;

    // Movement: Send Redundant Burst for "Stop"
    if (cmd == "s") {
       _executeRawCommand("s\ns\ns");
    } else {
       _executeRawCommand(cmd);
    }
    
    _syncRescueTimer?.cancel();
    _syncRescueTimer = Timer(const Duration(seconds: 2), () {
      if (_isWaitingForSync) { _isWaitingForSync = false; _lastPendingCommand = null; notifyListeners(); }
    });
  }

  void _executeRawCommand(String cmd) {
    try {
      if (_connection != null && _isConnected) {
        _connection!.output.add(utf8.encode("$cmd\n"));
        _commandHistory.insert(0, cmd);
        if (_commandHistory.length > 20) _commandHistory.removeLast();
        notifyListeners();
      }
    } catch (e) { _handleDisconnection("Write Fail"); }
  }

  void switchMode(bool manual) => sendCommand(manual ? 'manual_on' : 'manual_off');
  void startMovement(String cmd) { if (_manualMode) sendCommand(cmd); }
  void stopMovement() => sendCommand('s');
  void clearAlerts() { _alerts.clear(); notifyListeners(); }
  void disconnect() { _handleDisconnection("Closed"); }

  void _handleDisconnection(String reason) {
    if (!_isConnected && _connection == null) return;
    _isConnected = false; _dataSubscription?.cancel();
    try { _connection?.close(); } catch (e) {}
    _connection = null; _syncRescueTimer?.cancel();
    notifyListeners();
    Fluttertoast.showToast(msg: "Offline: $reason", backgroundColor: Colors.red);
  }

  @override
  void dispose() { _watchdogTimer?.cancel(); _syncRescueTimer?.cancel(); _dataSubscription?.cancel(); _connection?.close(); super.dispose(); }
}
