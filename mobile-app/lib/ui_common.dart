import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AppPalette {
  static const Color background = Color(0xFFF9F7FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF251B4A);
  static const Color muted = Color(0xFF7D78A6);
  static const Color border = Color(0xFFE7E0FF);
  static const Color primary = Color(0xFF7C5CFF);
  static const Color peach = Color(0xFFFFA47B);
  static const Color mint = Color(0xFF69E7C8);
  static const Color lemon = Color(0xFFFFD969);
  static const Color sky = Color(0xFF85C8FF);
  static const Color pink = Color(0xFFFF8FC7);
  static const Color danger = Color(0xFFE6405C);
  static const Color dangerDark = Color(0xFF9B102C);
}

class LoadingScaffold extends StatelessWidget {
  const LoadingScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFFBFF), Color(0xFFF3EEFF), Color(0xFFFFF1E7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppPalette.primary),
        ),
      ),
    );
  }
}

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({
    super.key,
    required this.child,
    this.isDanger = false,
  });

  final Widget child;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final colors = isDanger
        ? const [
            Color(0xFFFFE5EA),
            Color(0xFFFFA5B4),
            Color(0xFFFF3A58),
          ]
        : const [
            Color(0xFFFFFBFF),
            Color(0xFFF4EFFF),
            Color(0xFFFFF1E8),
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            left: -20,
            child: _bubble(
              size: 180,
              color: (isDanger ? AppPalette.danger : AppPalette.lemon)
                  .withValues(alpha: 0.18),
            ),
          ),
          Positioned(
            top: 110,
            right: -30,
            child: _bubble(
              size: 160,
              color: (isDanger ? AppPalette.pink : AppPalette.sky)
                  .withValues(alpha: 0.22),
            ),
          ),
          Positioned(
            bottom: -60,
            left: 30,
            child: _bubble(
              size: 200,
              color: (isDanger ? AppPalette.peach : AppPalette.mint)
                  .withValues(alpha: 0.18),
            ),
          ),
          if (!isDanger) ...[
            const Positioned(
              top: 48,
              left: 260,
              child: DecorativeFlower(
                size: 90,
                petalColors: [
                  AppPalette.peach,
                  AppPalette.lemon,
                  AppPalette.sky,
                  AppPalette.pink,
                ],
              ),
            ),
            const Positioned(
              top: 210,
              right: 120,
              child: DecorativeFlower(
                size: 74,
                petalColors: [
                  AppPalette.mint,
                  AppPalette.sky,
                  AppPalette.lemon,
                  AppPalette.primary,
                ],
              ),
            ),
            Positioned(
              bottom: 90,
              right: 34,
              child: _stickerCard(
                width: 120,
                height: 86,
                color: AppPalette.pink.withValues(alpha: 0.18),
                icon: Icons.auto_awesome,
              ),
            ),
            Positioned(
              bottom: 160,
              left: 26,
              child: _stickerCard(
                width: 104,
                height: 74,
                color: AppPalette.sky.withValues(alpha: 0.2),
                icon: Icons.layers_rounded,
              ),
            ),
          ] else ...[
            Positioned(
              top: 80,
              left: 40,
              child: _warningBurst(
                color: Colors.white.withValues(alpha: 0.14),
                icon: Icons.warning_amber_rounded,
              ),
            ),
            Positioned(
              top: 180,
              right: 36,
              child: _warningBurst(
                color: Colors.black.withValues(alpha: 0.18),
                icon: Icons.notifications_active_rounded,
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }

  Widget _bubble({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 2),
      ),
    );
  }

  Widget _stickerCard({
    required double width,
    required double height,
    required Color color,
    required IconData icon,
  }) {
    return Transform.rotate(
      angle: -0.1,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        ),
        child: Icon(icon, color: AppPalette.text.withValues(alpha: 0.7)),
      ),
    );
  }

  Widget _warningBurst({required Color color, required IconData icon}) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Icon(icon, color: Colors.white, size: 34),
    );
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = AppPalette.surface,
    this.borderColor = AppPalette.border,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: AppPalette.primary.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class FoundCelebrationOverlay extends StatefulWidget {
  const FoundCelebrationOverlay({super.key});

  @override
  State<FoundCelebrationOverlay> createState() => _FoundCelebrationOverlayState();
}

