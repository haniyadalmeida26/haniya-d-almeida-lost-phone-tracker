import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../device_service.dart';
import '../ui_common.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    DeviceService().refreshDerivedState(widget.deviceId);
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      DeviceService().refreshDerivedState(widget.deviceId);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Text(
          '${widget.deviceName} History',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('devices')
            .doc(widget.deviceId)
            .snapshots(),
        builder: (context, deviceSnapshot) {
          if (!deviceSnapshot.hasData) {
            return const LoadingScaffold();
          }

          final device = deviceSnapshot.data?.data() ?? {};
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: HistorySummary(device: device),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const Text(
                      'Device Events',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('devices')
                          .doc(widget.deviceId)
                          .collection('events')
                          .orderBy('timestamp', descending: true)
                          .limit(20)
                          .snapshots(),
                      builder: (context, eventSnapshot) {
                        final events = eventSnapshot.data?.docs ?? [];
                        if (events.isEmpty) {
                          return _emptyCard(
                              'No Lost Mode or alarm events yet.');
                        }

                        return Column(
                          children: events
                              .map(
                                (doc) => _historyCard(
                                  title: doc.data()['type'] ?? 'event',
                                  line1: doc.data()['message'] ?? '',
                                  line2:
                                      formatTimestamp(doc.data()['timestamp']),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Location History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('devices')
                          .doc(widget.deviceId)
                          .collection('location_history')
                          .orderBy('timestamp', descending: true)
                          .limit(30)
                          .snapshots(),
                      builder: (context, snapshot) {
                        final locations = snapshot.data?.docs ?? [];
                        if (locations.isEmpty) {
                          return _emptyCard('No location history yet.');
                        }

                        return Column(
                          children: locations.map(
                            (doc) {
                              final data = doc.data();
                              final accuracy = asDouble(data['accuracy']);
                              return _historyCard(
                                title: data['source'] ?? 'location_update',
                                line1:
                                    'Location: ${formatCoordinates(data['latitude'], data['longitude'])} | Accuracy: ${accuracy == null ? 'unknown' : accuracy.toStringAsFixed(1)} m',
                                line2: formatTimestamp(data['timestamp']),
                              );
                            },
                          ).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Finder Detections',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('devices')
                          .doc(widget.deviceId)
                          .collection('detections')
                          .orderBy('timestamp', descending: true)
                          .limit(50)
                          .snapshots(),
                      builder: (context, snapshot) {
                        final detections = snapshot.data?.docs ?? [];
                        if (detections.isEmpty) {
                          return _emptyCard('No finder detections yet.');
                        }

                        return Column(
                          children: detections
                              .map(
                                (doc) => _historyCard(
                                  title: doc.data()['finderLabel'] ?? 'unknown',
                                  line1:
                                      'Location: ${formatCoordinates(doc.data()['latitude'], doc.data()['longitude'])} | Priority: ${doc.data()['priorityLabel'] ?? 'public_finder'}',
                                  line2:
                                      formatTimestamp(doc.data()['timestamp']),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Widget _emptyCard(String message) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      message,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
    ),
  );
}

Widget _historyCard({
  required String title,
  required String line1,
  required String line2,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          line1,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 4),
        Text(
          line2,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
      ],
    ),
  );
}

class HistorySummary extends StatelessWidget {
  const HistorySummary({
    super.key,
    required this.device,
  });

  final Map<String, dynamic> device;

  @override
  Widget build(BuildContext context) {
    final status = Map<String, dynamic>.from(device['status'] ?? {});
    final prediction = Map<String, dynamic>.from(device['prediction'] ?? {});
    final lastLocation =
        Map<String, dynamic>.from(device['lastLocation'] ?? {});
    final latestDetection =
        Map<String, dynamic>.from(device['latestDetection'] ?? {});

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tracking Summary',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Last seen: ${formatCoordinates(lastLocation['latitude'], lastLocation['longitude'])} '
            '• ${formatTimestamp(lastLocation['recordedAt'])}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 6),
          Text(
            'Online: ${status['isOnline'] == false ? 'No' : 'Yes'}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 6),
          Text(
            'Possible switch-off: ${status['possibleSwitchOff'] == true ? 'Yes' : 'No'}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 6),
          Text(
            'Disconnect hint: ${status['offlineReason'] ?? 'None'}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 6),
          Text(
            'Last finder detection: ${latestDetection.isEmpty ? 'Not available' : '${formatCoordinates(latestDetection['latitude'], latestDetection['longitude'])} • ${formatTimestamp(latestDetection['timestamp'])} • ${latestDetection['priorityLabel'] ?? 'public_finder'}'}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 6),
          Text(
            'Prediction: ${prediction.isEmpty ? 'Not available' : formatCoordinates(prediction['latitude'], prediction['longitude'])}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          ),
          if (prediction.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Prediction confidence: ${prediction['confidence'] ?? 'unknown'}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
            ),
          ],
        ],
      ),
    );
  }
}
