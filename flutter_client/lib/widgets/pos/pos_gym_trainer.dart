import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/pos_einvoice_qr.dart';
import '../notification_overlay.dart';

final _dmy = DateFormat('dd/MM/yyyy');

double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(',', '.'));

String _fmt(dynamic v, String unit) {
  final d = _num(v);
  if (d == null) return '';
  final s = d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
  return '$s$unit';
}

/// Ảnh thẻ QR của hội viên (PNG 600×780): tên khách, mã QR mở link, hướng dẫn quét — gửi Zalo hoặc in đưa khách.
Future<Uint8List?> _memberQrCard(String url, String name) async {
  try {
    const w = 600.0, h = 780.0, qrSize = 456.0, qrTop = 150.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(const Rect.fromLTWH(0, 0, w, 124), Paint()..color = const Color(0xFF0E7490));
    void text(String s, double y, double size, Color color, {FontWeight weight = FontWeight.w400}) {
      final b = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 2, ellipsis: '…'))
        ..pushStyle(ui.TextStyle(color: color, fontSize: size, fontWeight: weight))
        ..addText(s);
      final para = b.build()..layout(const ui.ParagraphConstraints(width: w - 48));
      canvas.drawParagraph(para, Offset(24, y));
    }

    text(name, 26, 34, const Color(0xFFFFFFFF), weight: FontWeight.w700);
    text('Thẻ tập · lịch tập · phác đồ PT', 78, 20, const Color(0xE6FFFFFF));
    final ink = Paint()
      ..color = const Color(0xFF0F172A)
      ..isAntiAlias = false;
    const left = (w - qrSize) / 2;
    for (final e in Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.medium)
        .make(url, width: qrSize, height: qrSize, drawText: false)) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(
          Rect.fromLTWH((left + e.left).floorToDouble(), (qrTop + e.top).floorToDouble(), e.width.ceilToDouble() + 0.5,
              e.height.ceilToDouble() + 0.5),
          ink,
        );
      }
    }
    text('Quét mã bằng camera điện thoại để xem', qrTop + qrSize + 24, 23, const Color(0xFF0F172A),
        weight: FontWeight.w600);
    text(url, qrTop + qrSize + 64, 16, const Color(0xFF64748B));
    final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Chèn [text] vào vị trí con trỏ (cuối ô nếu chưa đặt con trỏ).
void _insertText(TextEditingController c, String text) {
  final sel = c.selection;
  final pos = sel.isValid ? sel.end.clamp(0, c.text.length) : c.text.length;
  c.value = TextEditingValue(
    text: c.text.replaceRange(pos, pos, text),
    selection: TextSelection.collapsed(offset: pos + text.length),
  );
}

/// Ô dạng «a, b, c»: bấm chip thêm / bỏ mục.
List<String> _tokens(TextEditingController c) =>
    c.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

void _toggleToken(TextEditingController c, String t) {
  final list = _tokens(c);
  list.contains(t) ? list.remove(t) : list.add(t);
  c.text = list.join(', ');
}

Widget _tokenChips(TextEditingController c, List<String> items, StateSetter setState) => Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final t in items)
          FilterChip(
            label: Text(tr(t), style: const TextStyle(fontSize: 12.5)),
            visualDensity: VisualDensity.compact,
            selected: _tokens(c).contains(t),
            onSelected: (_) => setState(() => _toggleToken(c, t)),
          ),
      ],
    );

Widget _numField(TextEditingController c, String label) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: tr(label), isDense: true, border: const OutlineInputBorder()),
      ),
    );

const _conditionPresets = [
  'Bình thường', 'Mới tập lần đầu', 'Đau lưng', 'Đau gối', 'Đau vai', 'Huyết áp cao', 'Tiểu đường',
  'Thừa cân', 'Thiếu cân', 'Sau sinh', 'Từng chấn thương',
];
const _goalPresets = [
  'Giảm mỡ', 'Giảm cân', 'Tăng cơ', 'Săn chắc', 'Tăng sức bền', 'Cải thiện tư thế', 'Phục hồi chấn thương',
  'Thi đấu / body',
];
const _sessionNotePresets = [
  'Hoàn thành giáo án', 'Tăng tạ so với buổi trước', 'Kỹ thuật tốt', 'Cần sửa kỹ thuật', 'Sức bền tốt',
  'Mệt / thiếu ngủ', 'Đau cơ sau buổi trước', 'Đau khớp — cần theo dõi', 'Ăn uống chưa đúng', 'Cần thêm cardio',
  'Đi trễ / tập thiếu giờ',
];
const _ratingLabels = ['Kém', 'Chưa tốt', 'Đạt', 'Tốt', 'Rất tốt'];

