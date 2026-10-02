import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/pos/pos_vnd_thousands_formatter.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../departments_v2/dp_common.dart';
import '../hr_finance/hr_fin_common.dart';

String ecDate(DateTime? d) =>
    d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Mở form trong hộp thoại (máy tính) hoặc trang (điện thoại). Trả true nếu đã lưu.
Future<bool?> ecOpen(BuildContext context, Widget form) {
  if (MediaQuery.of(context).size.width >= 700) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620, maxHeight: 800), child: form),
      ),
    );
  }
  return Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => form));
}

class _FormShell extends StatelessWidget {
  const _FormShell({required this.title, required this.children, required this.onSave, required this.saving, this.icon, this.color});
  final String title;
  final List<Widget> children;
  final VoidCallback? onSave;
  final bool saving;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(children: [
            if (icon != null) ...[Icon(icon, color: color), const SizedBox(width: 8)],
            Flexible(child: Text(tr(title))),
          ]),
          actions: [IconButton(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close_rounded))],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), children: children),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SboxButton(label: 'Lưu', icon: Icons.check_rounded, expand: true, loading: saving, onPressed: saving ? null : onSave),
          ),
        ),
      );
}

InputDecoration _dec(String label, {String? hint, String? helper, String? suffix}) => InputDecoration(
      labelText: tr(label),
      hintText: hint == null ? null : tr(hint),
      helperText: helper == null ? null : tr(helper),
      helperMaxLines: 2,
      suffixText: suffix,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );

Widget _dateField(BuildContext context, String label, DateTime? value, ValueChanged<DateTime?> onChanged, {bool clearable = false}) =>
    InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1990),
          lastDate: DateTime(DateTime.now().year + 5),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: _dec(label).copyWith(
          suffixIcon: clearable && value != null
              ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => onChanged(null))
              : const Icon(Icons.event_rounded, size: 20),
        ),
        child: Text(value == null ? tr('Không thời hạn') : ecDate(value)),
      ),
    );

/// Tệp đính kèm: chọn & tải lên, hiện danh sách.
class _Attachments extends StatelessWidget {
  const _Attachments({required this.urls, required this.onChanged});
  final List<String> urls;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final u in urls)
          InputChip(
            avatar: Icon(u.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_rounded : Icons.image_rounded, size: 18),
            label: Text(u.split('/').last, overflow: TextOverflow.ellipsis),
            onDeleted: () => onChanged([...urls]..remove(u)),
          ),
        ActionChip(
          avatar: const Icon(Icons.attach_file_rounded, size: 18),
          label: Text(tr('Đính kèm quyết định (ảnh / PDF)')),
          onPressed: () async {
            final added = await hrFinPickAndUpload(context, ApiService());
            if (added.isNotEmpty) onChanged([...urls, ...added]);
          },
        ),
      ]),
    ]);
  }
}

// ─── Khen thưởng / kỷ luật ─────────────────────────────────────

class CareerRecordForm extends StatefulWidget {
  const CareerRecordForm({super.key, required this.employeeId, required this.kind, this.existing});
  final String employeeId;

  /// award | discipline
  final String kind;
  final Map<String, dynamic>? existing;

  @override
  State<CareerRecordForm> createState() => _CareerRecordFormState();
}

class _CareerRecordFormState extends State<CareerRecordForm> {
  final _api = ApiService();
  late final TextEditingController _title;
  late final TextEditingController _form;
  late final TextEditingController _decision;
  late final TextEditingController _issuer;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _date;
  DateTime? _end;
  late List<String> _files;
  bool _saving = false;

  bool get _award => widget.kind == 'award';

