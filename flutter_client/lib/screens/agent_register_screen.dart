import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'admin_login_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class AgentRegisterScreen extends StatefulWidget {
  const AgentRegisterScreen({super.key, required this.token});

  final String token;

  @override
  State<AgentRegisterScreen> createState() => _AgentRegisterScreenState();
}

class _AgentRegisterScreenState extends State<AgentRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loadingInfo = true;
  bool _submitting = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;
  Map<String, dynamic>? _agentInfo;

  @override
  void initState() {
    super.initState();
    _loadAgentInfo();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAgentInfo() async {
    setState(() {
      _loadingInfo = true;
      _error = null;
    });
    try {
      final res = await ApiService().getAgentByRegistrationToken(widget.token);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        _agentInfo = data;
        _nameCtrl.text = data['agentName']?.toString() ?? '';
      } else {
        _error = res['message']?.toString() ?? 'Token không hợp lệ';
      }
    } catch (e) {
      _error = 'Không thể tải thông tin đăng ký: $e';
    }
    if (mounted) setState(() => _loadingInfo = false);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await ApiService().agentSelfRegister(
        registrationToken: widget.token,
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        confirmPassword: _confirmCtrl.text,
        fullName: _nameCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Đăng ký thành công')),
            content: Text(
              tr(res['data']?['message']?.toString() ??
                  'Bạn có thể đăng nhập cổng đại lý bằng email và mật khẩu vừa tạo.'),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
                  );
                },
                child: Text(tr('Đăng nhập cổng đại lý')),
              ),
            ],
          ),
        );
      } else {
        setState(() => _error = res['message']?.toString() ?? 'Đăng ký thất bại');
      }
    } catch (e) {
      setState(() => _error = 'Lỗi: $e');
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _loadingInfo
                    ? const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _error != null && _agentInfo == null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.red, size: 48),
                              const SizedBox(height: 12),
                              Text(tr(_error!),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _loadAgentInfo,
                                child: Text(tr('Thử lại')),
                              ),
                            ],
                          )
                        : Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.support_agent,
                                        color: Color(0xFF0F172A), size: 28),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(tr('Đăng ký tài khoản đại lý'),
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  tr(_agentInfo?['agentName']?.toString() ?? ''),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                if (_agentInfo?['agentCode'] != null)
                                  Text(tr('${tr('Mã: ')}${_agentInfo!['agentCode']}'),
                                    style: const TextStyle(
                                        color: Color(0xFF64748B)),
                                  ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _nameCtrl,
                                  decoration: InputDecoration(
                                    labelText: tr('Họ tên'),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'Nhập họ tên'
                                          : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText: tr('Email đăng nhập'),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Nhập email';
                                    }
                                    if (!v.contains('@')) return 'Email không hợp lệ';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _passwordCtrl,
                                  obscureText: _obscure1,
                                  decoration: InputDecoration(
                                    labelText: tr('Mật khẩu'),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscure1
                                          ? Icons.visibility_off
                                          : Icons.visibility),
                                      onPressed: () => setState(
                                          () => _obscure1 = !_obscure1),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.length < 6) {
                                      return 'Tối thiểu 6 ký tự';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _confirmCtrl,
                                  obscureText: _obscure2,
                                  decoration: InputDecoration(
                                    labelText: tr('Xác nhận mật khẩu'),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscure2
                                          ? Icons.visibility_off
                                          : Icons.visibility),
                                      onPressed: () => setState(
                                          () => _obscure2 = !_obscure2),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v != _passwordCtrl.text) {
                                      return 'Mật khẩu không khớp';
                                    }
                                    return null;
                                  },
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 12),
                                  Text(tr(_error!),
                                      style: const TextStyle(color: Colors.red)),
                                ],
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: _submitting ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F172A),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                  child: _submitting
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(tr('Hoàn tất đăng ký')),
                                ),
                              ],
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
