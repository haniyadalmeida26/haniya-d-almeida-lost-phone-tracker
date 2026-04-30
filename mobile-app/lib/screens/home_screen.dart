import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../device_service.dart';
import '../ui_common.dart';
import 'finder_screen.dart';
import 'history_screen.dart';
import 'map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DeviceService _deviceService = DeviceService();
  final TextEditingController _trustedEmailController = TextEditingController();
  Timer? _refreshTimer;
  Timer? _celebrationTimer;
  String _userName = '';
  String? _currentDeviceId;
  String? _selectedDeviceId;
  bool _isBusy = false;
  bool _showFoundCelebration = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _celebrationTimer?.cancel();
    _trustedEmailController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _deviceService.initializeCurrentDevice();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final deviceId = await _deviceService.getCurrentTrackedDeviceIdOrNull();
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    if (!mounted) return;

    setState(() {
      _currentDeviceId = deviceId;
      _selectedDeviceId = deviceId;
      _userName =
          userDoc.data()?['name'] ?? user.email?.split('@').first ?? 'User';
    });

    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      final selectedDeviceId = _selectedDeviceId;
      if (selectedDeviceId != null) {
        await _deviceService.refreshDerivedState(selectedDeviceId);
      }
    });
  }

  Future<void> _toggleLostMode(bool isLost) async {
    final selectedDeviceId = _selectedDeviceId;
    if (selectedDeviceId == null) return;

    setState(() => _isBusy = true);
    await _deviceService.setLostModeForDevice(selectedDeviceId, isLost);
    await _deviceService.refreshDerivedState(selectedDeviceId);
    if (!mounted) return;

    if (!isLost) {
      setState(() => _showFoundCelebration = true);
      _celebrationTimer?.cancel();
      _celebrationTimer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) setState(() => _showFoundCelebration = false);
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLost ? AppPalette.danger : AppPalette.primary,
        content: Text(
          isLost
              ? 'Selected device marked as LOST.'
              : 'Selected device marked as FOUND.',
        ),
      ),
    );
    setState(() => _isBusy = false);
  }

  Future<void> _simulateDetection() async {
    final selectedDeviceId = _selectedDeviceId;
    if (selectedDeviceId == null) return;
    setState(() => _isBusy = true);
    final message =
        await _deviceService.simulateFinderDetectionForDevice(selectedDeviceId);
    await _deviceService.refreshDerivedState(selectedDeviceId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppPalette.primary,
        content: Text(message),
      ),
    );
    setState(() => _isBusy = false);
  }

  Future<void> _stopAlarm() async {
    final selectedDeviceId = _selectedDeviceId;
    if (selectedDeviceId == null) return;
    setState(() => _isBusy = true);
    await _deviceService.clearAlarmForDevice(selectedDeviceId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppPalette.peach,
        content: Text('Alarm stop command sent.'),
      ),
    );
    setState(() => _isBusy = false);
  }

  Future<void> _signOut() async {
    await _deviceService.setOffline();
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _addTrustedFinderEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = _trustedEmailController.text.trim().toLowerCase();
    if (user == null || email.isEmpty) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'trustedFinderEmails': FieldValue.arrayUnion([email]),
    }, SetOptions(merge: true));

    if (!mounted) return;
    _trustedEmailController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppPalette.mint,
        content: Text('$email added as trusted finder contact.'),
      ),
    );
  }

  Future<void> _removeTrustedFinderEmail(String email) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'trustedFinderEmails': FieldValue.arrayRemove([email]),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoadingScaffold();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Lost Phone Tracker',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppPalette.border),
            ),
            child: IconButton(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded),
            ),
          ),
        ],
      ),
      body: AppBackdrop(
        child: Stack(
          children: [
            _body(user),
            if (_showFoundCelebration) const FoundCelebrationOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _body(User user) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('devices')
          .where('userId', isEqualTo: user.uid)
          .where('role', isEqualTo: 'tracked_phone')
          .snapshots(),
      builder: (context, devicesSnapshot) {
        if (devicesSnapshot.connectionState == ConnectionState.waiting &&
            !devicesSnapshot.hasData) {
          return const LoadingScaffold();
        }

        final devices = devicesSnapshot.data?.docs ?? [];
        if (devices.isNotEmpty &&
            (_selectedDeviceId == null ||
                !devices.any((doc) => doc.id == _selectedDeviceId))) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedDeviceId = devices.first.id);
          });
        }

        final selectedDoc = _selectedDeviceId == null
            ? null
            : devices.where((doc) => doc.id == _selectedDeviceId).firstOrNull;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _welcomeHeader(user.email ?? ''),
              const SizedBox(height: 20),
              if (selectedDoc != null)
                SelectedDevicePanel(
                  device: selectedDoc.data(),
                  deviceId: selectedDoc.id,
                  isCurrentDevice: selectedDoc.id == _currentDeviceId,
                  isBusy: _isBusy,
                  onActivateLostMode: () => _toggleLostMode(true),
                  onDeactivateLostMode: () => _toggleLostMode(false),
                  onSimulateDetection: _simulateDetection,
                  onStopAlarm: _stopAlarm,
                  onOpenMap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapScreen(
                        deviceId: selectedDoc.id,
                        deviceName:
                            selectedDoc.data()['deviceName'] ?? selectedDoc.id,
                      ),
                    ),
                  ),
                  onOpenHistory: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HistoryScreen(
                        deviceId: selectedDoc.id,
                        deviceName:
                            selectedDoc.data()['deviceName'] ?? selectedDoc.id,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              const Text(
                'My Devices',
                style: TextStyle(
                  color: AppPalette.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              if (devices.isEmpty)
                _infoCard('No devices registered yet.')
              else
                Column(
                  children: devices
                      .map(
                        (doc) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DeviceCard(
                            deviceId: doc.id,
                            data: doc.data(),
                            isCurrentDevice: doc.id == _currentDeviceId,
                            isSelected: doc.id == _selectedDeviceId,
                            onTap: () async {
                              setState(() => _selectedDeviceId = doc.id);
                              await _deviceService.refreshDerivedState(doc.id);
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 22),
              if (_deviceService.isControllerClient)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .snapshots(),
                  builder: (context, userSnapshot) {
                    final trustedEmails = List<String>.from(
                      userSnapshot.data?.data()?['trustedFinderEmails'] ??
                          const <String>[],
                    );
                    return _trustedContactsCard(trustedEmails);
                  },
                ),
              if (!_deviceService.isControllerClient) ...[
                const Text(
                  'Finder Tools',
                  style: TextStyle(
                    color: AppPalette.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                SoftCard(
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FinderScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPalette.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        'Open Real BLE Finder Scan',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              _infoCard(
                _deviceService.isControllerClient
                    ? 'This browser is your soft control dashboard. It does not register itself as a lost-phone device.'
                    : 'This phone is the real tracked device. Lost Mode switches it into fast tracking and alarm recovery actions.',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _welcomeHeader(String email) {
    return SoftCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _dot(AppPalette.sky),
                        const SizedBox(width: 8),
                        _dot(AppPalette.lemon),
                        const SizedBox(width: 8),
                        _dot(AppPalette.pink),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Hello, $_userName',
                      style: const TextStyle(
                        color: AppPalette.text,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      email,
                      style: const TextStyle(
                        color: AppPalette.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Soft dashboard mode',
                        style: TextStyle(
                          color: AppPalette.text,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppPalette.pink.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: const [
                          Expanded(
                            child: _PreviewAction(
                              icon: Icons.map_rounded,
                              label: 'Map',
                              color: AppPalette.sky,
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _PreviewAction(
                              icon: Icons.notifications_active_rounded,
                              label: 'Alarm',
                              color: AppPalette.peach,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Share the vibe',
                                style: TextStyle(
                                  color: AppPalette.text,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: AppPalette.primary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
      );

  Widget _infoCard(String message) {
    return SoftCard(
      child: Text(
        message,
        style: const TextStyle(
          color: AppPalette.muted,
          height: 1.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _trustedContactsCard(List<String> trustedEmails) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trusted Finder Contacts',
            style: TextStyle(
              color: AppPalette.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Trusted emails are prioritized first when their phones detect your lost device.',
            style: TextStyle(
              color: AppPalette.muted,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _trustedEmailController,
                  decoration: InputDecoration(
                    hintText: 'friend@example.com',
                    hintStyle: const TextStyle(color: AppPalette.muted),
                    filled: true,
                    fillColor: AppPalette.sky.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _addTrustedFinderEmail,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (trustedEmails.isEmpty)
            const Text(
              'No trusted finder contacts added yet.',
              style: TextStyle(
                color: AppPalette.muted,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: trustedEmails
                  .map(
                    (email) => InputChip(
                      label: Text(email),
                      onDeleted: () => _removeTrustedFinderEmail(email),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class SelectedDevicePanel extends StatelessWidget {
  const SelectedDevicePanel({
    super.key,
    required this.device,
    required this.deviceId,
    required this.isCurrentDevice,
    required this.isBusy,
    required this.onActivateLostMode,
    required this.onDeactivateLostMode,
    required this.onSimulateDetection,
    required this.onStopAlarm,
    required this.onOpenMap,
    required this.onOpenHistory,
  });

  final Map<String, dynamic> device;
  final String deviceId;
  final bool isCurrentDevice;
  final bool isBusy;
  final VoidCallback onActivateLostMode;
  final VoidCallback onDeactivateLostMode;
  final VoidCallback onSimulateDetection;
  final VoidCallback onStopAlarm;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final status = Map<String, dynamic>.from(device['status'] ?? {});
    final isLost = status['isLost'] == true;
    final isOnline = status['isOnline'] != false;
    final lastLocation = Map<String, dynamic>.from(device['lastLocation'] ?? {});
    final prediction = Map<String, dynamic>.from(device['prediction'] ?? {});
    final latestDetection =
        Map<String, dynamic>.from(device['latestDetection'] ?? {});
    final alarmActive = status['alarmActive'] == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLost
              ? const [Color(0xFFFFDEE5), Color(0xFFFFAABA), Color(0xFFE6405C)]
              : const [Colors.white, Color(0xFFFFF5F0), Color(0xFFF1F3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isLost
              ? AppPalette.danger.withValues(alpha: 0.20)
              : AppPalette.border,
        ),
        boxShadow: [
          BoxShadow(
            color: (isLost ? AppPalette.danger : AppPalette.primary)
                .withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device['deviceName'] ?? deviceId,
                      style: TextStyle(
                        color: isLost ? Colors.white : AppPalette.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isCurrentDevice
                          ? 'Tracked phone with live Lost Mode logic'
                          : 'Remote tracked phone controlled from this dashboard',
                      style: TextStyle(
                        color: isLost
                            ? Colors.white.withValues(alpha: 0.82)
                            : AppPalette.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: isOnline ? 'ONLINE' : 'OFFLINE',
                color: isOnline
                    ? (isLost ? Colors.white : AppPalette.mint)
                    : (isLost ? Colors.white : AppPalette.peach),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              StatusChip(
                label: isLost ? 'LOST MODE ACTIVE' : 'SAFE',
                color: isLost ? Colors.white : AppPalette.primary,
              ),
              if (alarmActive)
                StatusChip(
                  label: 'ALARM ACTIVE',
                  color: isLost ? Colors.white : AppPalette.danger,
                ),
            ],
          ),
          const SizedBox(height: 18),
          _tile(
            'Last known location',
            '${formatCoordinates(lastLocation['latitude'], lastLocation['longitude'])}\n${formatTimestamp(lastLocation['recordedAt'])}',
            isLost,
          ),
          const SizedBox(height: 12),
          _tile(
            'Last finder detection',
            latestDetection.isEmpty
                ? 'No network detections yet'
                : '${formatCoordinates(latestDetection['latitude'], latestDetection['longitude'])}\n${formatTimestamp(latestDetection['timestamp'])} • ${latestDetection['priorityLabel'] ?? 'public_finder'}',
            isLost,
          ),
          const SizedBox(height: 12),
          _tile(
            'AI prediction',
            prediction.isEmpty
                ? 'Not enough movement history yet'
                : '${formatCoordinates(prediction['latitude'], prediction['longitude'])}\nconfidence ${prediction['confidence']}',
            isLost,
          ),
          const SizedBox(height: 12),
          _tile(
            'Recovery status',
            'Offline reason: ${status['offlineReason']?.toString() ?? 'No issue detected'}\nRemote alarm: ${alarmActive ? 'Alarm command is ON' : 'Alarm command is OFF'}',
            isLost,
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton(
                onPressed: isBusy
                    ? null
                    : (isLost ? onDeactivateLostMode : onActivateLostMode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLost ? Colors.white : AppPalette.primary,
                  foregroundColor: isLost ? AppPalette.danger : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                child: Text(isLost ? 'Mark Found' : 'Mark Lost'),
              ),
              _action('Simulate Finder Detection', onSimulateDetection, isLost),
              if (alarmActive) _action('Stop Alarm', onStopAlarm, isLost),
              _action('Open Map', onOpenMap, isLost),
              _action('Open History', onOpenHistory, isLost),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(String title, String value, bool isLost) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLost
            ? Colors.white.withValues(alpha: 0.12)
            : AppPalette.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color:
                  isLost ? Colors.white.withValues(alpha: 0.84) : AppPalette.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: isLost ? Colors.white : AppPalette.text,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(String label, VoidCallback onPressed, bool isLost) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: isLost ? Colors.white : AppPalette.text,
        side: BorderSide(
          color: isLost
              ? Colors.white.withValues(alpha: 0.34)
              : AppPalette.border,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.deviceId,
    required this.data,
    required this.isCurrentDevice,
    required this.isSelected,
    required this.onTap,
  });

  final String deviceId;
  final Map<String, dynamic> data;
  final bool isCurrentDevice;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = Map<String, dynamic>.from(data['status'] ?? {});
    final isLost = status['isLost'] == true;
    final isOnline = status['isOnline'] != false;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: SoftCard(
        color: isSelected
            ? AppPalette.primary.withValues(alpha: 0.10)
            : AppPalette.surface,
        borderColor: isSelected ? AppPalette.primary : AppPalette.border,
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: (isLost ? AppPalette.peach : AppPalette.mint)
                    .withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                isLost ? Icons.location_off_rounded : Icons.smartphone_rounded,
                color: isLost ? AppPalette.danger : AppPalette.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['deviceName'] ?? deviceId,
                    style: const TextStyle(
                      color: AppPalette.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCurrentDevice
                        ? 'Current device • ${isOnline ? 'online' : 'offline'}'
                        : 'Remote device • ${isOnline ? 'online' : 'offline'}',
                    style: const TextStyle(
                      color: AppPalette.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            StatusChip(
              label: isLost ? 'LOST' : 'SAFE',
              color: isLost ? AppPalette.danger : AppPalette.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewAction extends StatelessWidget {
  const _PreviewAction({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppPalette.text,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