  static const _awardForms = ['Giấy khen', 'Bằng khen', 'Thưởng tiền', 'Biểu dương', 'Nhân viên xuất sắc'];
  static const _disciplineForms = ['Nhắc nhở', 'Khiển trách', 'Cảnh cáo', 'Kéo dài nâng lương', 'Cách chức', 'Sa thải'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?['title']?.toString() ?? '');
    _form = TextEditingController(text: e?['form']?.toString() ?? '');
    _decision = TextEditingController(text: e?['decisionNumber']?.toString() ?? '');
    _issuer = TextEditingController(text: e?['issuedBy']?.toString() ?? '');
    final amt = (e?['amount'] as num?) ?? 0;
    _amount = TextEditingController(text: amt > 0 ? PosVndThousandsFormatter.format(amt) : '');
    _note = TextEditingController(text: e?['note']?.toString() ?? '');
    _date = DateTime.tryParse(e?['date']?.toString() ?? '')?.toLocal() ?? DateTime.now();
    _end = DateTime.tryParse(e?['endDate']?.toString() ?? '')?.toLocal();
    _files = [for (final f in (e?['attachments'] as List? ?? const [])) '$f'];
  }

  @override
  void dispose() {
    for (final c in [_title, _form, _decision, _issuer, _amount, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      dpToast(context, _award ? 'Nhập nội dung khen thưởng' : 'Nhập lý do kỷ luật', error: true);
      return;
    }
    final amount = PosVndThousandsFormatter.parse(_amount.text);
    final data = {
      'kind': widget.kind,
      'title': _title.text.trim(),
      'form': _form.text.trim(),
      'decisionNumber': _decision.text.trim(),
      'effectiveDate': DateTime(_date.year, _date.month, _date.day).toIso8601String(),
      'endDate': _end == null ? null : DateTime(_end!.year, _end!.month, _end!.day).toIso8601String(),
      'issuedBy': _issuer.text.trim(),
      'amount': amount > 0 ? amount : null,
      'note': _note.text.trim(),
      'attachments': _files,
    };
    setState(() => _saving = true);
    final r = widget.existing == null
        ? await _api.addCareerRecord(widget.employeeId, data)
        : await _api.updateCareerRecord('${widget.existing!['recordId']}', data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      Navigator.pop(context, true);
    } else {
      dpToast(context, r['message']?.toString() ?? 'Không lưu được', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forms = _award ? _awardForms : _disciplineForms;
    return _FormShell(
      title: '${widget.existing == null ? 'Thêm' : 'Sửa'} ${_award ? 'khen thưởng' : 'kỷ luật'}',
      icon: _award ? Icons.emoji_events_rounded : Icons.gavel_rounded,
      color: _award ? SboxColors.warning : SboxColors.danger,
      saving: _saving,
      onSave: _save,
      children: [
        TextField(
          controller: _title,
          autofocus: widget.existing == null,
          maxLines: 2,
          decoration: _dec(_award ? 'Nội dung khen thưởng *' : 'Lý do kỷ luật *',
              hint: _award ? 'VD: Hoàn thành xuất sắc chỉ tiêu quý 3' : 'VD: Vi phạm nội quy giờ giấc nhiều lần'),
        ),
        const SizedBox(height: 12),
        Text(tr('Hình thức'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in forms)
            ChoiceChip(
              label: Text(tr(f)),
              selected: _form.text == f,
              showCheckmark: false,
              onSelected: (_) => setState(() => _form.text = _form.text == f ? '' : f),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _form, onChanged: (_) => setState(() {}), decoration: _dec('Hoặc nhập hình thức khác')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _decision, decoration: _dec('Số quyết định', hint: 'QĐ-15/2026'))),
          const SizedBox(width: 10),
          Expanded(child: _dateField(context, 'Ngày hiệu lực', _date, (d) => setState(() => _date = d ?? _date))),
        ]),
        const SizedBox(height: 12),
        if (!_award) ...[
          _dateField(context, 'Hiệu lực đến', _end, (d) => setState(() => _end = d), clearable: true),
          const SizedBox(height: 12),
        ],
        TextField(controller: _issuer, decoration: _dec('Cấp / người ra quyết định', hint: 'VD: Giám đốc')),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: [PosVndThousandsFormatter()],
          decoration: _dec(_award ? 'Tiền thưởng kèm theo' : 'Tiền phạt / bồi thường kèm theo',
              suffix: '₫', helper: 'Chỉ ghi nhận vào hồ sơ. Muốn cộng / trừ lương, tạo phiếu ở Tài chính nhân sự.'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLines: 3, decoration: _dec('Ghi chú')),
        const SizedBox(height: 12),
        _Attachments(urls: _files, onChanged: (v) => setState(() => _files = v)),
      ],
    );
  }
}

// ─── Điều chuyển / bổ nhiệm / thăng chức ───────────────────────

class CareerMoveForm extends StatefulWidget {
  const CareerMoveForm({super.key, required this.employee});

  /// employee từ /api/employee-career (id, department, departmentId, position).
  final Map<String, dynamic> employee;

  @override
  State<CareerMoveForm> createState() => _CareerMoveFormState();
}

