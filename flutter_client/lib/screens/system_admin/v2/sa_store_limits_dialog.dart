import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/app_tr.dart';
import '../../../services/api_service.dart';
import '../../../widgets/sbox/sbox_ui.dart';
import 'sa_v2_common.dart';

/// Giới hạn RIÊNG của một cửa hàng (số chi nhánh, tài khoản, thiết bị, thông báo FCM).
/// Để trống = theo gói dịch vụ; 0 = không giới hạn. Không bị ghi đè khi đổi gói.
class StoreLimitsDialog extends StatefulWidget {
  const StoreLimitsDialog({super.key, required this.api, required this.catalog, required this.store, required this.data});
  final ApiService api;
  final SaCatalog catalog;
  final Map<String, dynamic> store;
  final Map<String, dynamic> data;

  @override
  State<StoreLimitsDialog> createState() => _StoreLimitsDialogState();
}

enum _FcmMode { inherit, on, off }

class _StoreLimitsDialogState extends State<StoreLimitsDialog> {
  Map<String, dynamic> get _pkg => Map<String, dynamic>.from(widget.data['package'] as Map? ?? {});
  Map<String, dynamic> get _ov => Map<String, dynamic>.from(widget.data['overrides'] as Map? ?? {});
  Map<String, dynamic> get _usage => Map<String, dynamic>.from(widget.data['usage'] as Map? ?? {});

  late final _branches = TextEditingController(text: _initial('maxBranches'));
  late final _users = TextEditingController(text: _initial('maxUsers'));
  late final _devices = TextEditingController(text: _initial('maxDevices'));
  late final _access = TextEditingController(text: _initial('maxAccessDevices'));
  late final _note = TextEditingController(text: '${widget.data['adminNote'] ?? ''}');
  late _FcmMode _fcm = _ov['allowFcm'] == null ? _FcmMode.inherit : (_ov['allowFcm'] == true ? _FcmMode.on : _FcmMode.off);
  late bool _customCats = _ov['fcmCategories'] != null;
  late final Set<String> _cats = {...((_ov['fcmCategories'] ?? _pkg['fcmCategories']) as List? ?? []).map((e) => '$e')};
  bool _saving = false;

  String _initial(String key) => _ov[key] == null ? '' : '${_ov[key]}';

  int? _parse(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());

  String _limitLabel(dynamic v) => (v is num && v > 0) ? '$v' : 'không giới hạn';

  Widget _numberField(String label, TextEditingController c, String pkgKey, {dynamic used}) {
    final pkgValue = _pkg[pkgKey];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: saInput(
          label,
          hint: 'Theo gói: ${_limitLabel(pkgValue)}',
          helper: 'Để trống = theo gói (${_limitLabel(pkgValue)}) · 0 = không giới hạn${used == null ? '' : ' · đang dùng $used'}',
        ),
      ),
    );
  }

  Future<void> _save({bool reset = false}) async {
    setState(() => _saving = true);
    final body = reset
        ? <String, dynamic>{}
        : <String, dynamic>{
            'maxBranches': _parse(_branches),
            'maxUsers': _parse(_users),
            'maxDevices': _parse(_devices),
            'maxAccessDevices': _parse(_access),
            'allowFcm': _fcm == _FcmMode.inherit ? null : _fcm == _FcmMode.on,
            'fcmCategories': (_fcm == _FcmMode.on && _customCats) ? _cats.toList() : null,
            'note': _note.text.trim(),
          };
    final r = await widget.api.saSaveStoreLimits('${widget.store['id']}', body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saOk(context, r, reset ? 'Đã bỏ giới hạn riêng — cửa hàng dùng theo gói' : 'Đã lưu giới hạn riêng')) return;
    final warnings = ((r['data'] is Map ? r['data']['warnings'] : null) as List? ?? []).map((e) => '$e').toList();
    if (warnings.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Lưu ý khi giới hạn thấp hơn mức đang dùng')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final w in warnings) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $w')),
            const SizedBox(height: 4),
            Text(tr('Dữ liệu hiện có không bị xóa; cửa hàng chỉ không thêm mới được cho đến khi giảm xuống hoặc nâng giới hạn.'),
                style: SboxType.smallStyle()),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đã hiểu')))],
        ),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final fcmPkg = _pkg['allowFcm'] != false;
    return AlertDialog(
      title: Text(tr('Giới hạn & thông báo — ${widget.store['name']}')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Gói: ${widget.data['packageName'] ?? 'chưa gán gói'} · giá trị riêng ở đây ưu tiên hơn gói và được giữ khi đổi gói.',
                style: SboxType.smallStyle()),
            const SizedBox(height: 12),
            Text(tr('Chi nhánh'), style: SboxType.bodyStrong()),
            const SizedBox(height: 6),
            _numberField('Số chi nhánh tối đa', _branches, 'maxBranches', used: _usage['branches']),
            Text(tr('Tài khoản & thiết bị'), style: SboxType.bodyStrong()),
            const SizedBox(height: 6),
            _numberField('Số tài khoản tối đa', _users, 'maxUsers', used: _usage['users']),
            _numberField('Số máy chấm công tối đa', _devices, 'maxDevices', used: _usage['devices']),
            _numberField('Số thiết bị truy cập tối đa', _access, 'maxAccessDevices'),
            const SizedBox(height: 4),
            Text(tr('Thông báo đẩy (FCM)'), style: SboxType.bodyStrong()),
            const SizedBox(height: 6),
            SegmentedButton<_FcmMode>(
              segments: [
                ButtonSegment(value: _FcmMode.inherit, label: Text(tr('Theo gói (${fcmPkg ? 'bật' : 'tắt'})'))),
                ButtonSegment(value: _FcmMode.on, label: Text(tr('Bật'))),
                ButtonSegment(value: _FcmMode.off, label: Text(tr('Tắt'))),
              ],
              selected: {_fcm},
              onSelectionChanged: (s) => setState(() => _fcm = s.first),
            ),
            if (_fcm == _FcmMode.on) ...[
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _customCats,
                onChanged: (v) => setState(() => _customCats = v),
                title: Text(tr('Chỉ gửi một số loại thông báo')),
                subtitle: Text(tr(_customCats ? 'Không chọn loại nào = gửi mọi loại.' : 'Đang theo gói: ${((_pkg['fcmCategories'] as List?)?.isEmpty ?? true) ? 'mọi loại' : (_pkg['fcmCategories'] as List).length.toString() + ' loại'}')),
              ),
              if (_customCats)
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final f in widget.catalog.fcm)
                    FilterChip(
                      label: Text(tr(f.name)),
                      selected: _cats.contains(f.code),
                      onSelected: (v) => setState(() => v ? _cats.add(f.code) : _cats.remove(f.code)),
                    ),
                ]),
            ],
            const SizedBox(height: 12),
            TextField(controller: _note, maxLines: 2, decoration: saInput('Ghi chú nội bộ (lý do đặt riêng…)')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => _save(reset: true), child: Text(tr('Dùng theo gói'))),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(tr('Hủy'))),
        FilledButton(onPressed: _saving ? null : _save, child: Text(tr('Lưu'))),
      ],
    );
  }
}
