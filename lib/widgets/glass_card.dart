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
                      AppTheme.accent.withValues(alpha: _pressed ? 0.02 : 0.05),
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
      color: AppTheme.accent2.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 16, color: AppTheme.accent2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.accent2, fontSize: 12),
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
  final String? title;
  const InlineErrorCard({
    super.key,
    required this.message,
    this.onRetry,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
            const SizedBox(width: 8),
            Text(title ?? 'Something went wrong',
                style: const TextStyle(
                    color: AppTheme.danger, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Text(message, style: const TextStyle(color: AppTheme.textDim)),
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

/// Friendly empty-state card.
class EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppTheme.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(body,
              style:
                  const TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.4)),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tiny "cached — N min ago" pill. Rendered next to a title or inside a card
/// when the UI is showing offline-cache data.
class StaleBadge extends StatelessWidget {
  final String label;
  const StaleBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.accent2.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.accent2.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cached, size: 11, color: AppTheme.accent2),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.accent2,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4)),
        ],
      ),
    );
  }
}

/// Simple shimmer-style skeleton bar used for first-load placeholders.
class SkeletonBlock extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;
  const SkeletonBlock({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 8,
  });

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04 + 0.05 * t),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// Skeleton card modeled after _DeviceTile — shown on first load of the devices
/// list while the network call is in flight.
class DeviceTileSkeleton extends StatelessWidget {
  const DeviceTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const SkeletonBlock(height: 44, width: 44, radius: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBlock(height: 14, width: 150),
                SizedBox(height: 6),
                SkeletonBlock(height: 11, width: 90),
                SizedBox(height: 12),
                Row(
                  children: [
                    SkeletonBlock(height: 18, width: 60, radius: 999),
                    SizedBox(width: 8),
                    SkeletonBlock(height: 18, width: 60, radius: 999),
                    SizedBox(width: 8),
                    SkeletonBlock(height: 18, width: 60, radius: 999),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ListSkeleton extends StatelessWidget {
  final int count;
  final Widget Function(int) tileBuilder;
  const ListSkeleton(
      {super.key, this.count = 3, required this.tileBuilder});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) => tileBuilder(i),
    );
  }
}