class _CareerMoveFormState extends State<CareerMoveForm> {
  final _api = ApiService();
  final _position = TextEditingController();
  final _decision = TextEditingController();
  final _issuer = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'transfer';
  String? _deptId;
  DeptTree? _tree;
  DateTime _date = DateTime.now();
  List<String> _files = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _deptId = widget.employee['departmentId']?.toString();
    _position.text = widget.employee['position']?.toString() ?? '';
    _loadTree();
  }

  @override
  void dispose() {
    for (final c in [_position, _decision, _issuer, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTree() async {
    final r = await _api.getDepartmentOverview();
    if (!mounted || r['data'] is! Map) return;
    setState(() => _tree = DeptTree([
          for (final x in ((r['data'] as Map)['items'] as List? ?? const []).whereType<Map>()) Dept(Map<String, dynamic>.from(x)),
        ]));
  }

  List<String> get _suggestions {
    final d = _deptId == null ? null : _tree?.byId[_deptId];
    return d?.positions ?? const [];
  }

  Future<void> _save() async {
    if (_deptId == null) {
      dpToast(context, 'Chọn phòng ban', error: true);
      return;
    }
    if (_position.text.trim().isEmpty) {
      dpToast(context, 'Nhập chức vụ', error: true);
      return;
    }
    setState(() => _saving = true);
    final r = await _api.moveEmployeeCareer('${widget.employee['id']}', {
      'kind': _kind,
      'departmentId': _deptId,
      'position': _position.text.trim(),
      'effectiveDate': DateTime(_date.year, _date.month, _date.day).toIso8601String(),
      'decisionNumber': _decision.text.trim(),
      'issuedBy': _issuer.text.trim(),
      'note': _note.text.trim(),
      'attachments': _files,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      final now = (r['data'] as Map?)?['appliedNow'] == true;
      dpToast(context, now ? 'Đã cập nhật phòng ban, chức vụ trên hồ sơ' : 'Đã ghi nhận, hồ sơ đổi từ ngày ${ecDate(_date)}');
      Navigator.pop(context, true);
    } else {
      dpToast(context, r['message']?.toString() ?? 'Không lưu được', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.employee;
    final future = DateTime(_date.year, _date.month, _date.day).isAfter(DateTime.now());
    return _FormShell(
      title: 'Điều chuyển / bổ nhiệm',
      icon: Icons.swap_horiz_rounded,
      color: SboxColors.brand600,
      saving: _saving,
      onSave: _save,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: SboxColors.slate50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.badge_outlined, color: SboxColors.slate500),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Hiện tại: ${e['position'] ?? 'Chưa có chức vụ'} · ${e['department'] ?? 'Chưa có phòng ban'}'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'transfer', label: Text(tr('Điều chuyển'))),
            ButtonSegment(value: 'appointment', label: Text(tr('Bổ nhiệm'))),
            ButtonSegment(value: 'promotion', label: Text(tr('Thăng chức'))),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _tree == null
              ? null
              : () async {
                  final id = await pickDepartment(context, _tree!, title: 'Chọn phòng ban mới');
                  if (id != null && id.isNotEmpty) setState(() => _deptId = id);
                },
          child: InputDecorator(
            decoration: _dec('Phòng ban *').copyWith(suffixIcon: const Icon(Icons.expand_more_rounded)),
            child: Text(tr(_deptId == null ? 'Chọn phòng ban' : (_tree?.pathOf(_deptId!) ?? '${e['department'] ?? ''}'))),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _position, decoration: _dec('Chức vụ *', hint: 'VD: Trưởng nhóm')),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in _suggestions) ActionChip(label: Text(tr(p)), onPressed: () => setState(() => _position.text = p)),
          ]),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _dateField(context, 'Ngày hiệu lực', _date, (d) => setState(() => _date = d ?? _date))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _decision, decoration: _dec('Số quyết định'))),
        ]),
        if (future)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('Hiệu lực trong tương lai: hồ sơ giữ phòng ban, chức vụ hiện tại và tự cập nhật khi tới ngày hiệu lực.'),
                style: const TextStyle(fontSize: 12, color: SboxColors.warningText)),
          ),
        const SizedBox(height: 12),
        TextField(controller: _issuer, decoration: _dec('Cấp / người ra quyết định')),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLines: 2, decoration: _dec('Ghi chú')),
        const SizedBox(height: 12),
        _Attachments(urls: _files, onChanged: (v) => setState(() => _files = v)),
      ],
    );
  }
}
