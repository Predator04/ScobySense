import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../theme.dart';
import '../widgets/glass_card.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  String? _text;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/privacy.txt').then((v) {
      if (mounted) setState(() => _text = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: AppBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              child: _text == null
                  ? const SizedBox(
                      height: 80,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.accent)))
                  : SelectableText(
                      _text!,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppTheme.text,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