const _planDays = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật'];
const _exercises = <String, List<String>>{
  'Ngực': ['Đẩy ngực ngang 4×10', 'Đẩy ngực dốc lên 3×12', 'Ép ngực máy 3×12', 'Hít đất 3×15'],
  'Lưng': ['Kéo xà 4×8', 'Kéo cáp xuống 3×12', 'Kéo cáp ngồi 3×12', 'Chèo tạ đơn 3×12', 'Deadlift 4×6'],
  'Vai': ['Đẩy vai 4×10', 'Dang tạ bên 3×15', 'Dang tạ sau 3×15'],
  'Tay': ['Cuốn tạ đơn 3×12', 'Cuốn tạ đòn 3×10', 'Đẩy cáp tay sau 3×12', 'Dips 3×10'],
  'Chân – mông': ['Squat 4×10', 'Leg press 4×12', 'Lunge 3×12', 'Đá đùi trước 3×15', 'Móc đùi sau 3×15', 'Hip thrust 4×12'],
  'Bụng – core': ['Plank 3×45s', 'Gập bụng 3×20', 'Nâng chân 3×15', 'Russian twist 3×20'],
  'Cardio': ['Chạy bộ 20 phút', 'Đạp xe 15 phút', 'HIIT 15 phút', 'Leo cầu thang 10 phút'],
  'Khác': ['Khởi động 10 phút', 'Giãn cơ 10 phút', 'Nghỉ giữa hiệp 60–90s', 'Uống 2 lít nước / ngày'],
};
const _planTemplates = <String, String>{
  'Người mới · 3 buổi/tuần': 'Thứ 2: Toàn thân\n- Khởi động 10 phút\n- Squat 3×12\n- Hít đất 3×10\n- Kéo cáp xuống 3×12\n'
      '- Plank 3×30s\nThứ 4: Toàn thân + cardio\n- Leg press 3×12\n- Ép ngực máy 3×12\n- Kéo cáp ngồi 3×12\n'
      '- Đạp xe 15 phút\nThứ 6: Toàn thân\n- Lunge 3×10\n- Đẩy vai 3×12\n- Gập bụng 3×15\n- Giãn cơ 10 phút\n'
      'Ghi chú: tập đúng kỹ thuật trước, tăng tạ từ tuần 3.',
  'Giảm mỡ · 4 buổi/tuần': 'Thứ 2: Chân – mông\n- Squat 4×12\n- Lunge 3×12\n- Hip thrust 4×12\n- HIIT 15 phút\n'
      'Thứ 3: Ngực – vai – tay sau\n- Đẩy ngực ngang 4×12\n- Đẩy vai 3×12\n- Đẩy cáp tay sau 3×15\n- Chạy bộ 20 phút\n'
      'Thứ 5: Lưng – tay trước\n- Kéo cáp xuống 4×12\n- Chèo tạ đơn 3×12\n- Cuốn tạ đơn 3×15\n- Đạp xe 20 phút\n'
      'Thứ 7: Toàn thân + core\n- Deadlift 3×10\n- Hít đất 3×15\n- Plank 3×45s\n- Russian twist 3×20\n'
      'Dinh dưỡng: thâm hụt ~400 kcal/ngày, đủ đạm, giảm tinh bột buổi tối, 2 lít nước/ngày.',
  'Tăng cơ · 5 buổi (chia nhóm cơ)': 'Thứ 2: Ngực\n- Đẩy ngực ngang 4×8\n- Đẩy ngực dốc lên 4×10\n- Ép ngực máy 3×12\n'
      'Thứ 3: Lưng\n- Deadlift 4×6\n- Kéo xà 4×8\n- Chèo tạ đơn 3×10\n'
      'Thứ 4: Chân\n- Squat 5×6\n- Leg press 4×10\n- Móc đùi sau 3×12\n'
      'Thứ 5: Vai\n- Đẩy vai 4×8\n- Dang tạ bên 4×12\n- Dang tạ sau 3×15\n'
      'Thứ 6: Tay\n- Cuốn tạ đòn 4×10\n- Dips 4×10\n- Đẩy cáp tay sau 3×12\n'
      'Dinh dưỡng: dư ~300 kcal/ngày, đạm 1,6–2 g/kg, ngủ đủ 7–8 tiếng.',
};

