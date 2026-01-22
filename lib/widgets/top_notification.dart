import 'dart:async';

import 'package:flutter/material.dart';

class TopNotification {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    dismiss();
    final overlay = Overlay.of(context);
    final theme = Theme.of(context);
    _entry = OverlayEntry(
      builder: (context) => _TopNotificationBanner(
        message: message,
        colorScheme: theme.colorScheme,
        textStyle: theme.textTheme.bodyMedium,
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(duration, dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _TopNotificationBanner extends StatefulWidget {
  const _TopNotificationBanner({
    required this.message,
    required this.colorScheme,
    required this.textStyle,
  });

  final String message;
  final ColorScheme colorScheme;
  final TextStyle? textStyle;

  @override
  State<_TopNotificationBanner> createState() => _TopNotificationBannerState();
}

class _TopNotificationBannerState extends State<_TopNotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -0.2), end: Offset.zero)
            .animate(curve);
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(curve);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.textStyle ??
        TextStyle(
          color: widget.colorScheme.onSurface,
        );
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Material(
                  color: widget.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: TopNotification.dismiss,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        widget.message,
                        style: textStyle.copyWith(
                          color: widget.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
