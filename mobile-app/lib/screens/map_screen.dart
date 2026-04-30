import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../device_service.dart';
import '../ui_common.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng? _viewerLocation;
  bool _viewerLocationLoaded = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    DeviceService().refreshDerivedState(widget.deviceId);
    _loadViewerLocation();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      DeviceService().refreshDerivedState(widget.deviceId);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadViewerLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _viewerLocationLoaded = true);
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _viewerLocationLoaded = true);
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _viewerLocation = LatLng(position.latitude, position.longitude);
          _viewerLocationLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _viewerLocationLoaded = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Text(
          '${widget.deviceName} Map',
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
          final lastLocation =
              Map<String, dynamic>.from(device['lastLocation'] ?? {});
          final prediction =
              Map<String, dynamic>.from(device['prediction'] ?? {});
          final status = Map<String, dynamic>.from(device['status'] ?? {});

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('devices')
                .doc(widget.deviceId)
                .collection('detections')
                .orderBy('timestamp', descending: true)
                .limit(25)
                .snapshots(),
            builder: (context, detectionsSnapshot) {
              final markers = <Marker>[];
              LatLng initialTarget = const LatLng(20.5937, 78.9629);
              double? distanceFromViewerMeters;

              final lastLat = asDouble(lastLocation['latitude']);
              final lastLng = asDouble(lastLocation['longitude']);
              if (lastLat != null && lastLng != null) {
                initialTarget = LatLng(lastLat, lastLng);
                markers.add(
                  _mapMarker(
                    point: initialTarget,
                    color: Colors.lightBlueAccent,
                    icon: Icons.phone_android,
                    label: 'Last known phone location',
                  ),
                );
              }

              if (_viewerLocation != null) {
                markers.add(
                  _mapMarker(
                    point: _viewerLocation!,
                    color: Colors.greenAccent,
                    icon: Icons.my_location,
                    label: 'Your current location',
                  ),
                );

                if (lastLat != null && lastLng != null) {
                  distanceFromViewerMeters = Geolocator.distanceBetween(
                    _viewerLocation!.latitude,
                    _viewerLocation!.longitude,
                    lastLat,
                    lastLng,
                  );
                }
              }

              final predictionLat = asDouble(prediction['latitude']);
              final predictionLng = asDouble(prediction['longitude']);
              if (predictionLat != null && predictionLng != null) {
                markers.add(
                  _mapMarker(
                    point: LatLng(predictionLat, predictionLng),
                    color: Colors.orangeAccent,
                    icon: Icons.auto_awesome,
                    label: 'AI prediction',
                  ),
                );
              }

              for (final doc in detectionsSnapshot.data?.docs ?? []) {
                final data = doc.data();
                final lat = asDouble(data['latitude']);
                final lng = asDouble(data['longitude']);
                if (lat == null || lng == null) {
                  continue;
                }

                markers.add(
                  _mapMarker(
                    point: LatLng(lat, lng),
                    color: Colors.redAccent,
                    icon: Icons.bluetooth_searching,
                    label:
                        '${data['priorityLabel'] ?? 'public_finder'} | ${data['finderLabel'] ?? 'finder'}',
                  ),
                );
              }

              WidgetsBinding.instance.addPostFrameCallback((_) {
                _mapController.move(initialTarget, 16);
              });

              return Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialTarget,
                      initialZoom: 5,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.mobile',
                      ),
                      MarkerLayer(markers: markers),
                    ],
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 20,
                    child: MapLegend(
                      device: device,
                      status: status,
                      markerCount: markers.length,
                      viewerLocationLoaded: _viewerLocationLoaded,
                      viewerLocation: _viewerLocation,
                      distanceFromViewerMeters: distanceFromViewerMeters,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Marker _mapMarker({
    required LatLng point,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Marker(
      point: point,
      width: 72,
      height: 72,
      child: Tooltip(
        message: label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.black87, size: 22),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xCC161B22),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MapLegend extends StatelessWidget {
  const MapLegend({
    super.key,
    required this.device,
    required this.status,
    required this.markerCount,
    required this.viewerLocationLoaded,
    required this.viewerLocation,
    required this.distanceFromViewerMeters,
  });

  final Map<String, dynamic> device;
  final Map<String, dynamic> status;
  final int markerCount;
  final bool viewerLocationLoaded;
  final LatLng? viewerLocation;
  final double? distanceFromViewerMeters;

  @override
  Widget build(BuildContext context) {
    final lastLocation =
        Map<String, dynamic>.from(device['lastLocation'] ?? {});
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xF2161B22),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFF1A73E8).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${device['deviceName'] ?? 'Device'} overview',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Blue: last known phone GPS | Green: your location now | Red: finder detections | Orange: AI prediction',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
          const SizedBox(height: 6),
          Text(
            'Status: ${status['isOnline'] == false ? 'offline' : 'online'} | Markers on map: $markerCount',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
          const SizedBox(height: 6),
          Text(
            'Last seen: ${formatCoordinates(lastLocation['latitude'], lastLocation['longitude'])} at ${formatTimestamp(lastLocation['recordedAt'])}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
          const SizedBox(height: 6),
          Text(
            viewerLocation == null
                ? (viewerLocationLoaded
                    ? 'Your current location: unavailable'
                    : 'Your current location: loading...')
                : 'Your current location: ${viewerLocation!.latitude.toStringAsFixed(5)}, ${viewerLocation!.longitude.toStringAsFixed(5)}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
          const SizedBox(height: 6),
          Text(
            'Distance from you to last seen point: ${formatDistanceMeters(distanceFromViewerMeters)}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
          const SizedBox(height: 6),
          Text(
            'Offline reason: ${status['offlineReason'] ?? 'None'}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
        ],
      ),
    );
  }
}
