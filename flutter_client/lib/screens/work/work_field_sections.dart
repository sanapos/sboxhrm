import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../models/task.dart';
import '../../models/task_v2.dart';
import '../../services/api_service.dart';
import '../../services/work_api.dart';
import '../../utils/image_source_picker.dart';
import '../../utils/platform_geolocation.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'work_common.dart';

// ─── Tiện ích chung ───────────────────────────────────────────────

/// Vị trí hiện tại (null nếu không bật GPS / từ chối quyền).
Future<GeoPosition?> workCurrentPosition(BuildContext context) async {
  try {
    if (!await ensureLocationPermission()) {
      if (context.mounted) workToast(context, 'Chưa cấp quyền vị trí — bật định vị (GPS) để check-in', error: true);
      return null;
    }
    return await getCurrentPosition(timeout: 15000);
  } catch (_) {
    if (context.mounted) workToast(context, 'Không lấy được vị trí — kiểm tra GPS', error: true);
    return null;
  }
}

String _money(num v) => '${SboxFmt.number(v)} đ';

/// Chụp / chọn ảnh rồi tải lên nơi lưu của cửa hàng (máy chủ hoặc Google Drive). Trả URL xem ảnh.
Future<TaskMediaV2?> workUploadPhoto(
  BuildContext context,
  String taskId, {
  String category = 'report',
  String? checklistItemId,
  String? fieldKey,
  String? caption,
}) async {
  final picked = await pickSingleImageWithCamera(context, maxEdge: 1600, jpegQuality: 80);
  if (picked == null || !context.mounted) return null;
  GeoPosition? pos;
  try {
    pos = await getLastKnownPosition();
  } catch (_) {}
  final r = await WorkApi().uploadMedia(taskId, picked.bytes, picked.name,
      category: category, checklistItemId: checklistItemId, fieldKey: fieldKey, caption: caption,
      lat: pos?.latitude, lng: pos?.longitude);
  if (!context.mounted) return null;
  if (r['isSuccess'] == true && r['data'] is Map) {
    final m = TaskMediaV2.fromJson(Map<String, dynamic>.from(r['data'] as Map));
    if (m.warning != null) workToast(context, m.warning!, error: true);
    return m;
  }
  workToast(context, 'Không tải được ảnh: ${r['message'] ?? ''}', error: true);
  return null;
}

/// Phiếu hoàn thành (PDF) — chia sẻ Zalo / in.
Future<void> workShareReportPdf(BuildContext context, WorkTask t) async {
  workToast(context, 'Đang tạo phiếu hoàn thành…');
  final bytes = await WorkApi().reportPdf(t.id);
  if (!context.mounted) return;
  if (bytes == null) {
    workToast(context, 'Không tạo được PDF — thử lại sau', error: true);
    return;
  }
  await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: 'PhieuHoanThanh_${t.taskCode}.pdf');
}

/// Quản lý chấm điểm việc đã hoàn thành.
Future<bool> workEvaluate(BuildContext context, WorkTask t) async {
  var quality = 4.0, timely = 4.0, overall = 4.0;
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Widget stars(String label, double v, ValueChanged<double> on) => Row(children: [
              SizedBox(width: 110, child: Text(tr(label))),
              for (var i = 1; i <= 5; i++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(i <= v ? Icons.star_rounded : Icons.star_border_rounded, color: SboxColors.warning),
                  onPressed: () => set(() => on(i.toDouble())),
                ),
            ]);
        return AlertDialog(
          title: Text(tr('Đánh giá «${t.title}»')),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              stars('Chất lượng', quality, (v) => quality = v),
              stars('Đúng hạn', timely, (v) => timely = v),
              stars('Tổng thể', overall, (v) => overall = v),
              TextField(controller: note, decoration: InputDecoration(labelText: tr('Nhận xét')), maxLines: 2),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu đánh giá'))),
          ],
        );
      },
    ),
  );
  if (ok != true) return false;
  final r = await ApiService().createTaskEvaluation(t.id,
      qualityScore: quality.round(), timelinessScore: timely.round(), overallScore: overall.round(),
      comment: note.text.trim().isEmpty ? null : note.text.trim());
  if (!context.mounted) return false;
  workToast(context, r['isSuccess'] == true ? 'Đã lưu đánh giá' : '${r['message'] ?? 'Không lưu được'}',
      error: r['isSuccess'] != true);
  return r['isSuccess'] == true;
}