class _FoundCelebrationOverlayState extends State<FoundCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final curve = Curves.easeOutBack.transform(_controller.value);
          final fade = Curves.easeOut.transform(
            (_controller.value < 0.8 ? _controller.value / 0.8 : 1.0)
                .clamp(0.0, 1.0),
          );

          return Opacity(
            opacity: 1 - (_controller.value * 0.25),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.22 * fade),
                  ),
                ),
                Positioned(
                  left: -90 + (160 * curve),
                  top: 120,
                  child: _burst(
                    colors: const [
                      AppPalette.peach,
                      AppPalette.primary,
                      AppPalette.mint,
                    ],
                  ),
                ),
                Positioned(
                  right: -90 + (160 * curve),
                  top: 180,
                  child: Transform.rotate(
                    angle: math.pi,
                    child: _burst(
                      colors: const [
                        AppPalette.pink,
                        AppPalette.sky,
                        AppPalette.lemon,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: -120 + (210 * curve),
                  bottom: 170,
                  child: Transform.rotate(
                    angle: -0.18,
                    child: _partyPopper(
                      colors: const [
                        AppPalette.primary,
                        AppPalette.sky,
                        AppPalette.mint,
                        AppPalette.lemon,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: -120 + (210 * curve),
                  bottom: 120,
                  child: Transform.rotate(
                    angle: math.pi + 0.18,
                    child: _partyPopper(
                      colors: const [
                        AppPalette.peach,
                        AppPalette.pink,
                        AppPalette.primary,
                        AppPalette.lemon,
                      ],
                    ),
                  ),
                ),
                Center(
                  child: Transform.scale(
                    scale: 0.8 + (0.2 * curve),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppPalette.pink.withValues(alpha: 0.22),
                            blurRadius: 30,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Device Found',
                            style: TextStyle(
                              color: AppPalette.text,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Lost Mode is cleared and recovery is complete.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppPalette.muted,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _burst({required List<Color> colors}) {
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        children: [
          for (int i = 0; i < colors.length; i++)
            Positioned(
              left: 20.0 * i,
              top: 24.0 * i,
              child: Container(
                width: 90 - (i * 8),
                height: 90 - (i * 8),
                decoration: BoxDecoration(
                  color: colors[i].withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          Positioned(
            left: 54,
            top: 54,
            child: Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _partyPopper({required List<Color> colors}) {
    return SizedBox(
      width: 170,
      height: 110,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 8,
            child: Container(
              width: 54,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppPalette.text, AppPalette.primary],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          for (int i = 0; i < colors.length; i++)
            Positioned(
              left: 34 + (i * 24),
              top: 10 + (i.isEven ? 0 : 16),
              child: Transform.rotate(
                angle: -0.8 + (i * 0.28),
                child: Container(
                  width: 54,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colors[i],
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          for (int i = 0; i < colors.length; i++)
            Positioned(
              left: 72 + (i * 16),
              top: 44 - (i * 8),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DecorativeFlower extends StatelessWidget {
  const DecorativeFlower({
    super.key,
    required this.size,
    required this.petalColors,
  });

  final double size;
  final List<Color> petalColors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < petalColors.length; i++)
            Transform.rotate(
              angle: (math.pi / 2) * i,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: size * 0.34,
                  height: size * 0.50,
                  decoration: BoxDecoration(
                    color: petalColors[i].withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(size),
                  ),
                ),
              ),
            ),
          Container(
            width: size * 0.30,
            height: size * 0.30,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

double? asDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

String formatCoordinates(dynamic latitude, dynamic longitude) {
  final lat = asDouble(latitude);
  final lng = asDouble(longitude);
  if (lat == null || lng == null) {
    return 'Unknown';
  }
  return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

String formatTimestamp(dynamic value) {
  if (value is Timestamp) {
    final dt = value.toDate().toLocal();
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  return 'Unknown time';
}

String formatDistanceMeters(double? meters) {
  if (meters == null) {
    return 'Unknown';
  }
  if (meters < 1000) {
    return '${meters.toStringAsFixed(0)} m';
  }
  return '${(meters / 1000).toStringAsFixed(2)} km';
}

extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
