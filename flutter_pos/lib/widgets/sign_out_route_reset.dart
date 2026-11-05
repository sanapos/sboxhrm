import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Đăng xuất hoặc hết phiên khi đang ở trang con: gỡ hết trang đã mở để về màn đăng nhập.
/// Trang gốc đổi sang LoginScreen nhưng các trang đã push vẫn nằm đè lên, người dùng bị kẹt.
class SignOutRouteReset extends StatefulWidget {
  const SignOutRouteReset({super.key, required this.child});

  final Widget child;

  @override
  State<SignOutRouteReset> createState() => _SignOutRouteResetState();
}

class _SignOutRouteResetState extends State<SignOutRouteReset> {
  late final AuthProvider _auth;
  late bool _wasSignedIn;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _wasSignedIn = _auth.isAuthenticated;
    _auth.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final signedIn = _auth.isAuthenticated;
    if (_wasSignedIn && !signedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
      });
    }
    _wasSignedIn = signedIn;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
