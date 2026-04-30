import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../device_service.dart';
import '../ui_common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegisterMode = false;
  bool _isLoading = false;
  String _errorMessage = '';

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter email and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (_isRegisterMode) {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        await FirebaseFirestore.instance
            .collection('users')
            .doc(credential.user!.uid)
            .set({
          'email': email,
          'name': email.split('@').first,
          'createdAt': FieldValue.serverTimestamp(),
          'devices': [],
        }, SetOptions(merge: true));
      } else {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
      }

      await DeviceService().initializeCurrentDevice();
    } on FirebaseAuthException catch (error) {
      setState(() {
        _errorMessage = switch (error.code) {
          'user-not-found' => 'No account found for that email.',
          'wrong-password' => 'Incorrect password.',
          'email-already-in-use' => 'Email already registered.',
          'weak-password' => 'Password must be at least 6 characters.',
          'invalid-email' => 'Please enter a valid email.',
          _ => error.message ?? 'Authentication failed.',
        };
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 24),
                SoftCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _previewCard(
                              title: 'Collection',
                              accent: AppPalette.sky,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      _MiniAvatar(color: AppPalette.pink),
                                      SizedBox(width: 6),
                                      _MiniAvatar(color: AppPalette.sky),
                                      SizedBox(width: 6),
                                      _MiniAvatar(color: AppPalette.lemon),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: const [
                                      _RoundAction(
                                        icon: Icons.wallet_rounded,
                                        color: AppPalette.primary,
                                      ),
                                      SizedBox(width: 8),
                                      _RoundAction(
                                        icon: Icons.send_rounded,
                                        color: AppPalette.peach,
                                      ),
                                      SizedBox(width: 8),
                                      _RoundAction(
                                        icon: Icons.more_horiz_rounded,
                                        color: AppPalette.sky,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _previewCard(
                              title: 'Share the vibe',
                              accent: AppPalette.lemon,
                              child: const Center(
                                child: _MoodStickerBoard(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _heroBanner(),
                      const SizedBox(height: 24),
                      Row(
                        children: const [
                          _LoginStatChip(
                            label: 'Live map',
                            color: AppPalette.sky,
                          ),
                          SizedBox(width: 10),
                          _LoginStatChip(
                            label: 'Alarm wake',
                            color: AppPalette.peach,
                          ),
                          SizedBox(width: 10),
                          _LoginStatChip(
                            label: 'AI hints',
                            color: AppPalette.mint,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SoftCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isRegisterMode ? 'Create account' : 'Welcome back',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 18),
                      _buildField(
                        label: 'Email',
                        controller: _emailController,
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        tint: AppPalette.sky,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        label: 'Password',
                        controller: _passwordController,
                        icon: Icons.lock_outline_rounded,
                        obscureText: true,
                        tint: AppPalette.pink,
                      ),
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppPalette.danger.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppPalette.danger.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Text(
                            _errorMessage,
                            style: const TextStyle(
                              color: AppPalette.danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  _isRegisterMode
                                      ? 'Create Account'
                                      : 'Sign In',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _isRegisterMode = !_isRegisterMode;
                              _errorMessage = '';
                            });
                          },
                          child: Text(
                            _isRegisterMode
                                ? 'Already have an account? Sign in'
                                : 'Need an account? Register',
                            style: const TextStyle(
                              color: AppPalette.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required Color tint,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppPalette.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(
            color: AppPalette.text,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: tint.withValues(alpha: 0.08),
            prefixIcon: Icon(icon, color: tint),
            hintStyle: const TextStyle(color: AppPalette.muted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubbleIcon({required Color color, required IconData icon}) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: AppPalette.text),
    );
  }

  Widget _heroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppPalette.primary, AppPalette.pink, AppPalette.peach],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _bubbleIcon(
                color: Colors.white.withValues(alpha: 0.22),
                icon: Icons.phone_iphone_rounded,
              ),
              const SizedBox(width: 12),
              _bubbleIcon(
                color: Colors.white.withValues(alpha: 0.22),
                icon: Icons.location_searching_rounded,
              ),
              const Spacer(),
              _bubbleIcon(
                color: Colors.white.withValues(alpha: 0.22),
                icon: Icons.notifications_active_rounded,
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Lost Phone Tracker',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _isRegisterMode
                ? 'Create your colorful control center and register this phone.'
                : 'Sign in to your playful dashboard and manage your tracked devices.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.90),
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewCard({
    required String title,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppPalette.text,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LoginStatChip extends StatelessWidget {
  const _LoginStatChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppPalette.text,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.pets_rounded, color: AppPalette.text.withValues(alpha: 0.78), size: 18),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _MoodStickerBoard extends StatelessWidget {
  const _MoodStickerBoard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 12,
            top: 18,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wb_cloudy_rounded, color: Colors.white),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppPalette.lemon,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wb_sunny_outlined, color: AppPalette.text),
            ),
          ),
          Positioned(
            right: 18,
            top: 18,
            child: Icon(
              Icons.favorite_outline_rounded,
              color: AppPalette.primary.withValues(alpha: 0.58),
            ),
          ),
          Positioned(
            left: 52,
            top: 28,
            child: Icon(
              Icons.music_note_rounded,
              color: AppPalette.pink.withValues(alpha: 0.70),
            ),
          ),
        ],
      ),
    );
  }
}
