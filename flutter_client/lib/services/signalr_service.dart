import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';
import '../models/attendance.dart';
import 'api_config.dart';

/// Base URL for SignalR connections
final String _defaultBaseUrl = getApiBaseUrl();

/// Device status notification model
class DeviceStatusNotification {
  final String deviceId;
  final String serialNumber;
  final String deviceName;
  final String? location;
  final String status;
  final String eventType;
  final DateTime timestamp;
  final String message;

  DeviceStatusNotification({
    required this.deviceId,
    required this.serialNumber,
    required this.deviceName,
    this.location,
    required this.status,
    required this.eventType,
    required this.timestamp,
    required this.message,
  });

  factory DeviceStatusNotification.fromJson(Map<String, dynamic> json) {
    // Support both camelCase and PascalCase (SignalR may send either)
    V? get<V>(String camelKey) {
      final v = json[camelKey];
      if (v != null) return v as V;
      final pascalKey = camelKey[0].toUpperCase() + camelKey.substring(1);
      return json[pascalKey] as V?;
    }

    return DeviceStatusNotification(
      deviceId: get('deviceId') ?? '',
      serialNumber: get('serialNumber') ?? '',
      deviceName: get('deviceName') ?? '',
      location: get('location'),
      status: get('status') ?? '',
      eventType: get('eventType') ?? '',
      timestamp: _parseTimestamp(get('timestamp')),
      message: get('message') ?? '',
    );
  }

  /// Parse timestamp từ server (UTC) và chuyển sang local time
  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    final strValue = value.toString();
    // Server có thể gửi UTC không có Z suffix, thêm Z để parse đúng rồi chuyển local
    final parsed = DateTime.tryParse(strValue.endsWith('Z') ? strValue : '${strValue}Z');
    return parsed?.toLocal() ?? DateTime.now();
  }

  bool get isOnline => status == 'Online';
  bool get isOffline => status == 'Offline';
  bool get isPending => status == 'Pending';
}

/// Service for real-time notifications via SignalR
class SignalRService {
  static final SignalRService _instance = SignalRService._internal();
  factory SignalRService() => _instance;
  SignalRService._internal();

  HubConnection? _hubConnection;
  bool _isConnected = false;
  bool _isReconnecting = false;
  int _reconnectAttempt = 0;
  String? _lastConnectionError;
  Completer<void>? _connectCompleter; // Mutex for concurrent connect calls
  
  // Track connection params for auto-reconnect
  String? _lastBaseUrl;
  String? _lastAccessToken;
  Future<String?> Function()? _tokenFactory;
  
  // Track joined groups for auto-rejoin on reconnect
  String? _currentStoreId;
  String? _currentUserId;
  final Set<String> _currentDeviceIds = {};
  
  // Stream controllers for broadcasting events
  final _attendanceController = StreamController<Attendance>.broadcast();
  final _notificationController = StreamController<Map<String, dynamic>>.broadcast();
  final _deviceStatusController = StreamController<DeviceStatusNotification>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _communicationController = StreamController<Map<String, dynamic>>.broadcast();
  
  /// Stream of new attendance notifications
  Stream<Attendance> get onNewAttendance => _attendanceController.stream;
  
  /// Stream of general notifications
  Stream<Map<String, dynamic>> get onNewNotification => _notificationController.stream;
  
  /// Stream of device status change notifications
  Stream<DeviceStatusNotification> get onDeviceStatusChanged => _deviceStatusController.stream;
  
  /// Stream of connection state changes (true = connected, false = disconnected)
  Stream<bool> get onConnectionStateChanged => _connectionStateController.stream;

  /// Stream of communication events (created, published, comment, reaction)
  Stream<Map<String, dynamic>> get onCommunicationEvent => _communicationController.stream;
  
  /// Whether the connection is active
  bool get isConnected => _isConnected;
  
  /// Last connection error message (for debugging)
  String? get lastError => _lastConnectionError;

  /// Connect to the SignalR hub
  /// [tokenFactory] is called to get a fresh token on each (re)connection
  Future<void> connect([String? baseUrl, String? accessToken, Future<String?> Function()? tokenFactory]) async {
    // Prevent concurrent connect calls (token race condition)
    if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
      debugPrint('📡 Connect already in progress, waiting...');
      await _connectCompleter!.future;
      return;
    }
    _connectCompleter = Completer<void>();

    // If already connected but need to reconnect with token
    if (_isConnected && accessToken != null && _hubConnection != null) {
      debugPrint('📡 SignalR already connected, reconnecting with auth token...');
      await disconnect();
    }
    
    if (_isConnected) {
      debugPrint('📡 SignalR already connected');
      _connectCompleter!.complete();
      return;
    }

