import 'package:flutter/material.dart';
import '../services/prefs.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

/// Terms & Disclaimer screen.
///
/// Two modes:
///  - `requireAccept: true` (first launch) — blocks back navigation and
///    exposes an "I accept" button that persists acceptance and pops `true`.
///  - `requireAccept: false` (opened from Settings) — read-only, back button
///    enabled, no accept button.
class TermsScreen extends StatelessWidget {
  final bool requireAccept;
  const TermsScreen({super.key, this.requireAccept = false});

  static const List<_Point> _points = [
    _Point(
      Icons.flag_outlined,
      'Unofficial third-party app',
      'ScobySense is a community-built client. It is NOT affiliated with, '
          'endorsed by, or supported by the device manufacturer. All product '
          'names, logos, and trademarks belong to their respective owners. '
          'Please do not contact them for help with it.',
    ),
    _Point(
      Icons.shield_outlined,
      'Provided "AS IS" — no warranty',
      'The app is provided "AS IS", with NO warranty of any kind — express '
          'or implied — including no warranty of merchantability, fitness for '
          'a particular purpose, non-infringement, or that it will work at '
          'all.',
    ),
    _Point(
      Icons.gavel_outlined,
      'No liability — use entirely at your own risk',
      'To the fullest extent permitted by law, the app and its creator(s) '
          'accept NO responsibility or liability for any damage to your '
          'device, spoiled or ruined batches, property damage, personal '
          'injury, lost data, or any other loss — including direct, indirect, '
          'incidental, consequential, special, exemplary, or punitive '
          'damages — arising from your use of the app. You use ScobySense '
          'entirely at your own risk.',
    ),
    _Point(
      Icons.handshake_outlined,
      'You agree to indemnify the creator(s)',
      'You agree to indemnify, defend, and hold harmless the app\'s '
          'creator(s) and contributors from any and all claims, damages, '
          'losses, liabilities, costs, and expenses (including reasonable '
          'legal fees) arising out of or related to your use of the app, '
          'your batches, or your violation of these terms.',
    ),
    _Point(
      Icons.account_circle_outlined,
      'You take responsibility for your use',
      'You accept full responsibility for how you use this app and its '
          'control features.',
    ),
    _Point(
      Icons.warning_amber,
      'F2 (carbonation) builds pressure',
      'Carbonation creates pressure inside bottles — over-carbonated bottles '
          'can burst. Follow safe carbonation practices: burp bottles, use '
          'pressure-rated vessels, and watch F2 duration carefully.',
    ),
    _Point(
      Icons.biotech_outlined,
      'Fermentation is a live-food process',
      'Spoiled or contaminated batches should be discarded. Follow safe '
          'fermentation practices and do not drink anything you suspect is '
          'unsafe.',
    ),
    _Point(
      Icons.medical_services_outlined,
      'No health claims — not medical advice',
      'The app is not medical advice and makes NO claims to diagnose, treat, '
          'cure, or prevent any disease or condition. Statements about '
          'kombucha or fermentation have not been evaluated by any health '
          'authority. Consult a qualified professional for medical questions.',
    ),
    _Point(
      Icons.local_fire_department,
      'The machine heats during brewing',
      'Do not tamper with or bypass the machine\'s built-in safety features.',
    ),
    _Point(
      Icons.thermostat_auto,
      'No temperature control',
      'This app does NOT control fermentation temperature (the official app '
          'does not either). It monitors temperature only.',
    ),
    _Point(
      Icons.vpn_key_outlined,
      'Your account is your responsibility',
      'You are responsible for your own account credentials, for '
          'keeping them secure, and for all activity under your account. You '
          'must also comply with the device manufacturer\'s own terms of '
          'service.',
    ),
    _Point(
      Icons.cloud_queue,
      'Dependent on the device backend',
      'ScobySense talks to the device backend. If it changes, throttles, or '
          'revokes access, the app may stop working at any time without '
          'notice, and the creator(s) have no obligation to restore service.',
    ),
    _Point(
      Icons.verified_user_outlined,
      'Personal, non-commercial use — 18+',
      'ScobySense is for personal, non-commercial use only. You must be at '
          'least 18 years of age, or the age of majority in your '
          'jurisdiction, to use the app.',
    ),
    _Point(
      Icons.balance,
      'Governing law — Nevada, USA',
      'These terms are governed by the laws of the State of Nevada, USA, '
          'without regard to its conflict-of-laws rules. Exclusive venue for '
          'any dispute lies in the state or federal courts located in Clark '
          'County, Nevada.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !requireAccept,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Terms & Disclaimer'),
          automaticallyImplyLeading: !requireAccept,
        ),
        body: AppBackground(
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: AppTheme.accent, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text('Before you use ScobySense',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15)),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                                'Please read these points. By continuing you '
                                'confirm you understand and accept them.',
                                style: TextStyle(
                                    color: AppTheme.textDim, fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final p in _points) ...[
                        GlassCard(child: _PointRow(p)),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                if (requireAccept)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await AppPrefs.setTermsAccepted(true);
                            if (!context.mounted) return;
                            Navigator.of(context).pop(true);
                          },
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('I accept — continue'),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Point {
  final IconData icon;
  final String title;
  final String body;
  const _Point(this.icon, this.title, this.body);
}

class _PointRow extends StatelessWidget {
  final _Point p;
  const _PointRow(this.p);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: AppTheme.accent.withValues(alpha: 0.12),
            border:
                Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
          ),
          child: Icon(p.icon, size: 18, color: AppTheme.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 4),
              Text(p.body,
                  style: const TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 13,
                      height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
