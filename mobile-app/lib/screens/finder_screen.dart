import 'package:flutter/material.dart';

import '../device_service.dart';

class FinderScreen extends StatefulWidget {
  const FinderScreen({super.key});

  @override
  State<FinderScreen> createState() => _FinderScreenState();
}

class _FinderScreenState extends State<FinderScreen> {
  bool _isScanning = false;
  String _statusMessage =
      'Ready to scan for nearby lost phones using real Bluetooth.';

  Future<void> _startRealBleScan() async {
    setState(() {
      _isScanning = true;
      _statusMessage = 'Scanning for nearby lost phone beacons...';
    });

    final result = await DeviceService().scanForNearbyLostDevices();
    if (!mounted) {
      return;
    }

    setState(() {
      _isScanning = false;
      _statusMessage = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text(
          'Finder Scan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Real Bluetooth Detection',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Use this on another phone acting as a finder device. '
              'It scans for nearby lost-phone BLE beacons and uploads real detections to Firebase.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _statusMessage,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isScanning ? null : _startRealBleScan,
                child: _isScanning
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Start Real BLE Scan'),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Requirements: Bluetooth ON, location ON, permissions granted, and the lost phone must already be in Lost Mode.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ],
        ),
      ),
    );
  }
}