/// Nhắc người làm (gửi thông báo).
Future<void> workRemind(BuildContext context, WorkTask t) async {
  final to = t.assigneeId;
  if (to == null) {
    workToast(context, 'Việc chưa có người làm', error: true);
    return;
  }
  final msg = TextEditingController(text: tr('Nhắc: hạn ${workDate(t.dueDate, withTime: true)} — cập nhật giúp mình nhé.'));
  var urgent = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr('Nhắc việc')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: msg, maxLines: 3),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: urgent,
            onChanged: (v) => set(() => urgent = v),
            title: Text(tr('Khẩn')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Gửi nhắc'))),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final r = await ApiService().sendTaskReminder(t.id, sentToId: to, message: msg.text.trim(), urgencyLevel: urgent ? 2 : 0);
  if (context.mounted) {
    workToast(context, r['isSuccess'] == true ? 'Đã gửi nhắc' : '${r['message'] ?? 'Không gửi được'}', error: r['isSuccess'] != true);
  }
}

// ─── Khách hàng & địa điểm ───────────────────────────────────────

class WorkCustomerCard extends StatelessWidget {
  const WorkCustomerCard({super.key, required this.task});
  final WorkTask task;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final phone = (t.customerPhone ?? '').replaceAll(RegExp(r'[^\d+]'), '');
    final hasPlace = (t.location ?? '').isNotEmpty || t.latitude != null;
    if ((t.customerName ?? '').isEmpty && phone.isEmpty && !hasPlace && (t.relatedLabel ?? '').isEmpty) {
      return const SizedBox.shrink();
    }
    final mapUri = t.latitude != null
        ? Uri.parse('https://www.google.com/maps/search/?api=1&query=${t.latitude},${t.longitude}')
        : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(t.location ?? '')}');
    return SboxCard(
      title: 'Khách hàng & địa điểm',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ((t.customerName ?? '').isNotEmpty)
          Text(t.customerName!, style: SboxType.bodyStyle().copyWith(fontWeight: FontWeight.w600)),
        if ((t.relatedLabel ?? '').isNotEmpty)
          Text(tr('Chứng từ: ${t.relatedLabel}'), style: SboxType.smallStyle(SboxColors.textMuted)),
        if ((t.location ?? '').isNotEmpty) Text(t.location!, style: SboxType.smallStyle()),
        const SizedBox(height: SboxSpace.sm),
        Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, children: [
          if (phone.isNotEmpty)
            SboxButton.secondary(
                label: 'Gọi', icon: Icons.call_outlined, onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone))),
          if (phone.isNotEmpty)
            SboxButton.secondary(
                label: 'Zalo',
                icon: Icons.chat_outlined,
                onPressed: () => launchUrl(Uri.parse('https://zalo.me/$phone'), mode: LaunchMode.externalApplication)),
          if (hasPlace)
            SboxButton.secondary(
                label: 'Chỉ đường', icon: Icons.directions_outlined, onPressed: () => launchUrl(mapUri, mode: LaunchMode.externalApplication)),
        ]),
      ]),
    );
  }
}

// ─── Biểu mẫu riêng ──────────────────────────────────────────────

class WorkFormCard extends StatefulWidget {
  const WorkFormCard({super.key, required this.task, required this.canEdit, required this.onChanged});
  final WorkTask task;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  State<WorkFormCard> createState() => _WorkFormCardState();
}