    // Save connection params for auto-reconnect
    if (baseUrl != null) _lastBaseUrl = baseUrl;
    if (accessToken != null) _lastAccessToken = accessToken;
    if (tokenFactory != null) _tokenFactory = tokenFactory;

    try {
      // Get fresh token via factory if available
      String? token = _lastAccessToken;
      if (_tokenFactory != null) {
        token = await _tokenFactory!();
        _lastAccessToken = token;
      }
      
      final url = _lastBaseUrl ?? _defaultBaseUrl;
      final hubUrl = '$url/hubs/attendance';
      debugPrint('📡 Connecting to SignalR hub: $hubUrl (auth: ${token != null ? "yes" : "no"})');

      final options = HttpConnectionOptions(
        accessTokenFactory: token != null
            ? () async {
                // Use token factory to get fresh token on each reconnect
                if (_tokenFactory != null) {
                  final freshToken = await _tokenFactory!();
                  if (freshToken != null) {
                    _lastAccessToken = freshToken;
                    return freshToken;
                  }
                }
                return _lastAccessToken ?? token!;
              }
            : null,
      );

      _hubConnection = HubConnectionBuilder()
          .withUrl(hubUrl, options: options)
          .withAutomaticReconnect()
          .build();

      // Register event handlers
      _hubConnection!.on('NewAttendance', _handleNewAttendance);
      _hubConnection!.on('NewNotification', _handleNewNotification);
      _hubConnection!.on('DeviceStatusChanged', _handleDeviceStatusChanged);
      _hubConnection!.on('CommunicationCreated', _handleCommunicationEvent);
      _hubConnection!.on('CommunicationPublished', _handleCommunicationEvent);
      _hubConnection!.on('CommunicationCommentAdded', _handleCommunicationEvent);
      _hubConnection!.on('CommunicationReactionUpdated', _handleCommunicationEvent);

      // Connection state handlers
      _hubConnection!.onclose(({Exception? error}) {
        debugPrint('📡 SignalR connection closed: $error');
        _isConnected = false;
        _lastConnectionError = error?.toString();
        _connectionStateController.add(false);
        _scheduleReconnect();
      });

      _hubConnection!.onreconnecting(({Exception? error}) {
        debugPrint('📡 SignalR reconnecting: $error');
        _isConnected = false;
        _connectionStateController.add(false);
      });

      _hubConnection!.onreconnected(({String? connectionId}) {
        debugPrint('📡 SignalR reconnected: $connectionId');
        _isConnected = true;
        _lastConnectionError = null;
        _connectionStateController.add(true);
        _rejoinGroups();
      });

      await _hubConnection!.start();
      _isConnected = true;
      _isReconnecting = false;
      _reconnectAttempt = 0;
      _lastConnectionError = null;
      _connectionStateController.add(true);
      _connectCompleter?.complete();
      debugPrint('📡 SignalR connected successfully!');
    } catch (e) {
      debugPrint('📡 SignalR connection error: $e');
      _isConnected = false;
      _lastConnectionError = e.toString();
      _connectionStateController.add(false);
      _connectCompleter?.complete();
      _scheduleReconnect();
    }
  }

  /// Schedule a reconnect attempt with exponential backoff (max 60s)
  void _scheduleReconnect() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    final delay = math.min(5 * math.pow(2, _reconnectAttempt).toInt(), 60);
    _reconnectAttempt++;
    debugPrint('📡 Scheduling reconnect in $delay seconds (attempt $_reconnectAttempt)...');
    Future.delayed(Duration(seconds: delay), () async {
      if (_isConnected) {
        _isReconnecting = false;
        _reconnectAttempt = 0;
        return;
      }
      debugPrint('📡 Attempting to reconnect...');
      _hubConnection = null;
      await connect();
      if (_isConnected) {
        _reconnectAttempt = 0;
        await _rejoinGroups();
      } else {
        _isReconnecting = false;
        _scheduleReconnect();
      }
    });
  }

  /// Handle device status change notification
  void _handleDeviceStatusChanged(List<Object?>? args) {
    try {
      if (args == null || args.isEmpty) return;
      
      final data = args[0] as Map<String, dynamic>;
      debugPrint('📡 Received device status change: $data');
      
      final notification = DeviceStatusNotification.fromJson(data);
      _deviceStatusController.add(notification);
    } catch (e) {
      debugPrint('📡 Error parsing device status notification: $e');
    }
  }

  /// Handle incoming attendance notification
  void _handleNewAttendance(List<Object?>? args) {
    try {
      if (args == null || args.isEmpty) return;
      
      final data = args[0] as Map<String, dynamic>;
      debugPrint('📡 Received new attendance: $data');
      
      // Use fromJson to properly parse all fields
      final attendance = Attendance.fromJson(data);
      
      _attendanceController.add(attendance);
    } catch (e) {
      debugPrint('📡 Error parsing attendance notification: $e');
    }
  }

  /// Handle incoming general notification
  void _handleNewNotification(List<Object?>? args) {
    try {
      if (args == null || args.isEmpty) return;
      
      final data = args[0] as Map<String, dynamic>;
      debugPrint('📡 Received new notification: $data');
      
      _notificationController.add(data);
    } catch (e) {
      debugPrint('📡 Error parsing notification: $e');
    }
  }

  /// Handle communication events (created, published, comment, reaction)
  void _handleCommunicationEvent(List<Object?>? args) {
    try {
      if (args == null || args.isEmpty) return;
      
      final data = args[0] as Map<String, dynamic>;
      debugPrint('📡 Received communication event: $data');
      
      _communicationController.add(data);
    } catch (e) {
      debugPrint('📡 Error parsing communication event: $e');
    }
  }

  /// Join a store group to receive store-scoped notifications
  Future<void> joinStoreGroup(String storeId) async {
    _currentStoreId = storeId;
    await _invokeWithRetry('JoinStoreGroup', [storeId], 'store group: $storeId');
  }

  /// Leave a store group
  Future<void> leaveStoreGroup(String storeId) async {
    if (!_isConnected || _hubConnection == null) return;
    
    try {
      await _hubConnection!.invoke('LeaveStoreGroup', args: [storeId]);
      debugPrint('📡 Left store group: $storeId');
    } catch (e) {
      debugPrint('📡 Error leaving store group: $e');
    }
  }

  /// Join a device group to receive device-specific notifications
  Future<void> joinDeviceGroup(String deviceId) async {
    _currentDeviceIds.add(deviceId);
    await _invokeWithRetry('JoinDeviceGroup', [deviceId], 'device group: $deviceId');
  }

  /// Leave a device group
  Future<void> leaveDeviceGroup(String deviceId) async {
    if (!_isConnected || _hubConnection == null) return;
    
    try {
      await _hubConnection!.invoke('LeaveDeviceGroup', args: [deviceId]);
      debugPrint('📡 Left device group: $deviceId');
    } catch (e) {
      debugPrint('📡 Error leaving device group: $e');
    }
  }

  /// Join a user group to receive user-specific notifications
  Future<void> joinUserGroup(String userId) async {
    _currentUserId = userId;
    await _invokeWithRetry('JoinUserGroup', [userId], 'user group: $userId');
  }

  /// Leave a user group
  Future<void> leaveUserGroup(String userId) async {
    if (!_isConnected || _hubConnection == null) return;
    
    try {
      await _hubConnection!.invoke('LeaveUserGroup', args: [userId]);
      debugPrint('📡 Left user group: $userId');
    } catch (e) {
      debugPrint('📡 Error leaving user group: $e');
    }
  }

  /// Invoke a hub method with retry logic for transient connection issues
  Future<void> _invokeWithRetry(String method, List<Object> args, String label) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!_isConnected || _hubConnection == null) {
        debugPrint('📡 Cannot join $label - not connected (attempt ${attempt + 1})');
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 1 + attempt));
          continue;
        }
        return;
      }
      try {
        await _hubConnection!.invoke(method, args: args);
        debugPrint('📡 Joined $label');
        return;
      } catch (e) {
        debugPrint('📡 Error joining $label (attempt ${attempt + 1}): $e');
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 1 + attempt));
        }
      }
    }
  }

  /// Rejoin all previously joined groups after reconnection
  Future<void> _rejoinGroups() async {
    debugPrint('📡 Rejoining groups after reconnect...');
    if (_currentStoreId != null) {
      await _invokeWithRetry('JoinStoreGroup', [_currentStoreId!], 'store group: $_currentStoreId');
    }
    if (_currentUserId != null) {
      await _invokeWithRetry('JoinUserGroup', [_currentUserId!], 'user group: $_currentUserId');
    }
    for (final deviceId in _currentDeviceIds) {
      await _invokeWithRetry('JoinDeviceGroup', [deviceId], 'device group: $deviceId');
    }
  }

  /// Disconnect from the SignalR hub
  Future<void> disconnect() async {
    if (_hubConnection != null) {
      await _hubConnection!.stop();
      _isConnected = false;
      debugPrint('📡 SignalR disconnected');
    }
  }

  /// Dispose resources
  void dispose() {
    _attendanceController.close();
    _notificationController.close();
    _deviceStatusController.close();
    _connectionStateController.close();
    _communicationController.close();
    disconnect();
  }
}

/// Alias for backward compatibility  
typedef AttendanceSignalRService = SignalRService;
