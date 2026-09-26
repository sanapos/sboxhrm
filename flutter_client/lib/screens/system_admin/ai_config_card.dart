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
  /// Mọi khóa dùng chung (đã che) — khóa hết lượt tự chuyển sang khóa kế tiếp.
  List<String> _keys = const [];
  /// Khóa (đã che) → giờ hết tạm nghỉ (hết lượt / sai khóa).
  Map<String, DateTime> _cooling = const {};
  /// Khóa (đã che) → kết quả lần thử gần nhất.
  Map<String, Map> _testByKey = const {};
  bool _appendKey = true;
  String? _testDetail;
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
    _keys = ((d['apiKeys'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    _cooling = {
      for (final st in ((d['keyStatus'] as List?) ?? const []).whereType<Map>())
        if (st['coolingUntil'] != null && DateTime.tryParse(st['coolingUntil'].toString()) != null)
          st['key'].toString(): DateTime.parse(st['coolingUntil'].toString()).toLocal(),
    };
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
      if (_keyCtrl.text.trim().isNotEmpty) 'appendApiKey': _appendKey && _keys.isNotEmpty,
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

  Future<void> _removeKey(String masked) async {
    setState(() => _saving = true);
    final res = await _api.saveSystemAiConfig({'removeApiKeys': [masked]});
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _apply(Map<String, dynamic>.from(res['data'] as Map));
      }
    });
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, tr('Đã xóa khóa'));
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testDetail = null;
    });
    final res = await _api.testSystemAiConfig();
    if (!mounted) return;
    setState(() {
      _testing = false;
      final data = res['data'];
      // Kết quả từng khóa (hoạt động / hết lượt / sai khóa).
      _testDetail = data is Map
          ? (data['detail']?.toString() ?? '').replaceAll(' · ', '\n')
          : res['message']?.toString();
      _testByKey = {
        if (data is Map)
          for (final r in ((data['keys'] as List?) ?? const []).whereType<Map>()) r['key'].toString(): r,
      };
    });
    await _load();
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, tr('Kết nối AI thành công ($_model)'));
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  /// Khóa đang được dùng: khóa đầu tiên không tạm nghỉ.
  int get _firstReadyIndex {
    for (var i = 0; i < _keys.length; i++) {
      if (!_cooling.containsKey(_keys[i])) return i;
    }
    return -1;
  }

  Widget _keyStatusChip(String masked, bool inUse) {
    final test = _testByKey[masked];
    final until = _cooling[masked];
    final hhmm = until == null
        ? ''
        : '${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}';
    final (String label, Color color) = test != null && test['status'] == 'invalid'
        ? (tr('Sai / bị khóa'), const Color(0xFFB91C1C))
        : until != null
            ? (tr('Hết lượt · nghỉ đến $hhmm'), const Color(0xFFC2410C))
            : test != null && test['status'] == 'error'
                ? (tr('Lỗi kết nối'), const Color(0xFFB91C1C))
                : inUse
                    ? (tr('Đang dùng'), const Color(0xFF15803D))
                    : (tr('Dự phòng'), Colors.grey.shade700);
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
    );
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
          for (final (i, k) in _keys.indexed)
            Row(
              children: [
                const Icon(Icons.lock, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text('${tr('Khóa')} ${i + 1}: $k', style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
                _keyStatusChip(k, i == _firstReadyIndex),
                IconButton(
                  tooltip: tr('Xóa khóa này'),
                  onPressed: _saving ? null : () => _removeKey(k),
                  icon: const Icon(Icons.close, size: 18, color: Color(0xFFB91C1C)),
                ),
              ],
            ),
          if (_keys.isNotEmpty) ...[
            Text(
              tr('Dùng lần lượt từ khóa 1: khóa nào hết lượt (quota) tạm nghỉ 15 phút và tự chuyển sang khóa kế tiếp; '
                  'khóa sai / bị khóa nghỉ 6 giờ. Hết giờ nghỉ thì được dùng lại.'),
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _appendKey,
              onChanged: (v) => setState(() => _appendKey = v ?? true),
              title: Text(tr('Thêm vào danh sách (bỏ chọn = thay toàn bộ)'), style: const TextStyle(fontSize: 13)),
            ),
          ],
          TextField(
            controller: _keyCtrl,
            minLines: 2,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              labelText: tr('Gemini API key (mỗi dòng một key)'),
              hintText: tr('Dán 1 hoặc nhiều key từ aistudio.google.com — mỗi tài khoản Google một key'),
              helperText: _maskedKey.isEmpty ? null : tr('Để trống = giữ các khóa hiện tại'),
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
          if (_testDetail != null && _testDetail!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_testDetail!, style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ],
      ),
    );
  }
}