class _WorkFormCardState extends State<WorkFormCard> {
  final _ctrls = <String, TextEditingController>{};
  final _values = <String, String>{};
  bool _dirty = false;
  bool _saving = false;
  String? _uploadingKey;

  List<TaskFormFieldV2> get _fields => TaskFormFieldV2.parse(widget.task.formSchema);

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant WorkFormCard old) {
    super.didUpdateWidget(old);
    if (old.task.formValues != widget.task.formValues && !_dirty) _reset();
  }

  void _reset() {
    _values
      ..clear()
      ..addAll(TaskFormFieldV2.parseValues(widget.task.formValues));
    for (final f in _fields) {
      final c = _ctrls.putIfAbsent(f.key, () => TextEditingController());
      c.text = _values[f.key] ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = <String, String?>{for (final f in _fields) if (!{'photo', 'signature'}.contains(f.type)) f.key: _values[f.key] ?? ''};
    final r = await WorkApi().saveForm(widget.task.id, payload);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      _dirty = false;
      workToast(context, 'Đã lưu biểu mẫu');
      widget.onChanged();
    } else {
      workToast(context, '${r['message'] ?? 'Không lưu được'}', error: true);
    }
  }

  void _set(String key, String v) => setState(() {
        _values[key] = v;
        _dirty = true;
      });

  Future<void> _pickPhoto(TaskFormFieldV2 f) async {
    setState(() => _uploadingKey = f.key);
    final m = await workUploadPhoto(context, widget.task.id, category: 'form', fieldKey: f.key, caption: f.label);
    if (!mounted) return;
    setState(() => _uploadingKey = null);
    if (m != null) {
      setState(() => _values[f.key] = m.url);
      widget.onChanged();
    }
  }

  Future<void> _sign(TaskFormFieldV2 f) async {
    final png = await showSignaturePad(context, title: f.label);
    if (png == null || !mounted) return;
    setState(() => _uploadingKey = f.key);
    final r = await WorkApi().uploadMedia(widget.task.id, png, 'chu-ky.png', category: 'signature', fieldKey: f.key, caption: f.label);
    if (!mounted) return;
    setState(() => _uploadingKey = null);
    if (r['isSuccess'] == true && r['data'] is Map) {
      final m = TaskMediaV2.fromJson(Map<String, dynamic>.from(r['data'] as Map));
      setState(() => _values[f.key] = m.url);
      workToast(context, 'Đã lưu chữ ký');
      widget.onChanged();
    } else {
      workToast(context, '${r['message'] ?? 'Không lưu được chữ ký'}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = _fields;
    if (fields.isEmpty) return const SizedBox.shrink();
    final missing = fields.where((f) => f.required && (_values[f.key] ?? '').trim().isEmpty && _values[f.key] != 'false').toList();
    return SboxCard(
      title: 'Thông tin công việc',
      subtitle: missing.isEmpty ? 'Đã đủ thông tin bắt buộc' : 'Còn ${missing.length} mục bắt buộc',
      trailing: widget.canEdit && _dirty
          ? FilledButton(onPressed: _saving ? null : _save, child: Text(tr(_saving ? 'Đang lưu…' : 'Lưu')))
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final f in fields) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: _field(f)),
      ]),
    );
  }

  Widget _label(TaskFormFieldV2 f) => Text.rich(TextSpan(children: [
        TextSpan(text: tr(f.label), style: SboxType.smallStyle(SboxColors.textSecondary).copyWith(fontWeight: FontWeight.w600)),
        if (f.required) const TextSpan(text: ' *', style: TextStyle(color: SboxColors.danger)),
        if ((f.unit ?? '').isNotEmpty) TextSpan(text: ' (${f.unit})', style: SboxType.captionStyle()),
      ]));

  Widget _field(TaskFormFieldV2 f) {
    final v = _values[f.key] ?? '';
    final enabled = widget.canEdit;
    final c = _ctrls.putIfAbsent(f.key, () => TextEditingController(text: v));
    final hint = (f.hint ?? '').isEmpty ? null : tr(f.hint!);
    switch (f.type) {
      case 'select':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(f),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in f.options)
              ChoiceChip(label: Text(tr(o)), selected: v == o, onSelected: enabled ? (s) => _set(f.key, s ? o : '') : null),
          ]),
        ]);
      case 'checkbox':
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: v == 'true',
          onChanged: enabled ? (b) => _set(f.key, b == true ? 'true' : 'false') : null,
          title: _label(f),
        );
      case 'rating':
        final n = int.tryParse(v) ?? 0;
        return Row(children: [
          Expanded(child: _label(f)),
          for (var i = 1; i <= 5; i++)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(i <= n ? Icons.star_rounded : Icons.star_border_rounded, color: SboxColors.warning),
              onPressed: enabled ? () => _set(f.key, '$i') : null,
            ),
        ]);
      case 'date':
        final d = DateTime.tryParse(v);
        return Row(children: [
          Expanded(child: _label(f)),
          TextButton.icon(
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(d == null ? tr('Chọn ngày') : workDate(d)),
            onPressed: !enabled
                ? null
                : () async {
                    final p = await showDatePicker(
                      context: context,
                      initialDate: d ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (p != null) _set(f.key, '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
                  },
          ),
        ]);
      case 'photo':
      case 'signature':
        final isSig = f.type == 'signature';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(f),
          const SizedBox(height: 4),
          Row(children: [
            if (v.isNotEmpty)
              ClipRRect(
                borderRadius: SboxRadius.smAll,
                child: Container(
                  color: Colors.white,
                  child: Image.network(workImageUrl(v), width: isSig ? 160 : 96, height: 72, fit: isSig ? BoxFit.contain : BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                ),
              ),
            if (v.isNotEmpty) const SizedBox(width: SboxSpace.sm),
            if (enabled)
              _uploadingKey == f.key
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : SboxButton.secondary(
                      label: isSig ? (v.isEmpty ? 'Khách ký' : 'Ký lại') : (v.isEmpty ? 'Chụp ảnh' : 'Chụp lại'),
                      icon: isSig ? Icons.draw_outlined : Icons.photo_camera_outlined,
                      onPressed: () => isSig ? _sign(f) : _pickPhoto(f),
                    ),
          ]),
        ]);
      default:
        final numeric = f.type == 'number' || f.type == 'money';
        return TextField(
          controller: c,
          enabled: enabled,
          minLines: f.type == 'textarea' ? 2 : 1,
          maxLines: f.type == 'textarea' ? 5 : 1,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true, signed: true)
              : f.type == 'phone'
                  ? TextInputType.phone
                  : TextInputType.text,
          onChanged: (x) => _set(f.key, f.type == 'money' ? x.replaceAll(RegExp(r'[^\d\-]'), '') : x.replaceAll(',', '.')),
          decoration: InputDecoration(
            label: _label(f),
            hintText: hint,
            helperText: f.type == 'money' && v.isNotEmpty ? _money(num.tryParse(v) ?? 0) : null,
            isDense: true,
          ),
        );
    }
  }
}

