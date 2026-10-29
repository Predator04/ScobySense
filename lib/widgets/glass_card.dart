import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';

class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool lifted;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.onTap,
    this.lifted = true,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: _pressed ? 0.05 : 0.09),
                Colors.white.withValues(alpha: _pressed ? 0.02 : 0.045),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );

    final shadowed = widget.lifted
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _pressed ? 0.25 : 0.45),
                  blurRadius: _pressed ? 10 : 24,
                  spreadRadius: -4,
                  offset: Offset(0, _pressed ? 4 : 12),
                ),
                BoxShadow(
                  color:
                      KombuTheme.accent.withValues(alpha: _pressed ? 0.02 : 0.05),
                  blurRadius: 30,
                  spreadRadius: -8,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: content,
          )
        : content;

    if (widget.onTap == null) return shadowed;
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        scale: _pressed ? 0.985 : 1.0,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.radius),
          onTap: widget.onTap,
          child: shadowed,
        ),
      ),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  final String message;
  const OfflineBanner({super.key, required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: KombuTheme.accent2.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 16, color: KombuTheme.accent2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: KombuTheme.accent2, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class InlineErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const InlineErrorCard({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.error_outline, color: KombuTheme.danger, size: 18),
            SizedBox(width: 8),
            Text('Something went wrong',
                style: TextStyle(
                    color: KombuTheme.danger, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Text(message, style: const TextStyle(color: KombuTheme.textDim)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
