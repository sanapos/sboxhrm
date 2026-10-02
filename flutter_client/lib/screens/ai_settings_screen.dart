import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_tr.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';

/// Cấu hình Trợ lý AI (Gemini) của cửa hàng.
class AiConfig {
  AiConfig({this.enabled = false, this.model = 'gemini-2.5-flash', this.maxTokens = 2048, this.temperature = 0.7});

  bool enabled;
  String model;
  int maxTokens;
  double temperature;

  AiConfig copy() => AiConfig(enabled: enabled, model: model, maxTokens: maxTokens, temperature: temperature);

  String get key => '$enabled|$model|$maxTokens|${temperature.toStringAsFixed(1)}';

  static const models = <(String, String, String)>[
    ('gemini-2.5-flash', 'Gemini 2.5 Flash', 'Nhanh, tiết kiệm — khuyên dùng'),
    ('gemini-2.5-pro', 'Gemini 2.5 Pro', 'Chất lượng cao, chậm hơn'),
    ('gemini-2.0-flash', 'Gemini 2.0 Flash', 'Đời trước, ổn định'),
    ('gemini-2.0-flash-lite', 'Gemini 2.0 Flash Lite', 'Siêu nhanh, câu trả lời ngắn'),
  ];
}

/// Trợ lý AI: bật / tắt, khóa AI riêng của cửa hàng (nhiều khóa, tự chuyển khi hết lượt), mô hình, kiểm tra kết nối.
/// Khóa luôn được che — server không bao giờ trả khóa thật.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key, this.canEditOverride});

  final bool? canEditOverride;

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _api = ApiService();
  final _newKey = TextEditingController();
  final _tokens = TextEditingController();
  AiConfig _saved = AiConfig();
  AiConfig _c = AiConfig();
  bool _configured = false;
  List<String> _keys = const [];
  Map<String, DateTime> _cooling = const {};
  bool _append = true;
  bool _obscure = true;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _error;
  (bool ok, String text)? _test;

  bool get _canEdit {
    if (widget.canEditOverride != null) return widget.canEditOverride!;
    try {
      return Provider.of<PermissionProvider>(context, listen: false).canEdit('AIGemini');
    } catch (_) {
      return false;
    }
  }

  bool get _dirty => _c.key != _saved.key || _newKey.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newKey.dispose();
    _tokens.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.getGeminiConfig();
    if (!mounted) return;
    if (r['isSuccess'] == true && r['data'] is Map) {
      final d = Map<String, dynamic>.from(r['data'] as Map);
      setState(() {
        _saved = AiConfig(
          enabled: d['enabled'] == true,
          model: (d['model'] ?? 'gemini-2.5-flash').toString(),
          maxTokens: (d['maxOutputTokens'] as num?)?.toInt() ?? 2048,
          temperature: ((d['temperature'] as num?)?.toDouble() ?? 0.7).clamp(0, 2),
        );
        _c = _saved.copy();
        _tokens.text = '${_c.maxTokens}';
        _configured = d['isConfigured'] == true;
        _keys = [for (final k in (d['apiKeys'] as List? ?? const [])) if ('$k'.isNotEmpty) '$k'];
        _cooling = {
          for (final st in ((d['keyStatus'] as List?) ?? const []).whereType<Map>())
            if (DateTime.tryParse('${st['coolingUntil']}') != null) '${st['key']}': DateTime.parse('${st['coolingUntil']}').toLocal(),
        };
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = r['message']?.toString() ?? 'Không tải được cấu hình AI';
      });
    }
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(m)),
        backgroundColor: error ? SboxColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ));

  Future<void> _save() async {
    final key = _newKey.text.trim();
    if (_c.enabled && !_configured && key.isEmpty) {
      _toast('Nhập khóa AI trước khi bật trợ lý', error: true);
      return;
    }
    if (_c.maxTokens < 256 || _c.maxTokens > 8192) {
      _toast('Độ dài tối đa phải từ 256 đến 8192', error: true);
      return;
    }
    final data = <String, dynamic>{
      'enabled': _c.enabled,
      'model': _c.model,
      'maxOutputTokens': _c.maxTokens,
      'temperature': double.parse(_c.temperature.toStringAsFixed(1)),
      if (key.isNotEmpty) 'apiKey': key,
      if (key.isNotEmpty) 'appendApiKey': _append && _keys.isNotEmpty,
    };
    setState(() => _saving = true);
    final r = await _api.updateGeminiConfig(data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      _newKey.clear();
      _toast('Đã lưu cấu hình AI');
      await _load();
    } else {
      _toast(r['message']?.toString() ?? 'Không lưu được', error: true);
    }
  }

  Future<void> _removeKey(String masked) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa khóa AI?')),
        content: Text(tr('Khóa $masked sẽ bị xóa khỏi cửa hàng.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.updateGeminiConfig({'removeApiKeys': [masked]});
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _toast('Đã xóa khóa');
      _load();
    } else {
      _toast(r['message']?.toString() ?? 'Không xóa được khóa', error: true);
    }
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _test = null;
    });
    final r = await _api.testGeminiConnection();
    if (!mounted) return;
    final d = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : <String, dynamic>{};
    final ok = r['isSuccess'] == true && d['success'] == true && d['isQuotaError'] != true;
    final detail = (d['detail'] ?? (d['sampleTitle'] != null ? 'Câu trả lời mẫu: ${d['sampleTitle']}' : '')).toString().replaceAll(' · ', '\n');
    setState(() {
      _testing = false;
      _test = (ok, '${d['message'] ?? r['message'] ?? (ok ? 'Kết nối thành công' : 'Kết nối thất bại')}${detail.isEmpty ? '' : '\n$detail'}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final edit = _canEdit;
    return SettingsPage(
      title: 'Trợ lý AI',
      subtitle: 'Trợ lý trả lời, soạn nội dung, tóm tắt báo cáo bằng Gemini',
      icon: Icons.auto_awesome_outlined,
      loading: _loading,
      error: _error,
      onRetry: _load,
      dirty: _dirty,
      saving: _saving,
      onSave: _save,
      onDiscard: () => setState(() {
        _c = _saved.copy();
        _tokens.text = '${_c.maxTokens}';
        _newKey.clear();
      }),
      children: [
        if (!edit) const SettingsNote('Bạn chỉ có quyền xem. Cần quyền «Thiết lập AI» để thay đổi.', icon: Icons.lock_outline_rounded, tone: SboxTone.neutral),
        _statusSection(edit),
        _keysSection(edit),
        _modelSection(edit),
        _testSection(),
      ],
    );
  }

  Widget _statusSection(bool edit) {
    final (tone, text) = !_c.enabled
        ? (SboxTone.neutral, 'Đang tắt — nhân viên không dùng được trợ lý AI')
        : _keys.isNotEmpty
            ? (SboxTone.success, 'Đang bật · dùng ${_keys.length} khóa riêng của cửa hàng')
            : _configured
                ? (SboxTone.brand, 'Đang bật · dùng khóa AI chung của hệ thống')
                : (SboxTone.warning, 'Đang bật nhưng chưa có khóa AI');
    return SettingsSection(
      title: 'Trạng thái',
      icon: Icons.power_settings_new_rounded,
      trailing: Switch(value: _c.enabled, onChanged: edit ? (v) => setState(() => _c.enabled = v) : null),
      children: [SettingsNote(text, icon: Icons.circle, tone: tone)],
    );
  }

  Widget _keysSection(bool edit) {
    return SettingsSection(
      title: 'Khóa AI riêng của cửa hàng',
      subtitle: 'Không bắt buộc. Có nhiều khóa thì khóa hết lượt sẽ tự chuyển sang khóa kế tiếp, rồi tới khóa chung của hệ thống',
      icon: Icons.key_rounded,
      children: [
        if (_keys.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Chưa có khóa riêng.', style: TextStyle(color: SboxColors.slate500)),
          ),
        for (var i = 0; i < _keys.length; i++)
          SettingsTile(
            divider: i > 0,
            label: 'Khóa ${i + 1}: ${_keys[i]}',
            help: _cooling[_keys[i]] != null
                ? 'Hết lượt — dùng lại lúc ${_cooling[_keys[i]]!.hour.toString().padLeft(2, '0')}:${_cooling[_keys[i]]!.minute.toString().padLeft(2, '0')}'
                : 'Đang dùng được',
            control: IconButton(
              tooltip: tr('Xóa khóa'),
              onPressed: edit ? () => _removeKey(_keys[i]) : null,
              icon: const Icon(Icons.delete_outline_rounded, color: SboxColors.danger),
            ),
          ),
        if (edit) ...[
          const Divider(height: 20),
          TextField(
            controller: _newKey,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('Thêm khóa Gemini API'),
              hintText: 'AIza…',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_keys.isNotEmpty)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _append,
              onChanged: (v) => setState(() => _append = v ?? true),
              title: Text(tr('Thêm vào danh sách, giữ các khóa cũ')),
              subtitle: Text(tr('Bỏ chọn để thay toàn bộ khóa cũ bằng khóa mới')),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _modelSection(bool edit) {
    return SettingsSection(
      title: 'Mô hình & câu trả lời',
      icon: Icons.tune_rounded,
      children: [
        for (final m in AiConfig.models)
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: edit,
            onTap: () => setState(() => _c.model = m.$1),
            leading: Icon(
              _c.model == m.$1 ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: _c.model == m.$1 ? SboxColors.brand600 : SboxColors.slate400,
            ),
            title: Text(tr(m.$2), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr(m.$3)),
          ),
        SettingsTile(
          label: 'Độ sáng tạo: ${_c.temperature.toStringAsFixed(1)}',
          help: _c.temperature <= 0.4
              ? 'Chính xác, ít thay đổi — hợp tra cứu, báo cáo'
              : _c.temperature <= 1.0
                  ? 'Cân bằng — khuyên dùng'
                  : 'Sáng tạo, đa dạng — hợp viết bài, ý tưởng',
          control: SizedBox(
            width: 240,
            child: Slider(
              value: _c.temperature,
              min: 0,
              max: 2,
              divisions: 20,
              onChanged: edit ? (v) => setState(() => _c.temperature = v) : null,
            ),
          ),
        ),
        SettingsTile(
          label: 'Độ dài tối đa mỗi câu trả lời',
          help: 'Đơn vị token (khoảng 3–4 ký tự). Mặc định 2048',
          control: SizedBox(
            width: 140,
            child: TextField(
              controller: _tokens,
              enabled: edit,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              onChanged: (v) => setState(() => _c.maxTokens = int.tryParse(v) ?? 0),
            ),
          ),
        ),
      ],
    );
  }

  Widget _testSection() {
    final t = _test;
    return SettingsSection(
      title: 'Kiểm tra kết nối',
      subtitle: 'Gửi một câu hỏi thử bằng cấu hình đã lưu',
      icon: Icons.wifi_tethering_rounded,
      trailing: SboxButton.secondary(
        label: 'Kiểm tra',
        icon: Icons.play_arrow_rounded,
        loading: _testing,
        onPressed: _testing || _dirty ? null : _runTest,
      ),
      children: [
        if (_dirty) const SettingsNote('Lưu thay đổi trước khi kiểm tra.', icon: Icons.info_outline_rounded, tone: SboxTone.neutral),
        if (t != null)
          SettingsNote(t.$2, icon: t.$1 ? Icons.check_circle_rounded : Icons.error_outline_rounded, tone: t.$1 ? SboxTone.success : SboxTone.danger),
      ],
    );
  }
}