// ─── Hiện trường: check-in GPS / bấm giờ ─────────────────────────

class WorkFieldCard extends StatefulWidget {
  const WorkFieldCard({super.key, required this.task, required this.canAct, required this.onChanged});
  final WorkTask task;
  final bool canAct;
  final VoidCallback onChanged;

  @override
  State<WorkFieldCard> createState() => _WorkFieldCardState();
}

class _WorkFieldCardState extends State<WorkFieldCard> {
  List<TaskTimeLogV2> _logs = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await WorkApi().timeLogs(widget.task.id);
    if (!mounted) return;
    setState(() => _logs = r['data'] is List
        ? (r['data'] as List).whereType<Map>().map((e) => TaskTimeLogV2.fromJson(Map<String, dynamic>.from(e))).toList()
        : const []);
  }

  Future<void> _go(bool checkIn) async {
    setState(() => _busy = true);
    final pos = await workCurrentPosition(context);
    if (!mounted) return;
    if (pos == null && widget.task.requireCheckIn && checkIn) {
      setState(() => _busy = false);
      return;
    }
    final api = WorkApi();
    final r = checkIn
        ? await api.checkIn(widget.task.id, lat: pos?.latitude, lng: pos?.longitude)
        : await api.checkOut(widget.task.id, lat: pos?.latitude, lng: pos?.longitude);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      final d = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : const <String, dynamic>{};
      final dist = d['startDistanceM'];
      workToast(context, checkIn ? (dist == null ? 'Đã check-in' : 'Đã check-in · cách địa điểm $dist m') : 'Đã check-out');
      await _load();
      widget.onChanged();
    } else {
      workToast(context, '${r['message'] ?? 'Không thực hiện được'}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final open = _logs.any((l) => l.open);
    final hours = _logs.fold<double>(0, (a, l) => a + l.hours);
    final relevant = t.requireCheckIn || _logs.isNotEmpty || t.latitude != null;
    if (!relevant && !widget.canAct) return const SizedBox.shrink();
    return SboxCard(
      title: 'Hiện trường',
      subtitle: [
        if (t.requireCheckIn) 'Bắt buộc check-in tại địa điểm',
        if (hours > 0) 'Đã làm ${SboxFmt.number(hours)} giờ',
      ].join(' · ').isEmpty
          ? 'Check-in để ghi giờ và vị trí làm việc'
          : [
              if (t.requireCheckIn) 'Bắt buộc check-in tại địa điểm',
              if (hours > 0) 'Đã làm ${SboxFmt.number(hours)} giờ',
            ].join(' · '),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.canAct && t.isOpen)
          Align(
            alignment: Alignment.centerLeft,
            child: _busy
                ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2))
                : open
                    ? SboxButton.pay(label: 'Check-out', icon: Icons.logout_rounded, expand: false, onPressed: () => _go(false))
                    : SboxButton(label: 'Check-in tại đây', icon: Icons.my_location_rounded, onPressed: () => _go(true)),
          ),
        for (final l in _logs.take(10))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(l.open ? Icons.radio_button_checked : Icons.check_circle_outline, size: 16,
                  color: l.open ? SboxColors.success : SboxColors.slate400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    l.employeeName,
                    '${workDate(l.startAt, withTime: true)} → ${l.open ? tr('đang làm') : workDate(l.endAt, withTime: true)}',
                    if (l.startDistanceM != null) tr('cách ${l.startDistanceM} m'),
                  ].whereType<String>().join(' · '),
                  style: SboxType.smallStyle(),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ─── Ảnh báo cáo ─────────────────────────────────────────────────

