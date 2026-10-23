import 'dart:ui';
import 'package:flutter/material.dart';

/// Shared light surfaces inspired by the translucent panel on the home screen.
/// Keep the home-page photograph overlay unchanged; on plain light pages a
/// mostly opaque white background keeps text legible while preserving a glass
/// appearance. Public-service symbols on the map retain their original colors.
class MallGlassStyle {
  static const Color accent = Color(0xFF10B981);
  static const Color selectedSurface = Color(0xFFE6F7F0);
  static const Color pageBackground = Color(0xFFF4F7F9);
  static const Color surfaceColor = Color(0xECFFFFFF);
  static const Color borderColor = Color(0xFFD8E3E7);
  static const Color secondaryText = Color(0xFF64748B);
}

class MallGlassCard extends StatelessWidget {
  const MallGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.selected = false,
    this.blur = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool selected;
  /// Disable blur for long scrolling lists to avoid expensive repeated filters.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final surface = DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? MallGlassStyle.selectedSurface.withValues(alpha: 0.94)
                : MallGlassStyle.surfaceColor,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: selected
                  ? MallGlassStyle.accent.withValues(alpha: 0.44)
                  : MallGlassStyle.borderColor,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.055),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: surface,
            )
          : surface,
    );
  }
}
