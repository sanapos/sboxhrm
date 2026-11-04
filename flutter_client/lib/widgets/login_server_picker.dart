import 'package:flutter/material.dart';

import '../config/sbox_endpoints.dart';
import '../l10n/app_tr.dart';
import '../services/api_service.dart';
import '../theme/sbox_tokens.dart';

/// Máy chủ cuối màn đăng nhập của app BOSS / Nhân Viên / KDS: mặc định chỉ hiện máy chủ
/// đang dùng; bấm vào và nhập mã bảo mật mới mở lựa chọn đổi máy chủ.
class LoginServerPicker extends StatefulWidget {
  const LoginServerPicker({super.key, this.onChanged});

  /// Gọi sau khi đã chuyển máy chủ (để form đăng nhập xóa lỗi cũ).
  final VoidCallback? onChanged;

  @override
  State<LoginServerPicker> createState() => _LoginServerPickerState();
}

class _LoginServerPickerState extends State<LoginServerPicker> {
  static const _securityCode = '123123';

  // Bản test trỏ API local: giữ thêm dòng máy chủ đang chạy để chọn lại được.
  final String _initial = ApiService.baseUrl;
  bool _expanded = false;
  String? _busyUrl;
  String? _error;

  List<String> get _servers => [
        SboxEndpoints.posSite,
        SboxEndpoints.hrmSite,
        if (_initial != SboxEndpoints.posSite && _initial != SboxEndpoints.hrmSite) _initial,
      ];

  Future<void> _unlock() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _SecurityCodeDialog(code: _securityCode),
    );
    if (ok == true && mounted) setState(() => _expanded = true);
  }

  Future<void> _select(String url) async {
    if (_busyUrl != null) return;
    if (url == ApiService.baseUrl) {
      setState(() => _expanded = false);
      return;
    }
    setState(() {
      _busyUrl = url;
      _error = null;
    });
    final err = await ApiService.applyBaseUrl(url);
    if (!mounted) return;
    setState(() {
      _busyUrl = null;
      _error = err;
      if (err == null) _expanded = false;
    });
    if (err == null) widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Máy chủ'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SboxColors.slate600),
          ),
          const SizedBox(height: 8),
          if (_expanded) ...[
            for (final url in _servers) _serverRow(url),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
              ),
            const SizedBox(height: 4),
            Text(
              tr('Mỗi máy chủ có dữ liệu và tài khoản riêng.'),
              style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
            ),
          ] else
            _currentRow(),
        ],
      ),
    );
  }

  String _host(String url) => Uri.tryParse(url)?.host ?? url;

  /// Dòng thu gọn: máy chủ đang dùng.
  Widget _currentRow() {
    return _rowShell(
      selected: false,
      onTap: _unlock,
      children: [
        const Icon(Icons.dns_outlined, size: 20, color: SboxColors.slate400),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _host(ApiService.baseUrl),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SboxColors.slate900),
          ),
        ),
        const Icon(Icons.chevron_right_rounded, size: 20, color: SboxColors.slate400),
      ],
    );
  }

  Widget _serverRow(String url) {
    final selected = url == ApiService.baseUrl;
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _rowShell(
        selected: selected,
        onTap: () => _select(url),
        children: [
          if (_busyUrl == url)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? color : SboxColors.slate400,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _host(url),
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: SboxColors.slate900,
              ),
            ),
          ),
          if (url == SboxEndpoints.posSite)
            Text(tr('Mặc định'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
        ],
      ),
    );
  }

  Widget _rowShell({required bool selected, required VoidCallback onTap, required List<Widget> children}) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : SboxColors.slate200, width: selected ? 1.5 : 1),
        ),
        child: Row(children: children),
      ),
    );
  }
}

class _SecurityCodeDialog extends StatefulWidget {
  const _SecurityCodeDialog({required this.code});

  final String code;

  @override
  State<_SecurityCodeDialog> createState() => _SecurityCodeDialogState();
}

class _SecurityCodeDialogState extends State<_SecurityCodeDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim() == widget.code) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _error = tr('Mã bảo mật không đúng'));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Đổi máy chủ')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: tr('Mã bảo mật'), errorText: _error),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Hủy'))),
        ElevatedButton(onPressed: _submit, child: Text(tr('Xác nhận'))),
      ],
    );
  }
}