/// Đánh giá sau buổi tập (điểm 1–5, nhận xét nhanh, cân nặng nếu đo) — PT ghi ngay sau buổi, khách xem trên link.
/// [visitId] gắn phiếu với lượt tập (hiện cạnh lượt đó trên link khách). Trả về true nếu đã lưu.
Future<bool> showGymSessionReview(BuildContext context,
    {required String customerId, required String name, String? visitId, String? visitLabel}) async {
  var rating = 4;
  final note = TextEditingController();
  final weight = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(tr('Đánh giá buổi tập · $name')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (visitLabel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(tr(visitLabel), style: const TextStyle(fontSize: 13, color: SboxColors.slate600)),
                ),
              Text(tr('Kết quả buổi tập'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (var i = 1; i <= 5; i++)
                  ChoiceChip(
                    label: Text(tr('${'★' * i} ${_ratingLabels[i - 1]}'), style: const TextStyle(fontSize: 12.5)),
                    selected: rating == i,
                    onSelected: (_) => setState(() => rating = i),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(tr('Nhận xét nhanh (bấm để chọn)'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              _tokenChips(note, _sessionNotePresets, setState),
              const SizedBox(height: 8),
              TextField(
                controller: note,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: tr('Nhận xét của PT'), isDense: true, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Row(children: [_numField(weight, 'Cân nặng sau buổi (kg, nếu đo)')]),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu đánh giá'))),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  final res = await ApiService().addGymAssessment(customerId, {
    'kind': 1,
    'rating': rating,
    if (visitId != null) 'visitId': visitId,
    'weightKg': _num(weight.text),
    'condition': note.text.trim(),
  });
  if (res['isSuccess'] != true) {
    NotificationOverlayManager().showError(title: 'Chưa lưu', message: res['message']?.toString() ?? '');
    return false;
  }
  NotificationOverlayManager().showSuccess(title: 'Đã lưu đánh giá buổi tập', message: tr(name));
  return true;
}

/// PT phụ trách hội viên + phiếu đánh giá thể trạng (cân nặng, mỡ, cơ, vòng eo, tình trạng, mục tiêu).
/// PT phụ trách nhận hoa hồng buổi khi hội viên check-in trừ buổi gói PT (gói chọn «hoa hồng mỗi buổi»).
Future<void> showGymTrainerSheet(BuildContext context, {required String customerId, required String name}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _TrainerSheet(customerId: customerId, name: name, scroll: scroll),
      ),
    );

class _TrainerSheet extends StatefulWidget {
  const _TrainerSheet({required this.customerId, required this.name, required this.scroll});
  final String customerId;
  final String name;
  final ScrollController scroll;

  @override
  State<_TrainerSheet> createState() => _TrainerSheetState();
}

class _TrainerSheetState extends State<_TrainerSheet> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  String? _trainerId;
  String? _trainerName;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getGymAssessments(widget.customerId);
    final staffRes = await _api.getPosSellSellers();
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? tr('Không tải được dữ liệu');
      });
      return;
    }
    final d = Map<String, dynamic>.from(res['data'] as Map);
    setState(() {
      _loading = false;
      _error = null;
      _trainerId = d['trainerEmployeeId']?.toString();
      _trainerName = d['trainerName']?.toString();
      _items = [
        for (final e in (d['items'] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ];
      _plans = [
        for (final e in (d['plans'] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ];
      _staff = [
        if (staffRes['data'] is List)
          for (final e in staffRes['data'] as List)
            if (e is Map) Map<String, dynamic>.from(e),
      ];
    });
  }

  Future<void> _pickTrainer() async {
    if (_staff.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa có nhân viên',
        message: tr('Thêm PT ở Hồ sơ nhân sự trước, rồi gán cho hội viên.'),
      );
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Chọn PT phụ trách')),
        children: [
          for (final s in _staff)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, '${s['employeeId']}'),
              child: Text(tr('${s['displayName'] ?? ''}'),
                  style: TextStyle(
                      fontWeight: '${s['employeeId']}' == _trainerId ? FontWeight.w700 : FontWeight.w400)),
            ),
          if (_trainerId != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text(tr('Bỏ PT phụ trách'), style: const TextStyle(color: SboxColors.danger)),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final res = await _api.setGymTrainer(widget.customerId, picked.isEmpty ? null : picked);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Chưa lưu', message: res['message']?.toString() ?? '');
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: picked.isEmpty ? 'Đã bỏ PT' : 'Đã gán PT',
      message: tr(picked.isEmpty ? widget.name : '${widget.name} → ${(res['data'] as Map?)?['name'] ?? ''}'),
    );
    await _load();
  }

  Future<void> _addAssessment() async {
    final body = _items.where((a) => a['kind'] != 1).toList();
    final last = body.isEmpty ? null : body.first;
    final weight = TextEditingController();
    final height = TextEditingController(text: _fmt(last?['heightCm'], ''));
    final fat = TextEditingController();
    final muscle = TextEditingController();
    final waist = TextEditingController();
    final chest = TextEditingController();
    final hip = TextEditingController();
    final arm = TextEditingController();
    final thigh = TextEditingController();
    final condition = TextEditingController();
    final goal = TextEditingController(text: '${last?['goal'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr('Đo thể trạng · ${widget.name}')),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (last != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      tr('Lần đo trước: ${[
                        if (_num(last['weightKg']) != null) _fmt(last['weightKg'], 'kg'),
                        if (_num(last['bodyFatPercent']) != null) 'mỡ ${_fmt(last['bodyFatPercent'], '%')}',
                        if (_num(last['waistCm']) != null) 'eo ${_fmt(last['waistCm'], 'cm')}',
                      ].join(' · ')}'),
                      style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600),
                    ),
                  ),
                Row(children: [
                  _numField(weight, 'Cân nặng (kg)'),
                  const SizedBox(width: 8),
                  _numField(height, 'Chiều cao (cm)'),
                  const SizedBox(width: 8),
                  _numField(fat, '% mỡ'),
                  const SizedBox(width: 8),
                  _numField(muscle, 'Cơ (kg)'),
                ]),
                const SizedBox(height: 10),
                Text(tr('Số đo vòng (cm)'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Row(children: [
                  _numField(chest, 'Ngực'),
                  const SizedBox(width: 8),
                  _numField(waist, 'Eo'),
                  const SizedBox(width: 8),
                  _numField(hip, 'Mông'),
                  const SizedBox(width: 8),
                  _numField(arm, 'Bắp tay'),
                  const SizedBox(width: 8),
                  _numField(thigh, 'Đùi'),
                ]),
                const SizedBox(height: 10),
                Text(tr('Tình trạng (bấm để chọn)'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                _tokenChips(condition, _conditionPresets, setState),
                const SizedBox(height: 6),
                TextField(
                  controller: condition,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: tr('Tình trạng / chấn thương / nhận xét của PT'),
                      isDense: true,
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Text(tr('Mục tiêu'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                _tokenChips(goal, _goalPresets, setState),
                const SizedBox(height: 6),
                TextField(
                  controller: goal,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: tr('Mục tiêu (vd giảm 5kg trong 3 tháng)'),
                      isDense: true,
                      border: const OutlineInputBorder()),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu đánh giá'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.addGymAssessment(widget.customerId, {
      'weightKg': _num(weight.text),
      'heightCm': _num(height.text),
      'bodyFatPercent': _num(fat.text),
      'muscleKg': _num(muscle.text),
      'waistCm': _num(waist.text),
      'chestCm': _num(chest.text),
      'hipCm': _num(hip.text),
      'armCm': _num(arm.text),
      'thighCm': _num(thigh.text),
      'condition': condition.text.trim(),
      'goal': goal.text.trim(),
    });
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Chưa lưu', message: res['message']?.toString() ?? '');
      return;
    }
    NotificationOverlayManager().showSuccess(title: 'Đã lưu đánh giá', message: tr(widget.name));
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa phiếu đánh giá?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xóa'))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.deleteGymAssessment('${a['id']}');
    if (!mounted) return;
    if (res['isSuccess'] == true) await _load();
  }

  /// Link công khai cho hội viên: gói, buổi còn, giờ vào – ra, thể trạng, phác đồ (không cần đăng nhập).
  Future<void> _shareLink({bool renew = false}) async {
    final res = await _api.getGymShareLink(widget.customerId, renew: renew);
    if (!mounted) return;
    final path = (res['data'] as Map?)?['path']?.toString();
    if (res['isSuccess'] != true || path == null) {
      NotificationOverlayManager().showError(title: 'Chưa tạo được link', message: res['message']?.toString() ?? '');
      return;
    }
    // Server trả link trên tên miền portal (sboxhrm.com); bản API cũ chỉ có path → ghép theo máy chủ app.
    final base = Uri.parse(ApiService.baseUrl);
    final url = (res['data'] as Map?)?['url']?.toString() ?? '${base.scheme}://${base.authority}$path';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Link cho hội viên · ${widget.name}')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 20,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Khách quét bằng camera điện thoại tại quầy — không cần gõ link.
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: SboxColors.slate200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SvgPicture.string(posQrSvg(url, size: 200), width: 200, height: 200),
                ),
                SizedBox(
                  width: 300,
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Khách quét mã QR bằng camera điện thoại, hoặc gửi link qua Zalo / SMS.'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                        tr('Xem thẻ / gói, số buổi còn, giờ vào – ra từng buổi tập, thể trạng và phác đồ PT giao '
                            '— không cần đăng nhập.'),
                        style: const TextStyle(fontSize: 13, color: SboxColors.slate600)),
                    const SizedBox(height: 10),
                    SelectableText(url,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.brand700)),
                  ]),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _shareLink(renew: true);
            },
            child: Text(tr('Đổi link (link cũ hết hiệu lực)')),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              NotificationOverlayManager().showSuccess(title: 'Đã chép link', message: url);
            },
            child: Text(tr('Chép link')),
          ),
          TextButton.icon(
            onPressed: () async {
              final png = await _memberQrCard(url, widget.name);
              if (png == null) return;
              await Printing.layoutPdf(
                name: 'QR the tap ${widget.name}',
                onLayout: (_) async {
                  final doc = pw.Document();
                  doc.addPage(pw.Page(
                    pageFormat: PdfPageFormat.a6,
                    margin: const pw.EdgeInsets.all(16),
                    build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(png))),
                  ));
                  return doc.save();
                },
              );
            },
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(tr('In QR')),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final png = await _memberQrCard(url, widget.name);
              if (png == null) return;
              await Share.shareXFiles(
                [XFile.fromData(png, name: 'qr-the-tap.png', mimeType: 'image/png')],
                text: tr('${widget.name} ơi, quét mã hoặc mở link để xem thẻ tập, số buổi và phác đồ: $url'),
              );
            },
            icon: const Icon(Icons.qr_code_2, size: 18),
            label: Text(tr('Gửi ảnh QR')),
          ),
          FilledButton.icon(
            onPressed: () => Share.share(tr('${widget.name} ơi, xem thẻ tập, số buổi và phác đồ tập của bạn tại: $url')),
            icon: const Icon(Icons.share, size: 18),
            label: Text(tr('Gửi link')),
          ),
        ],
      ),
    );
  }

  Future<void> _addPlan() async {
    final title = TextEditingController();
    final content = TextEditingController();
    var group = _exercises.keys.first;
    // Dòng mới trước khi chèn (không để 2 mục dính vào cùng một dòng).
    void addLine(String line) {
      final t = content.text;
      final pos = content.selection.isValid ? content.selection.end.clamp(0, t.length) : t.length;
      final needNl = pos > 0 && t[pos - 1] != '\n';
      _insertText(content, '${needNl ? '\n' : ''}$line\n');
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr('Phác đồ tập · ${widget.name}')),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Mẫu nhanh'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final e in _planTemplates.entries)
                    ActionChip(
                      avatar: const Icon(Icons.auto_awesome, size: 16),
                      label: Text(tr(e.key), style: const TextStyle(fontSize: 12.5)),
                      onPressed: () => setState(() {
                        if (title.text.trim().isEmpty) title.text = e.key;
                        content.text = e.value;
                      }),
                    ),
                  if (_plans.isNotEmpty)
                    ActionChip(
                      avatar: const Icon(Icons.copy, size: 16),
                      label: Text(tr('Chép phác đồ gần nhất'), style: const TextStyle(fontSize: 12.5)),
                      onPressed: () => setState(() {
                        title.text = '${_plans.first['title'] ?? ''}';
                        content.text = '${_plans.first['content'] ?? ''}';
                      }),
                    ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                      labelText: tr('Tên phác đồ (vd Tuần 1–4: giảm mỡ)'), isDense: true, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Text(tr('Thêm nhanh: ngày → nhóm cơ → bài tập'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final d in _planDays)
                    ActionChip(
                      label: Text(tr(d), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => addLine('$d: '),
                    ),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final g in _exercises.keys)
                    ChoiceChip(
                      label: Text(tr(g), style: const TextStyle(fontSize: 12.5)),
                      visualDensity: VisualDensity.compact,
                      selected: group == g,
                      onSelected: (_) => setState(() => group = g),
                    ),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final ex in _exercises[group]!)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 14),
                      label: Text(tr(ex), style: const TextStyle(fontSize: 12.5)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => addLine('- $ex'),
                    ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: content,
                  minLines: 8,
                  maxLines: 16,
                  decoration: InputDecoration(
                    labelText: tr('Nội dung (sửa tự do)'),
                    hintText: tr('Bấm ngày, rồi bấm bài tập để thêm — hoặc chọn mẫu nhanh.'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu phác đồ'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.addGymPlan(widget.customerId, {
      // Ghép tay bằng chip mà quên đặt tên → tên mặc định theo ngày.
      'title': title.text.trim().isEmpty ? 'Phác đồ ${_dmy.format(DateTime.now())}' : title.text.trim(),
      'content': content.text.trim(),
      'startDate': DateTime.now().toIso8601String(),
    });
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Chưa lưu', message: res['message']?.toString() ?? '');
      return;
    }
    NotificationOverlayManager().showSuccess(title: 'Đã lưu phác đồ', message: tr(widget.name));
    await _load();
  }

  Future<void> _deletePlan(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa phác đồ «${p['title']}»?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xóa'))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.deleteGymPlan('${p['id']}');
    if (mounted && res['isSuccess'] == true) await _load();
  }

  /// Chênh lệch so với lần đo trước (mũi tên + số), giúp PT / khách thấy tiến bộ.
  String _delta(String key, int index, String unit) {
    final prevItem = _items.skip(index + 1).where((a) => a['kind'] != 1 && _num(a[key]) != null).firstOrNull;
    if (prevItem == null) return '';
    final now = _num(_items[index][key]);
    final prev = _num(prevItem[key]);
    if (now == null || prev == null) return '';
    final d = now - prev;
    if (d.abs() < 0.05) return ' (=)';
    return ' (${d > 0 ? '+' : ''}${d.toStringAsFixed(1)}$unit)';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(children: [
          Expanded(
            child: Text(tr('PT & thể trạng · ${widget.name}'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          OutlinedButton.icon(
            onPressed: _shareLink,
            icon: const Icon(Icons.link, size: 18),
            label: Text(tr('Link cho khách')),
          ),
        ]),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Text(tr(_error!), style: const TextStyle(color: SboxColors.danger))
        else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.sports_gymnastics, color: SboxColors.brand700),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(_trainerName?.isNotEmpty == true ? 'PT phụ trách: $_trainerName' : 'Chưa có PT phụ trách'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    tr('PT nhận hoa hồng mỗi buổi khi hội viên check-in trừ buổi gói PT '
                        '(gói bật «hoa hồng mỗi buổi»).'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate600),
                  ),
                ]),
              ),
              TextButton(onPressed: _pickTrainer, child: Text(tr(_trainerId == null ? 'Gán PT' : 'Đổi PT'))),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Text(tr('Thể trạng & đánh giá buổi tập (${_items.length})'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                if (await showGymSessionReview(context, customerId: widget.customerId, name: widget.name)) _load();
              },
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: Text(tr('Đánh giá buổi')),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _addAssessment,
              icon: const Icon(Icons.straighten, size: 18),
              label: Text(tr('Đo thể trạng')),
            ),
          ]),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(tr('Chưa có phiếu đánh giá. PT đo lần đầu khi khách bắt đầu tập, sau đó đo lại định kỳ để theo dõi tiến bộ.'),
                  style: const TextStyle(color: SboxColors.slate600)),
            ),
          for (var i = 0; i < _items.length; i++) _assessmentCard(i),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Text(tr('Phác đồ tập (${_plans.length})'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            FilledButton.tonalIcon(
              onPressed: _addPlan,
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Giao phác đồ')),
            ),
          ]),
          const SizedBox(height: 8),
          if (_plans.isEmpty)
            Text(tr('Chưa có phác đồ. PT giao bài tập / lịch tuần / dinh dưỡng — khách xem qua «Link cho khách».'),
                style: const TextStyle(color: SboxColors.slate600)),
          for (final p in _plans)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              decoration: BoxDecoration(border: Border.all(color: SboxColors.slate200), borderRadius: BorderRadius.circular(10)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('${p['title']}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      tr([
                        if (DateTime.tryParse('${p['startDate'] ?? ''}') case final d?) 'từ ${_dmy.format(d.toLocal())}',
                        if ('${p['trainerName'] ?? ''}'.isNotEmpty) '${p['trainerName']}'.toUpperCase().startsWith('PT') ? '${p['trainerName']}' : 'PT ${p['trainerName']}',
                      ].join(' · ')),
                      style: const TextStyle(fontSize: 12, color: SboxColors.slate600),
                    ),
                    if ('${p['content'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(tr('${p['content']}'), style: const TextStyle(fontSize: 13)),
                      ),
                  ]),
                ),
                IconButton(
                  tooltip: tr('Xóa'),
                  icon: const Icon(Icons.delete_outline, size: 20, color: SboxColors.slate500),
                  onPressed: () => _deletePlan(p),
                ),
              ]),
            ),
        ],
      ],
    );
  }

  Widget _assessmentCard(int i) {
    final a = _items[i];
    final at = DateTime.tryParse('${a['assessedAt'] ?? ''}')?.toLocal();
    final metrics = <String>[
      if (_num(a['weightKg']) != null) 'Cân nặng ${_fmt(a['weightKg'], 'kg')}${_delta('weightKg', i, 'kg')}',
      if (_num(a['bmi']) != null) 'BMI ${_fmt(a['bmi'], '')}',
      if (_num(a['bodyFatPercent']) != null) 'Mỡ ${_fmt(a['bodyFatPercent'], '%')}${_delta('bodyFatPercent', i, '%')}',
      if (_num(a['muscleKg']) != null) 'Cơ ${_fmt(a['muscleKg'], 'kg')}${_delta('muscleKg', i, 'kg')}',
      if (_num(a['chestCm']) != null) 'Ngực ${_fmt(a['chestCm'], 'cm')}${_delta('chestCm', i, 'cm')}',
      if (_num(a['waistCm']) != null) 'Eo ${_fmt(a['waistCm'], 'cm')}${_delta('waistCm', i, 'cm')}',
      if (_num(a['hipCm']) != null) 'Mông ${_fmt(a['hipCm'], 'cm')}${_delta('hipCm', i, 'cm')}',
      if (_num(a['armCm']) != null) 'Tay ${_fmt(a['armCm'], 'cm')}${_delta('armCm', i, 'cm')}',
      if (_num(a['thighCm']) != null) 'Đùi ${_fmt(a['thighCm'], 'cm')}${_delta('thighCm', i, 'cm')}',
    ];
    final session = a['kind'] == 1;
    final rating = (a['rating'] as num?)?.toInt();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        border: Border.all(color: SboxColors.slate200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              tr([
                session ? 'Sau buổi tập' : 'Đo thể trạng',
                if (at != null) _dmy.format(at),
                if ('${a['trainerName'] ?? ''}'.isNotEmpty) '${a['trainerName']}',
              ].join(' · ')),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (session && rating != null)
              Text(tr('${'★' * rating}${'☆' * (5 - rating)} ${_ratingLabels[rating.clamp(1, 5) - 1]}'),
                  style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w700)),
            if (metrics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr(metrics.join(' · ')), style: const TextStyle(fontSize: 13)),
              ),
            if ('${a['condition'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr(session ? '${a['condition']}' : 'Tình trạng: ${a['condition']}'),
                    style: const TextStyle(fontSize: 13, color: SboxColors.slate700)),
              ),
            if ('${a['goal'] ?? ''}'.isNotEmpty)
              Text(tr('Mục tiêu: ${a['goal']}'), style: const TextStyle(fontSize: 13, color: SboxColors.slate700)),
          ]),
        ),
        IconButton(
          tooltip: tr('Xóa'),
          icon: const Icon(Icons.delete_outline, size: 20, color: SboxColors.slate500),
          onPressed: () => _delete(a),
        ),
      ]),
    );
  }
}