class WorkMediaCard extends StatefulWidget {
  const WorkMediaCard({super.key, required this.task, required this.canAct, required this.storageLabel});
  final WorkTask task;
  final bool canAct;
  final String storageLabel;

  @override
  State<WorkMediaCard> createState() => _WorkMediaCardState();
}

class _WorkMediaCardState extends State<WorkMediaCard> {
  List<TaskMediaV2> _media = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await WorkApi().media(widget.task.id);
    if (!mounted) return;
    setState(() => _media = r['data'] is List
        ? (r['data'] as List).whereType<Map>().map((e) => TaskMediaV2.fromJson(Map<String, dynamic>.from(e))).toList()
        : const []);
  }

  Future<void> _add(String category) async {
    setState(() => _busy = true);
    final m = await workUploadPhoto(context, widget.task.id, category: category);
    if (!mounted) return;
    setState(() => _busy = false);
    if (m != null) _load();
  }

  Future<void> _delete(TaskMediaV2 m) async {
    final ok = await SboxDialogs.confirm(context, title: 'Xoá ảnh?', message: m.fileName, confirmLabel: 'Xoá');
    if (!ok) return;
    final r = await WorkApi().deleteMedia(widget.task.id, m.id);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _load();
    } else {
      workToast(context, '${r['message'] ?? 'Không xoá được'}', error: true);
    }
  }

  void _open(TaskMediaV2 m) {
    if (!m.isImage) {
      launchUrl(Uri.parse(workImageUrl(m.url)), mode: LaunchMode.externalApplication);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: InteractiveViewer(child: Image.network(workImageUrl(m.url), fit: BoxFit.contain))),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              [m.categoryLabel, m.caption, m.uploadedByName, workDate(m.createdAt?.toLocal(), withTime: true)]
                  .whereType<String>()
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              style: SboxType.smallStyle(),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = _media.where((m) => m.category != 'signature').toList();
    return SboxCard(
      title: 'Ảnh & tài liệu báo cáo',
      subtitle: '${photos.length} file · lưu trên ${widget.storageLabel}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.canAct)
          Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, children: [
            SboxButton.secondary(label: 'Ảnh trước', icon: Icons.photo_camera_outlined, onPressed: _busy ? null : () => _add('before')),
            SboxButton.secondary(label: 'Ảnh sau', icon: Icons.photo_camera_back_outlined, onPressed: _busy ? null : () => _add('after')),
            SboxButton.secondary(label: 'Ảnh báo cáo', icon: Icons.add_a_photo_outlined, onPressed: _busy ? null : () => _add('report')),
            if (_busy) const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        if (photos.isNotEmpty) const SizedBox(height: SboxSpace.sm),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in photos)
            GestureDetector(
              onTap: () => _open(m),
              onLongPress: widget.canAct ? () => _delete(m) : null,
              child: Stack(children: [
                ClipRRect(
                  borderRadius: SboxRadius.smAll,
                  child: m.isImage
                      ? Image.network(workImageUrl(m.url), width: 96, height: 72, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 96, height: 72, color: SboxColors.slate100, child: const Icon(Icons.broken_image_outlined)))
                      : Container(
                          width: 96, height: 72, color: SboxColors.slate100,
                          child: const Icon(Icons.description_outlined, color: SboxColors.slate500)),
                ),
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Text(tr(m.categoryLabel), style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
                if (m.storageKind == 'gdrive')
                  const Positioned(right: 4, top: 4, child: Icon(Icons.add_to_drive, size: 14, color: Colors.white)),
              ]),
            ),
        ]),
      ]),
    );
  }
}

