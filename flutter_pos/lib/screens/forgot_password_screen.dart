import 'dart:async';

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialStoreCode;
  final String? initialEmail;

  const ForgotPasswordScreen({
    super.key,
    this.initialStoreCode,
    this.initialEmail,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeCodeController = TextEditingController();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String? _successMessage;
  int _step = 1; // 1: nhập email, 2: nhập OTP + mật khẩu mới
  int _resendCooldownSec = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    final store = widget.initialStoreCode?.trim() ?? '';
    final email = widget.initialEmail?.trim() ?? '';
    if (store.isNotEmpty) _storeCodeController.text = store;
    if (email.isNotEmpty && email.contains('@')) {
      _emailController.text = email;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _storeCodeController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 60]) {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldownSec = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendCooldownSec <= 1) {
        t.cancel();
        setState(() => _resendCooldownSec = 0);
      } else {
        setState(() => _resendCooldownSec--);
      }
    });
  }

  Future<void> _handleSendOtp({bool isResend = false}) async {
    if (_resendCooldownSec > 0) {
      setState(() {
        _errorMessage =
            'Vui lòng đợi $_resendCooldownSec giây trước khi gửi lại mã OTP.';
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final apiService = ApiService();
      final result = await apiService.forgotPassword(
        _storeCodeController.text.trim(),
        _emailController.text.trim(),
      );

      if (result['isSuccess'] == true) {
        setState(() {
          _step = 2;
          _successMessage = isResend
              ? 'Đã gửi lại mã OTP. Vui lòng kiểm tra hộp thư (và mục Spam).'
              : 'Mã OTP đã được gửi đến email của bạn. Vui lòng kiểm tra hộp thư (và mục Spam).';
        });
        _startResendCooldown(60);
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Không thể gửi mã OTP.';
        });
        final msg = (result['message'] ?? '').toString().toLowerCase();
        if (msg.contains('60 giây') || msg.contains('đợi')) {
          _startResendCooldown(60);
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Không thể kết nối đến server';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleVerifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final apiService = ApiService();
      final result = await apiService.verifyOtp(
        _storeCodeController.text.trim(),
        _emailController.text.trim(),
        _otpController.text.trim(),
        _newPasswordController.text,
        _confirmPasswordController.text,
      );

      if (result['isSuccess'] == true) {
        if (mounted) {
          NotificationOverlayManager().showSuccess(
              title: 'Thành công',
              message: tr(
                  'Đổi mật khẩu thành công! Vui lòng đăng nhập lại.'));
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        setState(() {
          _errorMessage =
              result['message'] ?? 'Mã OTP không hợp lệ hoặc đã hết hạn.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Không thể kết nối đến server';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .primaryColor
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        _step == 1 ? Icons.lock_reset : Icons.verified_user,
                        size: 48,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      tr(_step == 1 ? 'Quên mật khẩu' : 'Xác nhận OTP'),
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(_step == 1
                          ? 'Nhập mã cửa hàng và email đã đăng ký để nhận mã OTP (hiệu lực 5 phút)'
                          : 'Nhập mã OTP đã gửi đến ${_emailController.text.trim()} và mật khẩu mới (tối thiểu 6 ký tự)'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildStepDot(1),
                        Container(
                          width: 40,
                          height: 2,
                          color: _step >= 2
                              ? Theme.of(context).primaryColor
                              : Colors.grey.shade300,
                        ),
                        _buildStepDot(2),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tr(_errorMessage!),
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_successMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tr(_successMessage!),
                                style: const TextStyle(
                                    color: Colors.green, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_step == 1) ...[
                      TextFormField(
                        controller: _storeCodeController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: tr('Mã cửa hàng *'),
                          hintText: tr('VD: sanapos'),
                          prefixIcon: const Icon(Icons.store),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập mã cửa hàng';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleSendOtp(),
                        decoration: InputDecoration(
                          labelText: tr('Email *'),
                          hintText: tr('Nhập email đăng ký (không dùng SĐT)'),
                          helperText: tr(
                              'Tài khoản chỉ có SĐT: liên hệ quản trị viên đặt lại mật khẩu'),
                          prefixIcon: const Icon(Icons.email),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập email';
                          }
                          if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$')
                              .hasMatch(value.trim())) {
                            return 'Email không hợp lệ';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _isLoading ? null : () => _handleSendOtp(),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(tr('Gửi mã OTP'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  )),
                        ),
                      ),
                    ],
                    if (_step == 2) ...[
                      TextFormField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        style: const TextStyle(
                          fontSize: 24,
                          letterSpacing: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: tr('Mã OTP *'),
                          hintText: tr('000000'),
                          prefixIcon: const Icon(Icons.pin),
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập mã OTP';
                          }
                          if (value.trim().length != 6) {
                            return 'Mã OTP phải có 6 chữ số';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _newPasswordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: tr('Mật khẩu mới *'),
                          hintText: tr('Ít nhất 6 ký tự'),
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Vui lòng nhập mật khẩu mới';
                          }
                          if (value.length < 6) {
                            return 'Mật khẩu phải có ít nhất 6 ký tự';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: tr('Xác nhận mật khẩu *'),
                          hintText: tr('Nhập lại mật khẩu mới'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () => setState(() =>
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Vui lòng xác nhận mật khẩu';
                          }
                          if (value != _newPasswordController.text) {
                            return 'Mật khẩu không khớp';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: (_isLoading || _resendCooldownSec > 0)
                              ? null
                              : () {
                                  _otpController.clear();
                                  _handleSendOtp(isResend: true);
                                },
                          child: Text(tr(_resendCooldownSec > 0
                              ? 'Gửi lại sau ${_resendCooldownSec}s'
                              : 'Gửi lại mã OTP?')),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _handleVerifyOtp,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(tr('Xác nhận đổi mật khẩu'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  )),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _step = 1;
                            _otpController.clear();
                            _newPasswordController.clear();
                            _confirmPasswordController.clear();
                            _errorMessage = null;
                            _successMessage = null;
                          });
                        },
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: Text(tr('Quay lại nhập email')),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context).popUntil((route) => route.isFirst),
                      icon: const Icon(Icons.login, size: 18),
                      label: Text(tr('Quay lại đăng nhập')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepDot(int step) {
    final isActive = _step >= step;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive
            ? Theme.of(context).primaryColor
            : Colors.grey.shade300,
      ),
      child: Center(
        child: Text(
          tr('$step'),
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
