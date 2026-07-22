import 'package:flutter/material.dart';
import '../utils/web_marketing_gate_stub.dart'
    if (dart.library.html) '../utils/web_marketing_gate_web.dart' as web_gate;

/// Redirects web visitors to the static homepage (`/`), not Flutter Landing.
class WebStaticHomeRedirect extends StatefulWidget {
  const WebStaticHomeRedirect({super.key, this.section});

  /// Optional homepage anchor section, e.g. `pricing`, `devices`, `contact`.
  final String? section;

  @override
  State<WebStaticHomeRedirect> createState() => _WebStaticHomeRedirectState();
}

class _WebStaticHomeRedirectState extends State<WebStaticHomeRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments;
      final fromArgs = args is Map ? args['scrollSection']?.toString() : null;
      web_gate.redirectToStaticHome(
        section: widget.section ?? fromArgs,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