// ─── Ký tên ──────────────────────────────────────────────────────

/// Khung ký tên trên màn hình → PNG (nền trắng).
Future<Uint8List?> showSignaturePad(BuildContext context, {String title = 'Chữ ký'}) {
  final strokes = <List<Offset>>[];
  final key = GlobalKey();
  return showDialog<Uint8List>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr(title)),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        content: SizedBox(
          width: 420,
          height: 220,
          child: Container(
            key: key,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: SboxColors.border), borderRadius: SboxRadius.smAll),
            child: GestureDetector(
              onPanStart: (d) => set(() => strokes.add([d.localPosition])),
              onPanUpdate: (d) => set(() => strokes.last.add(d.localPosition)),
              child: CustomPaint(painter: _SignaturePainter(strokes), size: Size.infinite),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => set(strokes.clear), child: Text(tr('Ký lại'))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () async {
              if (strokes.isEmpty) return;
              final box = key.currentContext?.findRenderObject() as RenderBox?;
              final size = box?.size ?? const Size(420, 220);
              final recorder = ui.PictureRecorder();
              final canvas = Canvas(recorder);
              canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
              _SignaturePainter(strokes).paint(canvas, size);
              final img = await recorder.endRecording().toImage(size.width.ceil(), size.height.ceil());
              final data = await img.toByteData(format: ui.ImageByteFormat.png);
              if (ctx.mounted) Navigator.pop(ctx, data?.buffer.asUint8List());
            },
            child: Text(tr('Xác nhận')),
          ),
        ],
      ),
    ),
  );
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, 1.3, p..style = PaintingStyle.fill);
        p.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final o in s.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}
