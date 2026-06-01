import 'package:flutter/material.dart';
import '../utils/web_marketing_gate_stub.dart'
    if (dart.library.html) '../utils/web_marketing_gate_web.dart' as web_gate;

/// Redirects web visitors at `/` to the static [home.html] ?? marketing page.
class WebStaticHomeRedirect extends StatefulWidget {
  const WebStaticHomeRedirect({super.key});

  @override
  State<WebStaticHomeRedirect> createState() => _WebStaticHomeRedirectState();
}

class _WebStaticHomeRedirectState extends State<WebStaticHomeRedirect> {
  @override
  void initState() {
    super.initState();
    web_gate.redirectToStaticHome();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
