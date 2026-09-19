import 'dart:ui';
import 'package:flutter/material.dart';

/// Real glassmorphism widget using BackdropFilter blur.
/// Place over any colored/gradient background to get the frosted glass look.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final Color? tintColor;
  final Color? borderColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double borderWidth;

  const GlassContainer({
    Key? key,
    required this.child,
    this.blur = 12,
    this.opacity = 0.12,
    this.tintColor,
    this.borderColor,
    this.borderRadius = 16,
    this.padding,
    this.borderWidth = 1,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (tintColor ?? Colors.white).withOpacity(opacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? Colors.white.withOpacity(0.15),
              width: borderWidth,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Neon glow container — adds a colored outer glow shadow
class NeonCard extends StatelessWidget {
  final Widget child;
  final Color glowColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  const NeonCard({
    Key? key,
    required this.child,
    this.glowColor = const Color(0xFF00E5FF),
    this.borderRadius = 16,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}
