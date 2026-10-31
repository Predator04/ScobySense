import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/demo_mode.dart';
import '../services/prefs.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import 'devices_screen.dart';
import 'login_screen.dart';

/// First-run selector shown when the user is signed out and hasn't completed
/// onboarding before. Offers "I have a device, sign in" vs "Look around in
/// demo mode" with a one-line explanation of each.
class OnboardingScreen extends StatelessWidget {
  final AuthService auth;
  final UpdateService updater;
  const OnboardingScreen({super.key, required this.auth, required this.updater});

  Future<void> _goLogin(BuildContext context) async {
    await AppPrefs.setOnboarded(true);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LoginScreen(auth: auth, updater: updater),
    ));
  }

  Future<void> _goDemo(BuildContext context) async {
    await AppPrefs.setOnboarded(true);
    DemoMode.active = true;
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => DevicesScreen(auth: auth, updater: updater),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(colors: [
                          AppTheme.accent,
                          AppTheme.accent2,
                        ]),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accent.withValues(alpha: 0.35),
                            blurRadius: 24,
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.local_drink,
                          color: Color(0xFF04070A), size: 36),
                    ),
                    const SizedBox(height: 20),
                    const Text('Welcome to ScobySense',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text(
                      'Community kombucha brewer companion.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textDim),
                    ),
                    const SizedBox(height: 28),
                    GlassCard(
                      onTap: () => _goLogin(context),
                      child: Row(
                        children: [
                          _IconBubble(
                              icon: Icons.login, color: AppTheme.accent),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('I have a Fermenstation',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                                SizedBox(height: 4),
                                Text(
                                  'Sign in with the account from the official app to see live device state.',
                                  style: TextStyle(
                                      color: AppTheme.textDim, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: AppTheme.textDim),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      onTap: () => _goDemo(context),
                      child: Row(
                        children: [
                          _IconBubble(
                              icon: Icons.play_circle_outline,
                              color: AppTheme.accent2),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Look around in demo mode',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                                SizedBox(height: 4),
                                Text(
                                  'No account needed. Shows sample devices, recipes, and history so you can explore the UI.',
                                  style: TextStyle(
                                      color: AppTheme.textDim, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: AppTheme.textDim),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBubble({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
