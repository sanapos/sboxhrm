import 'package:flutter/material.dart';

/// Centralized responsive breakpoints and helpers
class Responsive {
  static const double mobileBreakpoint = 768;
  static const double tabletBreakpoint = 1024;
  static const double largeBreakpoint = 1440;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= mobileBreakpoint && w < tabletBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  static bool isMobileOrTablet(BuildContext context) =>
      MediaQuery.of(context).size.width < tabletBreakpoint;

  static double screenWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  /// Returns value based on breakpoint
  static T value<T>(BuildContext context,
      {required T mobile, T? tablet, required T desktop}) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet ?? desktop;
    return desktop;
  }

  /// Padding for content areas
  static EdgeInsets contentPadding(BuildContext context) => isMobile(context)
      ? const EdgeInsets.all(12)
      : isTablet(context)
          ? const EdgeInsets.all(16)
          : const EdgeInsets.all(24);

  /// Max width for cards/content
  static double? maxContentWidth(BuildContext context) =>
      isMobile(context) ? null : null;

  /// Dialog width - full screen on mobile, constrained on desktop
  static double dialogWidth(BuildContext context) {
    final w = screenWidth(context);
    if (isMobile(context)) return w - 32;
    if (isTablet(context)) return w * 0.7;
    return w * 0.5 > 600 ? 600 : w * 0.5;
  }

  /// Number of columns for a grid
  static int gridColumns(BuildContext context, {int mobile = 1, int tablet = 2, int desktop = 3}) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet;
    return desktop;
  }

  /// Font size scaling
  static double fontSize(BuildContext context, {required double base}) {
    if (isMobile(context)) return base * 0.9;
    return base;
  }
}

/// Widget that rebuilds when orientation or size changes
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext ctx, bool isMobile, bool isTablet, bool isDesktop) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final isMobile = w < Responsive.mobileBreakpoint;
        final isTablet = w >= Responsive.mobileBreakpoint && w < Responsive.tabletBreakpoint;
        final isDesktop = w >= Responsive.tabletBreakpoint;
        return builder(ctx, isMobile, isTablet, isDesktop);
      },
    );
  }
}