/// Giờ cao điểm & hội viên: lượt vào / người có mặt theo giờ và theo thứ — biết cần thêm người
/// (PT, lễ tân) hay máy tập ở khung giờ nào; kèm số hội viên đang hoạt động / mới / sắp hết / bỏ tập.
class GymTrafficSection extends StatefulWidget {
  const GymTrafficSection({super.key, this.from, this.to});
  final DateTime? from;
  final DateTime? to;

  @override
  State<GymTrafficSection> createState() => _GymTrafficSectionState();
}

class _GymTrafficSectionState extends State<GymTrafficSection> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GymTrafficSection old) {
    super.didUpdateWidget(old);
    // Khoảng ngày tính từ DateTime.now() mỗi lần dựng — chỉ nạp lại khi đổi NGÀY.
    bool same(DateTime? a, DateTime? b) =>
        a == null || b == null ? a == b : a.year == b.year && a.month == b.month && a.day == b.day;
    if (!same(old.from, widget.from) || !same(old.to, widget.to)) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ApiService().getGymTraffic(from: widget.from, to: widget.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final m = Map<String, dynamic>.from(d['members'] as Map? ?? const {});
    final hours = [for (final h in (d['hours'] as List? ?? const [])) Map<String, dynamic>.from(h as Map)];
    final weekdays = [for (final w in (d['weekdays'] as List? ?? const [])) Map<String, dynamic>.from(w as Map)];
    final open = hours.where((h) => ((h['checkIns'] as num?) ?? 0) > 0 || ((h['peakPresent'] as num?) ?? 0) > 0).toList();
    final maxPeak = hours.fold<num>(1, (a, h) => (h['peakPresent'] as num? ?? 0) > a ? h['peakPresent'] as num : a);
    final busiest = d['busiestHour'];
    const wd = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    Widget kpi(String label, Object value, {Color? color}) => Container(
          width: 170,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: SboxColors.slate200), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(label), style: const TextStyle(fontSize: 12, color: SboxColors.slate600)),
            const SizedBox(height: 4),
            Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color ?? SboxColors.slate900)),
          ]),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SboxColors.slate200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Hội viên & giờ cao điểm'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          kpi('Hội viên đang hoạt động', m['active'] ?? 0, color: SboxColors.brand700),
          kpi('Hội viên mới trong kỳ', m['newInPeriod'] ?? 0, color: SboxColors.success),
          kpi('Sắp hết hạn (7 ngày)', m['expiringIn7Days'] ?? 0, color: SboxColors.warningText),
          kpi('Hết hạn chưa gia hạn (30 ngày)', m['lapsedLast30Days'] ?? 0, color: SboxColors.danger),
          kpi('Còn hạn nhưng chưa đến tập', m['activeNotVisited'] ?? 0),
          kpi('Lượt vào TB / ngày', d['avgCheckInsPerDay'] ?? 0),
        ]),
        const SizedBox(height: 12),
        Text(
          tr(busiest == null
              ? 'Chưa có lượt tập trong kỳ.'
              : 'Đông nhất: ${busiest}h–${(busiest as num) + 1}h · tối đa ${d['busiestPeakPresent']} người cùng lúc. '
                  'Cột = số người có mặt cùng lúc cao nhất trong giờ đó — dùng để xếp PT / lễ tân và tính sức chứa phòng tập.'),
          style: const TextStyle(fontSize: 12.5, color: SboxColors.slate700),
        ),
        const SizedBox(height: 8),
        for (final h in open)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(width: 64, child: Text('${h['hour']}h–${(h['hour'] as num) + 1}h',
                  style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]))),
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 14,
                      width: c.maxWidth * ((h['peakPresent'] as num? ?? 0) / maxPeak).clamp(0.02, 1.0),
                      decoration: BoxDecoration(
                        color: h['hour'] == busiest ? SboxColors.danger : SboxColors.brand500,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: Text(
                  // TB/ngày ít lượt bị làm tròn thành 0 → hiện tổng lượt trong kỳ.
                  tr('  ${h['peakPresent']} người cùng lúc · ${h['checkIns']} lượt'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ]),
          ),
        if (weekdays.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final w in weekdays)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(tr('${wd[(w['weekday'] as num).toInt()]}: ${w['avgPerDay']} lượt/ngày'),
                    style: const TextStyle(fontSize: 12)),
              ),
          ]),
        ],
        if ((m['byPackage'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          Text(tr('Hội viên theo thẻ / gói đang dùng'), style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final p in (m['byPackage'] as List))
            Text(tr('• ${(p as Map)['package']}: ${p['members']} hội viên'), style: const TextStyle(fontSize: 13)),
        ],
      ]),
    );
  }
}
