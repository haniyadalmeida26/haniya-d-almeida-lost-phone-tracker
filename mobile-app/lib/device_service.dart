import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceService {
  DeviceService._internal();

  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;

  static const String _deviceIdKey = 'device_id';
  static const Duration _normalLocationInterval = Duration(seconds: 30);
  static const Duration _lostModeLocationInterval = Duration(seconds: 5);
  static const Duration _offlineThreshold = Duration(minutes: 2);
  static const String _bleServiceUuid = 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7';
  static const int _bleManufacturerId = 1234;
  static const MethodChannel _backgroundChannel =
      MethodChannel('lost_phone_tracker/background');

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _deviceListener;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  StreamSubscription<String>? _fcmTokenRefreshSubscription;
  Timer? _locationTimer;
  bool _isCurrentlyLost = false;
  bool _alarmActive = false;
  bool _isAdvertisingLostBeacon = false;
  final AudioPlayer _alarmPlayer = AudioPlayer();

  bool get isControllerClient => kIsWeb;
  bool get isTrackablePhone =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  CollectionReference<Map<String, dynamic>> get _devices =>
      FirebaseFirestore.instance.collection('devices');

  Future<void> initializeCurrentDevice() async {
    if (!isTrackablePhone) {
      return;
    }

    await registerTrackedPhone();
    await _initializePushMessaging();
    startDeviceListener();
    await _publishAppHeartbeat();
    await startLocationHeartbeat();
  }

  Future<String?> getCurrentTrackedDeviceIdOrNull() async {
    if (!isTrackablePhone) {
      return null;
    }
    return getDeviceId();
  }

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_deviceIdKey);
    if (savedId != null && savedId.isNotEmpty) {
      return savedId;
    }

    final deviceId = await _generateHardwareId();
    await prefs.setString(_deviceIdKey, deviceId);
    return deviceId;
  }

  Future<String> _generateHardwareId() async {
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return '${info.brand}_${info.id}_${info.model}'.replaceAll(' ', '_');
      }

      if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return (info.identifierForVendor ?? _fallbackId()).replaceAll(' ', '_');
      }
    } catch (_) {}

    return _fallbackId();
  }

  String _fallbackId() => 'device_${DateTime.now().millisecondsSinceEpoch}';

  Future<Map<String, String>> getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return {
          'model': '${info.manufacturer} ${info.model}',
          'platform': 'android',
          'osVersion': info.version.release,
        };
      }

      if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return {
          'model': info.utsname.machine,
          'platform': 'ios',
          'osVersion': info.systemVersion,
        };
      }
    } catch (_) {}

    return {
      'model': 'Unknown Device',
      'platform': 'unknown',
      'osVersion': 'unknown',
    };
  }

  Future<void> registerTrackedPhone() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !isTrackablePhone) {
      return;
    }

    final deviceId = await getDeviceId();
    final info = await getDeviceInfo();

    await _devices.doc(deviceId).set({
      'deviceId': deviceId,
      'userId': user.uid,
      'role': 'tracked_phone',
      'deviceName': info['model'],
      'model': info['model'],
      'platform': info['platform'],
      'osVersion': info['osVersion'],
      'registeredAt': FieldValue.serverTimestamp(),
      'lastHeartbeatAt': FieldValue.serverTimestamp(),
      'lastLocation': null,
      'latestDetection': null,
      'prediction': null,
      'fcmToken': null,
      'status': {
        'isLost': false,
        'isOnline': true,
        'possibleSwitchOff': false,
        'offlineReason': null,
        'lostActivatedAt': null,
        'foundAt': null,
        'lastDetectionAt': null,
        'alarmActive': false,
      },
      'commands': {
        'alarmActive': false,
      },
      'bleBeacon': {
        'serviceUuid': _bleServiceUuid,
        'manufacturerId': _bleManufacturerId,
        'beaconCode': _beaconCodeForDevice(deviceId),
      },
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'email': user.email,
      'name': user.email?.split('@').first ?? 'User',
      'devices': FieldValue.arrayUnion([deviceId]),
      'trustedFinderEmails': FieldValue.arrayUnion([]),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _initializePushMessaging() async {
    if (!isTrackablePhone) {
      return;
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await messaging.getToken();
    if (token != null) {
      await _saveFcmToken(token);
    }

    _fcmTokenRefreshSubscription?.cancel();
    _fcmTokenRefreshSubscription =
        messaging.onTokenRefresh.listen((token) async {
      await _saveFcmToken(token);
    });

    _foregroundMessageSubscription ??= FirebaseMessaging.onMessage.listen(
      (message) async {
        await handleRemoteCommandMessage(message.data);
      },
    );

    _openedMessageSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
      (message) async {
        await handleRemoteCommandMessage(message.data);
      },
    );

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      await handleRemoteCommandMessage(initialMessage.data);
    }
  }

  Future<void> _saveFcmToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !isTrackablePhone) {
      return;
    }

    final deviceId = await getDeviceId();
    await _devices.doc(deviceId).set({
      'fcmToken': token,
      'lastFcmTokenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void startDeviceListener() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !isTrackablePhone) {
      return;
    }

    final deviceId = await getDeviceId();
    _deviceListener?.cancel();

    _deviceListener =
        _devices.doc(deviceId).snapshots().listen((snapshot) async {
      if (!snapshot.exists) {
        return;
      }

      final data = snapshot.data();
      if (data == null) {
        return;
      }

      final status = Map<String, dynamic>.from(data['status'] ?? {});
      final commands = Map<String, dynamic>.from(data['commands'] ?? {});
      final nextLostState = status['isLost'] == true;
      final nextAlarmState = commands['alarmActive'] == true;
      final lostStateChanged = _isCurrentlyLost != nextLostState;
      final alarmStateChanged = _alarmActive != nextAlarmState;

      if (alarmStateChanged) {
        _alarmActive = nextAlarmState;
        await _setAlarmPlayback(_alarmActive);
        await _devices.doc(deviceId).set({
          'status': {
            'alarmActive': _alarmActive,
          },
        }, SetOptions(merge: true));

        await _appendEvent(
          deviceId: deviceId,
          type: _alarmActive ? 'alarm_started' : 'alarm_stopped',
          message: _alarmActive
              ? 'Controller turned alarm on.'
              : 'Controller turned alarm off.',
        );
      }

      if (lostStateChanged) {
        _isCurrentlyLost = nextLostState;
        await _restartLocationTimer();
        await _updateBleAdvertising(deviceId);
        await _syncNativeLostModeService(
          deviceId: deviceId,
          alarmActive: nextAlarmState,
          openUi: _isCurrentlyLost,
        );
        await _appendEvent(
          deviceId: deviceId,
          type: _isCurrentlyLost ? 'lost_mode_started' : 'lost_mode_stopped',
          message: _isCurrentlyLost
              ? 'Controller activated Lost Mode.'
              : 'Controller deactivated Lost Mode.',
        );

        if (_isCurrentlyLost) {
          await _publishCurrentLocationOrHeartbeat();
        }
      }

      if (alarmStateChanged && !lostStateChanged) {
        await _syncNativeLostModeService(
          deviceId: deviceId,
          alarmActive: _alarmActive,
          openUi: false,
        );
      }
    });
  }

  Future<void> startLocationHeartbeat() async {
    if (!isTrackablePhone) {
      return;
    }

    final hasPermission = await _checkLocationPermission();
    if (!hasPermission) {
      return;
    }

    await _publishCurrentLocationOrHeartbeat();
    await _restartLocationTimer();
  }

  Future<void> _restartLocationTimer() async {
    _locationTimer?.cancel();
    final interval =
        _isCurrentlyLost ? _lostModeLocationInterval : _normalLocationInterval;
    _locationTimer = Timer.periodic(interval, (_) async {
      await _publishCurrentLocationOrHeartbeat();
    });
  }

  String _beaconCodeForDevice(String deviceId) {
    final compact = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (compact.length <= 12) {
      return compact.toUpperCase();
    }
    return compact.substring(compact.length - 12).toUpperCase();
  }

  Future<void> _updateBleAdvertising(String deviceId) async {
    if (!isTrackablePhone) {
      return;
    }

    if (_isCurrentlyLost) {
      await _startBleAdvertising(deviceId);
    } else {
      await _stopBleAdvertising();
    }
  }

  Future<void> _startBleAdvertising(String deviceId) async {
    final blePeripheral = FlutterBlePeripheral();
    if (!await blePeripheral.isSupported) {
      return;
    }

    final permission = await blePeripheral.hasPermission();
    if (permission != BluetoothPeripheralState.granted) {
      final requested = await blePeripheral.requestPermission();
      if (requested != BluetoothPeripheralState.granted) {
        return;
      }
    }

    final bluetoothOn = await blePeripheral.isBluetoothOn;
    if (!bluetoothOn) {
      await blePeripheral.enableBluetooth();
    }

    final beaconCode = _beaconCodeForDevice(deviceId);
    final advertiseData = AdvertiseData(
      serviceUuid: _bleServiceUuid,
      manufacturerId: _bleManufacturerId,
      manufacturerData: Uint8List.fromList(utf8.encode(beaconCode)),
      localName: 'LPT-$beaconCode',
      includeDeviceName: true,
    );

    await blePeripheral.start(advertiseData: advertiseData);
    _isAdvertisingLostBeacon = true;
  }

  Future<void> _stopBleAdvertising() async {
    if (!_isAdvertisingLostBeacon) {
      return;
    }

    try {
      await FlutterBlePeripheral().stop();
    } catch (_) {}
    _isAdvertisingLostBeacon = false;
  }

  Future<void> _publishCurrentLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !isTrackablePhone) {
      return;
    }

    final hasPermission = await _checkLocationPermission();
    if (!hasPermission) {
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final deviceId = await getDeviceId();
      final now = DateTime.now();

      final locationPayload = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'source': _isCurrentlyLost ? 'lost_mode' : 'heartbeat',
        'recordedAt': Timestamp.fromDate(now),
      };

      await _devices.doc(deviceId).set({
        'lastHeartbeatAt': FieldValue.serverTimestamp(),
        'lastLocation': locationPayload,
        'status': {
          'isLost': _isCurrentlyLost,
          'isOnline': true,
          'possibleSwitchOff': false,
          'offlineReason': null,
          'alarmActive': _alarmActive,
        },
      }, SetOptions(merge: true));

      await _devices.doc(deviceId).collection('location_history').add({
        ...locationPayload,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await updatePrediction(deviceId);
    } catch (_) {
      await _publishAppHeartbeat();
    }
  }

  Future<void> _publishCurrentLocationOrHeartbeat() async {
    final hasPermission = await _checkLocationPermission();
    if (!hasPermission) {
      await _publishAppHeartbeat();
      return;
    }

    await _publishCurrentLocation();
  }

  Future<void> _publishAppHeartbeat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !isTrackablePhone) {
      return;
    }

    final deviceId = await getDeviceId();
    await _devices.doc(deviceId).set({
      'lastHeartbeatAt': FieldValue.serverTimestamp(),
      'status': {
        'isLost': _isCurrentlyLost,
        'isOnline': true,
        'possibleSwitchOff': false,
        'offlineReason': null,
        'alarmActive': _alarmActive,
      },
      'appState': {
        'lastForegroundHeartbeatAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  Future<bool> _checkLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    return permission != LocationPermission.deniedForever;
  }

  Future<void> setLostModeForDevice(String deviceId, bool isLost) async {
    await _devices.doc(deviceId).set({
      'status': {
        'isLost': isLost,
        'lostActivatedAt': isLost ? FieldValue.serverTimestamp() : null,
        'foundAt': isLost ? null : FieldValue.serverTimestamp(),
        'alarmActive': isLost,
      },
      'commands': {
        'alarmActive': isLost,
      },
    }, SetOptions(merge: true));

    await _appendEvent(
      deviceId: deviceId,
      type: isLost ? 'controller_marked_lost' : 'controller_marked_found',
      message: isLost
          ? 'Controller marked this phone as lost.'
          : 'Controller marked this phone as found.',
    );

    await _sendRemoteWakeupCommand(
      deviceId: deviceId,
      isLost: isLost,
      alarmActive: isLost,
    );
  }

  Future<void> clearAlarmForDevice(String deviceId) async {
    await _devices.doc(deviceId).set({
      'commands': {
        'alarmActive': false,
      },
      'status': {
        'alarmActive': false,
      },
    }, SetOptions(merge: true));

    await _appendEvent(
      deviceId: deviceId,
      type: 'controller_alarm_cleared',
      message: 'Controller cleared the alarm.',
    );

    await _sendRemoteWakeupCommand(
      deviceId: deviceId,
      isLost: true,
      alarmActive: false,
    );
  }

  Future<void> _sendRemoteWakeupCommand({
    required String deviceId,
    required bool isLost,
    required bool alarmActive,
  }) async {
    if (!isControllerClient) {
      return;
    }

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('sendLostModeCommand');
      await callable.call({
        'deviceId': deviceId,
        'isLost': isLost,
        'alarmActive': alarmActive,
      });
    } catch (error) {
      debugPrint('Push wakeup request error: $error');
    }
  }

  Future<void> handleRemoteCommandMessage(Map<String, dynamic> data) async {
    if (!isTrackablePhone || data.isEmpty) {
      return;
    }

    final targetDeviceId = data['deviceId']?.toString();
    final currentDeviceId = await getDeviceId();
    if (targetDeviceId == null || targetDeviceId != currentDeviceId) {
      return;
    }

    final isLost = data['isLost']?.toString() == 'true';
    final alarmActive = data['alarmActive']?.toString() == 'true';

    _isCurrentlyLost = isLost;
    _alarmActive = alarmActive;

    await _restartLocationTimer();
    await _updateBleAdvertising(currentDeviceId);
    await _setAlarmPlayback(alarmActive);
    await _syncNativeLostModeService(
      deviceId: currentDeviceId,
      alarmActive: alarmActive,
      openUi: isLost,
    );

    await _devices.doc(currentDeviceId).set({
      'status': {
        'isLost': isLost,
        'alarmActive': alarmActive,
        'isOnline': true,
      },
      'commands': {
        'alarmActive': alarmActive,
      },
      'lastWakePushAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _appendEvent(
      deviceId: currentDeviceId,
      type: 'push_wakeup_received',
      message: isLost
          ? 'Wake-up push received for Lost Mode.'
          : 'Wake-up push received to clear Lost Mode.',
    );

    if (isLost) {
      await _publishCurrentLocation();
    }
  }

  Future<void> _setAlarmPlayback(bool enabled) async {
    if (!isTrackablePhone) {
      return;
    }

    try {
      if (enabled) {
        await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
        await _alarmPlayer.setVolume(1.0);
        await _alarmPlayer.play(AssetSource('audio/lost_alarm.mpeg'));
      } else {
        await _alarmPlayer.stop();
      }
    } catch (_) {}
  }

  Future<void> _syncNativeLostModeService({
    required String deviceId,
    required bool alarmActive,
    required bool openUi,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    try {
      if (_isCurrentlyLost) {
        final snapshot = await _devices.doc(deviceId).get();
        final deviceName =
            snapshot.data()?['deviceName']?.toString() ?? 'Lost Phone';
        await _backgroundChannel.invokeMethod('startLostModeService', {
          'deviceId': deviceId,
          'deviceName': deviceName,
          'alarmActive': alarmActive,
          'openUi': openUi,
        });
      } else {
        await _backgroundChannel.invokeMethod('stopLostModeService');
      }
    } catch (_) {}
  }

  Future<void> _appendEvent({
    required String deviceId,
    required String type,
    required String message,
  }) async {
    await _devices.doc(deviceId).collection('events').add({
      'type': type,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<String> simulateFinderDetectionForDevice(String targetDeviceId) async {
    final finderUser = FirebaseAuth.instance.currentUser;
    if (finderUser == null) {
      return 'Please sign in first.';
    }

    final hasPermission = await _checkLocationPermission();
    if (!hasPermission) {
      return 'Finder location permission is required.';
    }

    final targetSnapshot = await _devices.doc(targetDeviceId).get();
    if (!targetSnapshot.exists) {
      return 'Target device not found.';
    }

    final targetData = targetSnapshot.data() ?? {};
    final targetStatus = Map<String, dynamic>.from(targetData['status'] ?? {});
    if (targetStatus['isLost'] != true) {
      return 'Mark the phone as LOST before simulating detection.';
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    final detectionTime = DateTime.now();
    final finderPriority = await _getFinderPriorityForOwner(
      targetData['userId']?.toString(),
    );

    final detectionPayload = {
      'deviceId': targetDeviceId,
      'ownerUserId': targetData['userId'],
      'finderUserId': finderUser.uid,
      'finderEmail': finderUser.email,
      'finderDeviceId':
          isTrackablePhone ? await getDeviceId() : 'controller_web',
      'finderLabel':
          isControllerClient ? 'controller-simulation' : 'simulated-finder',
      'priorityRank': finderPriority['rank'],
      'priorityLabel': finderPriority['label'],
      'source': 'simulation',
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'timestamp': Timestamp.fromDate(detectionTime),
    };

    await _devices.doc(targetDeviceId).collection('detections').add({
      ...detectionPayload,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _promoteLatestDetectionIfNeeded(
      targetDeviceId: targetDeviceId,
      detectionPayload: detectionPayload,
    );

    await _appendEvent(
      deviceId: targetDeviceId,
      type: 'finder_detection_uploaded',
      message:
          'Finder detection uploaded by controller (${finderPriority['label']}).',
    );

    return 'Finder detection uploaded successfully.';
  }

  Future<String> scanForNearbyLostDevices() async {
    final finderUser = FirebaseAuth.instance.currentUser;
    if (finderUser == null) {
      return 'Please sign in first.';
    }

    final hasPermissions = await _requestFinderBluetoothPermissions();
    if (!hasPermissions) {
      return 'Bluetooth and location permissions are required for real BLE scanning.';
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      if (!kIsWeb && Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
      }
      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () {
        return BluetoothAdapterState.off;
      });
    }

    final lostDevices = await _devices
        .where('role', isEqualTo: 'tracked_phone')
        .where('status.isLost', isEqualTo: true)
        .get();

    if (lostDevices.docs.isEmpty) {
      return 'No lost phones are broadcasting right now.';
    }

    final beaconMap = <String, Map<String, dynamic>>{};
    for (final doc in lostDevices.docs) {
      final data = doc.data();
      final beacon = Map<String, dynamic>.from(data['bleBeacon'] ?? {});
      final beaconCode = beacon['beaconCode']?.toString();
      if (beaconCode != null && beaconCode.isNotEmpty) {
        beaconMap[beaconCode] = {
          'deviceId': doc.id,
          'userId': data['userId'],
        };
      }
    }

    if (beaconMap.isEmpty) {
      return 'Lost phones are missing BLE beacon metadata.';
    }

    final matchedDeviceIds = <String>{};
    final subscription = FlutterBluePlus.onScanResults.listen(
      (results) async {
        for (final result in results) {
          final beaconCode = _extractBeaconCode(result);
          if (beaconCode == null) {
            continue;
          }

          final target = beaconMap[beaconCode];
          if (target == null) {
            continue;
          }

          final targetDeviceId = target['deviceId'] as String;
          if (matchedDeviceIds.contains(targetDeviceId)) {
            continue;
          }

          matchedDeviceIds.add(targetDeviceId);
          await _reportFinderDetection(
            targetDeviceId: targetDeviceId,
            ownerUserId: target['userId'] as String?,
            finderLabel: 'real-ble-finder',
            source: 'ble_scan',
          );
        }
      },
      onError: (_) {},
    );

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(_bleServiceUuid)],
        timeout: const Duration(seconds: 12),
        androidUsesFineLocation: true,
      );
      await FlutterBluePlus.isScanning
          .where((value) => value == false)
          .first
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
    } catch (_) {
      await FlutterBluePlus.stopScan();
    } finally {
      await subscription.cancel();
    }

    if (matchedDeviceIds.isEmpty) {
      return 'Scan finished. No nearby lost phone beacon was detected.';
    }

    return 'Scan finished. Found ${matchedDeviceIds.length} nearby lost phone beacon(s).';
  }

  String? _extractBeaconCode(ScanResult result) {
    final manufacturerData = result.advertisementData.manufacturerData;
    final bytes = manufacturerData[_bleManufacturerId];
    if (bytes != null && bytes.isNotEmpty) {
      return utf8.decode(bytes, allowMalformed: true).trim().toUpperCase();
    }

    final advName = result.advertisementData.advName.trim().toUpperCase();
    if (advName.startsWith('LPT-')) {
      return advName.replaceFirst('LPT-', '').trim();
    }

    return null;
  }

  Future<bool> _requestFinderBluetoothPermissions() async {
    if (kIsWeb) {
      return false;
    }

    if (Platform.isAndroid) {
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      return results.values.every((status) => status.isGranted);
    }

    if (Platform.isIOS) {
      final results = await [
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ].request();
      return results.values.every((status) => status.isGranted);
    }

    return false;
  }

  Future<void> _reportFinderDetection({
    required String targetDeviceId,
    required String? ownerUserId,
    required String finderLabel,
    required String source,
  }) async {
    final finderUser = FirebaseAuth.instance.currentUser;
    if (finderUser == null) {
      return;
    }
    final finderPriority = await _getFinderPriorityForOwner(ownerUserId);

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    final detectionTime = DateTime.now();

    final detectionPayload = {
      'deviceId': targetDeviceId,
      'ownerUserId': ownerUserId,
      'finderUserId': finderUser.uid,
      'finderEmail': finderUser.email,
      'finderDeviceId':
          isTrackablePhone ? await getDeviceId() : 'controller_web',
      'finderLabel': finderLabel,
      'priorityRank': finderPriority['rank'],
      'priorityLabel': finderPriority['label'],
      'source': source,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'timestamp': Timestamp.fromDate(detectionTime),
    };

    await _devices.doc(targetDeviceId).collection('detections').add({
      ...detectionPayload,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _promoteLatestDetectionIfNeeded(
      targetDeviceId: targetDeviceId,
      detectionPayload: detectionPayload,
    );

    await _appendEvent(
      deviceId: targetDeviceId,
      type: 'real_ble_detection_uploaded',
      message:
          'Nearby finder phone uploaded a real BLE detection (${finderPriority['label']}).',
    );
  }

  Future<Map<String, Object>> _getFinderPriorityForOwner(
    String? ownerUserId,
  ) async {
    final finderUser = FirebaseAuth.instance.currentUser;
    if (ownerUserId == null || finderUser?.email == null) {
      return {'rank': 2, 'label': 'public_finder'};
    }

    final ownerDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(ownerUserId)
        .get();
    final trustedEmails = List<String>.from(
      ownerDoc.data()?['trustedFinderEmails'] ?? const <String>[],
    ).map((email) => email.trim().toLowerCase()).toList();

    final finderEmail = finderUser!.email!.trim().toLowerCase();
    if (trustedEmails.contains(finderEmail)) {
      return {'rank': 1, 'label': 'trusted_contact'};
    }

    return {'rank': 2, 'label': 'public_finder'};
  }

  Future<void> _promoteLatestDetectionIfNeeded({
    required String targetDeviceId,
    required Map<String, dynamic> detectionPayload,
  }) async {
    final deviceSnapshot = await _devices.doc(targetDeviceId).get();
    final deviceData = deviceSnapshot.data() ?? {};
    final currentLatest =
        Map<String, dynamic>.from(deviceData['latestDetection'] ?? {});

    final currentRank = (currentLatest['priorityRank'] as num?)?.toInt() ?? 99;
    final newRank = (detectionPayload['priorityRank'] as num?)?.toInt() ?? 99;
    final currentTimestamp = currentLatest['timestamp'];
    final currentTime =
        currentTimestamp is Timestamp ? currentTimestamp.toDate() : null;
    final newTime = (detectionPayload['timestamp'] as Timestamp).toDate();

    final shouldReplace = currentLatest.isEmpty ||
        newRank < currentRank ||
        (newRank == currentRank &&
            (currentTime == null || newTime.isAfter(currentTime)));

    await _devices.doc(targetDeviceId).set({
      if (shouldReplace) 'latestDetection': detectionPayload,
      'status': {
        'lastDetectionAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  Future<void> refreshDerivedState(String deviceId) async {
    await evaluateOfflineState(deviceId);
    await updatePrediction(deviceId);
  }

  Future<void> evaluateOfflineState(String deviceId) async {
    final snapshot = await _devices.doc(deviceId).get();
    if (!snapshot.exists) {
      return;
    }

    final data = snapshot.data() ?? {};
    final lastHeartbeat = data['lastHeartbeatAt'];
    if (lastHeartbeat is! Timestamp) {
      return;
    }

    final lastHeartbeatTime = lastHeartbeat.toDate();
    final now = DateTime.now();
    final isOffline = now.difference(lastHeartbeatTime) > _offlineThreshold;
    final possibleSwitchOff =
        isOffline && await _wasMovingBeforeDisconnect(deviceId);

    await _devices.doc(deviceId).set({
      'status': {
        'isOnline': !isOffline,
        'possibleSwitchOff': possibleSwitchOff,
        'offlineReason': isOffline
            ? (possibleSwitchOff
                ? 'possible_switch_off_or_network_loss'
                : 'no_recent_updates')
            : null,
      },
    }, SetOptions(merge: true));
  }

  Future<bool> _wasMovingBeforeDisconnect(String deviceId) async {
    final history = await _devices
        .doc(deviceId)
        .collection('location_history')
        .orderBy('timestamp', descending: true)
        .limit(3)
        .get();

    if (history.docs.length < 2) {
      return false;
    }

    final points = history.docs
        .map((doc) => doc.data())
        .where((data) => data['latitude'] != null && data['longitude'] != null)
        .toList();

    if (points.length < 2) {
      return false;
    }

    final latest = points[0];
    final previous = points[1];

    final distanceInMeters = Geolocator.distanceBetween(
      (latest['latitude'] as num).toDouble(),
      (latest['longitude'] as num).toDouble(),
      (previous['latitude'] as num).toDouble(),
      (previous['longitude'] as num).toDouble(),
    );

    return distanceInMeters > 75;
  }

  Future<void> updatePrediction(String deviceId) async {
    final history = await _devices
        .doc(deviceId)
        .collection('location_history')
        .orderBy('timestamp', descending: true)
        .limit(3)
        .get();

    if (history.docs.length < 2) {
      return;
    }

    final points = history.docs
        .map((doc) => doc.data())
        .where((data) => data['latitude'] != null && data['longitude'] != null)
        .toList()
        .reversed
        .toList();

    if (points.length < 2) {
      return;
    }

    final secondLast = points[points.length - 2];
    final last = points[points.length - 1];

    double deltaLat = (last['latitude'] as num).toDouble() -
        (secondLast['latitude'] as num).toDouble();
    double deltaLng = (last['longitude'] as num).toDouble() -
        (secondLast['longitude'] as num).toDouble();

    if (points.length == 3) {
      final first = points[0];
      final deltaLat1 = (secondLast['latitude'] as num).toDouble() -
          (first['latitude'] as num).toDouble();
      final deltaLng1 = (secondLast['longitude'] as num).toDouble() -
          (first['longitude'] as num).toDouble();
      deltaLat = (deltaLat + deltaLat1) / 2;
      deltaLng = (deltaLng + deltaLng1) / 2;
    }

    await _devices.doc(deviceId).set({
      'prediction': {
        'latitude': (last['latitude'] as num).toDouble() + deltaLat,
        'longitude': (last['longitude'] as num).toDouble() + deltaLng,
        'generatedAt': FieldValue.serverTimestamp(),
        'basedOnPoints': points.length,
        'confidence': points.length == 3 ? 0.55 : 0.35,
      },
    }, SetOptions(merge: true));
  }

  Future<void> setOffline() async {
    if (!isTrackablePhone) {
      return;
    }

    try {
      final deviceId = await getDeviceId();
      await _devices.doc(deviceId).set({
        'status': {
          'isOnline': false,
          'offlineReason': 'app_closed_or_signed_out',
        },
        'lastHeartbeatAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
    } finally {
      unawaited(_stopBleAdvertising());
      unawaited(_setAlarmPlayback(false));
      unawaited(_backgroundChannel.invokeMethod('stopLostModeService'));
      _deviceListener?.cancel();
      _foregroundMessageSubscription?.cancel();
      _openedMessageSubscription?.cancel();
      _fcmTokenRefreshSubscription?.cancel();
      _locationTimer?.cancel();
    }
  }

  void dispose() {
    unawaited(_stopBleAdvertising());
    unawaited(_setAlarmPlayback(false));
    unawaited(_backgroundChannel.invokeMethod('stopLostModeService'));
    _deviceListener?.cancel();
    _foregroundMessageSubscription?.cancel();
    _openedMessageSubscription?.cancel();
    _fcmTokenRefreshSubscription?.cancel();
    _locationTimer?.cancel();
    unawaited(_alarmPlayer.dispose());
  }
}
