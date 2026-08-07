import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/pos/pos_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _store = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _store.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _error = null);
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(_store.text.trim(), _user.text.trim(), _pass.text);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = auth.error ?? 'Đăng nhập thất bại');
    }
    // MaterialApp home Consumer sẽ chuyển sang PosSell khi isAuthenticated
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final auth = context.watch<AuthProvider>();
    final form = _buildForm(auth.isLoading);
    if (!wide) {
      return Scaffold(body: SafeArea(child: form));
    }
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 11,
            child: Container(
              color: PosTheme.kiotBlue,
              padding: const EdgeInsets.all(28),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Spacer(),
                  Text(
                    'Bán hàng nhanh trên máy POS',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Android 6.0+ · Logic thống nhất SBOX HRM POS',
                    style: TextStyle(color: Color(0xFFDCEBFF), fontSize: 14),
                  ),
                  Spacer(),
                ],
              ),
            ),
          ),
          Expanded(flex: 10, child: form),
        ],
      ),
    );
  }

  Widget _buildForm(bool loading) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('SBOX POS',
                style: TextStyle(color: PosTheme.kiotBlue, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Chào mừng trở lại', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: _store,
              decoration: const InputDecoration(
                labelText: 'Tên cửa hàng',
                prefixIcon: Icon(Icons.storefront_outlined),
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                labelText: 'Email / SĐT',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Mật khẩu',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _login(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: PosTheme.kiotBlue)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: loading ? null : _login,
              style: FilledButton.styleFrom(
                backgroundColor: PosTheme.kiotBlue,
                minimumSize: const Size.fromHeight(48),
              ),
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Đăng nhập →', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
