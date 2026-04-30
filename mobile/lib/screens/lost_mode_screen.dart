import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../ui_common.dart';

class LostModeScreen extends StatelessWidget {
  const LostModeScreen({
    super.key,
    required this.deviceId,
    required this.deviceStream,
  });

  final String deviceId;
  final Stream<DocumentSnapshot<Map<String, dynamic>>> deviceStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: deviceStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoadingScaffold();
        }

        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final status = Map<String, dynamic>.from(data['status'] ?? {});
        final lastLocation =
            Map<String, dynamic>.from(data['lastLocation'] ?? {});
        final isAlarmActive = status['alarmActive'] == true;
        final isOnline = status['isOnline'] != false;

        return Scaffold(
          body: AppBackdrop(
            isDanger: true,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF4A0000),
                            Color(0xFFB1001C),
                            Color(0xFFFF142E),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: AppPalette.danger.withValues(alpha: 0.34),
                            blurRadius: 40,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(24),
                            ),
                          child: const Icon(
                              Icons.gpp_bad_rounded,
                              color: Colors.white,
                              size: 38,
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'LOST MODE IS ON',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'This screen is intentionally intense and dangerous-looking so the emergency state is impossible to miss. Tracking and recovery actions stay active until the controller marks the phone found.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.84),
                              height: 1.45,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        const StatusChip(
                          label: 'LOST MODE ACTIVE',
                          color: Colors.white,
                        ),
                        StatusChip(
                          label: isAlarmActive ? 'ALARM ON' : 'ALARM OFF',
                          color: Colors.white,
                        ),
                        StatusChip(
                          label: isOnline ? 'DEVICE ONLINE' : 'DEVICE OFFLINE',
                          color: Colors.white,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _dangerCard(
                      title: 'Owner Message',
                      body:
                          'If you found this phone, keep it powered and connected. The owner is actively trying to recover it.',
                    ),
                    const SizedBox(height: 14),
                    _dangerCard(
                      title: 'Live Tracking',
                      body:
                          'Last known location: ${formatCoordinates(lastLocation['latitude'], lastLocation['longitude'])}\nUpdated: ${formatTimestamp(lastLocation['recordedAt'])}',
                    ),
                    const SizedBox(height: 14),
                    _dangerCard(
                      title: 'Recovery Status',
                      body:
                          'Device ID: $deviceId\nAlarm: ${isAlarmActive ? 'Active' : 'Waiting'}\nController must mark this phone found to exit Lost Mode.',
                    ),
                    const Spacer(),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Text(
                        'The phone will return to the normal soft theme automatically when the controller clears Lost Mode.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dangerCard({required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
