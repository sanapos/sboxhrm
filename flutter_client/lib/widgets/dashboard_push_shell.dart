import 'package:flutter/material.dart';

/// Wraps screens pushed from [DashboardScreen] ?? with a back control.
/// Main-layout tabs omit this; dashboard deep-links need an explicit way back.
class DashboardPushShell extends StatelessWidget {
  const DashboardPushShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return PopScope(
      canPop: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            top: top + 4,
            left: 4,
            child: Material(
              color: Colors.white,
              elevation: 3,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              child: IconButton(
                tooltip: 'Quay lại',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
