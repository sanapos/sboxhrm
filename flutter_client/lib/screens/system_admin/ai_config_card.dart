import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import 'system_admin_helpers.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Cấu hình AI (Gemini) dùng chung toàn hệ thống — cửa hàng không có key riêng dùng cấu hình này
/// cho quét menu bằng ảnh và phân tích mẫu Word báo giá / hợp đồng.
class SystemAiConfigCard extends StatefulWidget {
  const SystemAiConfigCard({super.key});

  @override
  State<SystemAiConfigCard> createState() => _SystemAiConfigCardState();
}

class _SystemAiConfigCardState extends State<SystemAiConfigCard> {
  static const _models = ['gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-2.5-flash-lite'];

  final _api = ApiService();
  final _keyCtrl = TextEditingController();
  String _maskedKey = '';
  String _model = _models.first;
  bool _enabled = false;
  bool _configured = false;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic> d) {
    _maskedKey = (d['apiKey'] ?? '').toString();
    final m = (d['model'] ?? '').toString();
    _model = m.isEmpty ? _models.first : m;
    _enabled = d['enabled'] == true;
    _configured = d['isConfigured'] == true;
  }

  Future<void> _load() async {
    final res = await _api.getSystemAiConfig();
    if (!mounted) return;
    setState(() {
      if (res['isSuccess'] == true && res['data'] is Map) {
        _apply(Map<String, dynamic>.from(res['data'] as Map));
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await _api.saveSystemAiConfig({
      if (_keyCtrl.text.trim().isNotEmpty) 'apiKey': _keyCtrl.text.trim(),
      'model': _model,
      'enabled': _enabled,
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _apply(Map<String, dynamic>.from(res['data'] as Map));
        _keyCtrl.clear();
      }
    });
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, tr('Đã lưu cấu hình AI'));
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final res = await _api.testSystemAiConfig();
    if (!mounted) return;
    setState(() => _testing = false);
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, tr('Kết nối AI thành công ($_model)'));
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: ExpansionTile(
        leading: const Icon(Icons.auto_awesome, color: Color(0xFF7C3AED)),
        title: Text(tr('AI dùng chung (Gemini)'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(_loading
            ? tr('Đang tải…')
            : !_configured
                ? tr('Chưa cấu hình — quét menu & mẫu Word sẽ không chạy')
                : (_enabled ? tr('Đang bật · $_model') : tr('Đang tắt'))),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            tr('Dùng cho mọi cửa hàng chưa nhập key riêng: chụp ảnh menu tạo hàng hóa, phân tích mẫu Word báo giá / hợp đồng.'),
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: tr('Gemini API key'),
              hintText: _maskedKey.isEmpty ? tr('Dán key từ aistudio.google.com') : _maskedKey,
              helperText: _maskedKey.isEmpty ? null : tr('Để trống = giữ key hiện tại'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _models.contains(_model) ? _model : _models.first,
            decoration: InputDecoration(
                labelText: tr('Model'), border: const OutlineInputBorder()),
            items: [
              for (final m in _models) DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) => setState(() => _model = v ?? _models.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Bật AI cho toàn hệ thống')),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(tr('Lưu')),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _testing || !_configured ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bolt),
                label: Text(tr('Thử kết nối')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
