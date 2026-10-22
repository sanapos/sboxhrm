import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../notification_overlay.dart';

final _dmy = DateFormat('dd/MM/yyyy');

double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(',', '.'));

String _fmt(dynamic v, String unit) {
  final d = _num(v);
  if (d == null) return '';
  final s = d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
  return '$s$unit';
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
    final last = _items.isEmpty ? null : _items.first;
    final weight = TextEditingController();
    final height = TextEditingController(text: _fmt(last?['heightCm'], ''));
    final fat = TextEditingController();
    final muscle = TextEditingController();
    final waist = TextEditingController();
    final condition = TextEditingController();
    final goal = TextEditingController(text: '${last?['goal'] ?? ''}');
    Widget numField(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr(label), isDense: true, border: const OutlineInputBorder()),
          ),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đánh giá thể trạng · ${widget.name}')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [numField(weight, 'Cân nặng (kg)'), const SizedBox(width: 8), numField(height, 'Chiều cao (cm)')]),
              const SizedBox(height: 8),
              Row(children: [
                numField(fat, '% mỡ'),
                const SizedBox(width: 8),
                numField(muscle, 'Cơ (kg)'),
                const SizedBox(width: 8),
                numField(waist, 'Vòng eo (cm)'),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: condition,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText: tr('Tình trạng / chấn thương / nhận xét của PT'),
                    isDense: true,
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: goal,
                decoration: InputDecoration(
                    labelText: tr('Mục tiêu (giảm mỡ, tăng cơ…)'), isDense: true, border: const OutlineInputBorder()),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu đánh giá'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.addGymAssessment(widget.customerId, {
      'weightKg': _num(weight.text),
      'heightCm': _num(height.text),
      'bodyFatPercent': _num(fat.text),
      'muscleKg': _num(muscle.text),
      'waistCm': _num(waist.text),
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

  /// Chênh lệch so với lần đo trước (mũi tên + số), giúp PT / khách thấy tiến bộ.
  String _delta(String key, int index, String unit) {
    if (index + 1 >= _items.length) return '';
    final now = _num(_items[index][key]);
    final prev = _num(_items[index + 1][key]);
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
        Text(tr('PT & thể trạng · ${widget.name}'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
              child: Text(tr('Đánh giá thể trạng (${_items.length})'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            FilledButton.icon(
              onPressed: _addAssessment,
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Thêm đánh giá')),
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
      if (_num(a['waistCm']) != null) 'Eo ${_fmt(a['waistCm'], 'cm')}${_delta('waistCm', i, 'cm')}',
    ];
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
              tr([if (at != null) _dmy.format(at), if ('${a['trainerName'] ?? ''}'.isNotEmpty) 'PT ${a['trainerName']}']
                  .join(' · ')),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (metrics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr(metrics.join(' · ')), style: const TextStyle(fontSize: 13)),
              ),
            if ('${a['condition'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('Tình trạng: ${a['condition']}'),
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
                  tr('  ${h['peakPresent']} người cùng lúc · ${h['avgCheckInsPerDay']} lượt/ngày'),
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
