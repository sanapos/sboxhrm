import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import '../services/ai_token_usage_api.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';

/// «Token AI đã dùng» trong Thiết lập SBOX › Trợ lý AI: mỗi lời gọi Gemini tốn bao nhiêu token, tách theo
/// tính năng / ngày / mô hình. Token «suy nghĩ» không nằm trong câu trả lời nhưng vẫn tính tiền nên hiện riêng.
class AiTokenUsageSection extends StatefulWidget {
  const AiTokenUsageSection({super.key, this.api});

  final AiTokenUsageApi? api;

  @override
  State<AiTokenUsageSection> createState() => _AiTokenUsageSectionState();
}

class _AiTokenUsageSectionState extends State<AiTokenUsageSection> {
  late final AiTokenUsageApi _api = widget.api ?? AiTokenUsageApi();

  static const _periods = <int>[7, 30];

  /// Đường dẫn API → tên tính năng cho người dùng. Chỗ nào chưa có tên thì hiện nguyên đường dẫn.
  static const _featureNames = <String, String>{
    '/api/ai/assistant/chat': 'Trợ lý AI',
    '/api/ai/assistant/chat/stream': 'Trợ lý AI',
    '/api/ai/assistant/speak': 'Đọc thành giọng nói',
    '/api/ai/assistant/transcribe': 'Gõ bằng giọng nói',
    '/api/ai/assistant/read-order': 'Đọc đơn từ ảnh',
    '/api/ai/assist': 'Soạn nội dung',
    '/api/ai/morning-brief': 'Bản tin sáng',
    '/api/communications/ai/generate': 'Soạn thông báo nội bộ',
    '/api/communications/ai/generate-stream': 'Soạn thông báo nội bộ',
    '/api/communications/ai/test': 'Kiểm tra khóa',
    '/api/pos/ai/menu/scan': 'Thêm menu bằng ảnh',
    '/api/pos/ai/menu/scan-sheet': 'Thêm menu bằng bảng',
    '/api/pos/ai/menu/import': 'Thêm menu bằng ảnh',
    '/api/pos/ai/purchase-invoice/scan': 'Quét hóa đơn nhập',
    '/api/pos/ai/purchase-invoice/confirm': 'Quét hóa đơn nhập',
    '/api/pos/print-templates/ai-edit': 'Sửa mẫu in bằng AI',
    '/api/pos/print-templates/docx/import': 'Nhập mẫu Word',
  };

  int _days = 30;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _totals = const {};
  List<Map<String, dynamic>> _byDay = const [];
  List<Map<String, dynamic>> _byFeature = const [];
  List<Map<String, dynamic>> _byModel = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.report(days: _days);
    if (!mounted) return;
    if (r['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = r['message']?.toString() ?? 'Không tải được số liệu token';
      });
      return;
    }
    final d = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : const <String, dynamic>{};
    setState(() {
      _loading = false;
      _totals = d['totals'] is Map ? Map<String, dynamic>.from(d['totals'] as Map) : const {};
      _byDay = _list(d['byDay']);
      _byFeature = _list(d['byFeature']);
      _byModel = _list(d['byModel']);
    });
  }

  static List<Map<String, dynamic>> _list(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  static int _n(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  String _featureLabel(String key) => tr(_featureNames[key] ?? key);

  /// «2026-11-14» → «14/11».
  static String _dayLabel(String key) {
    final p = key.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}' : key;
  }

  int get _total => _n(_totals['totalTokens']);
  int get _calls => _n(_totals['calls']);

  @override
  Widget build(BuildContext context) => SettingsSection(
        title: 'Token AI đã dùng',
        subtitle: 'Mỗi lời gọi AI tốn bao nhiêu token — xem chỗ nào ngốn nhiều nhất',
        icon: Icons.data_usage_rounded,
        trailing: SboxButton.ghost(
          label: 'Tải lại',
          icon: Icons.refresh_rounded,
          loading: _loading,
          onPressed: _loading ? null : _load,
        ),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final d in _periods)
                ChoiceChip(
                  label: Text(tr('$d ngày')),
                  selected: _days == d,
                  onSelected: _loading
                      ? null
                      : (v) {
                          if (!v || _days == d) return;
                          setState(() => _days = d);
                          _load();
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
          else if (_error != null)
            SettingsNote(_error!, icon: Icons.error_outline_rounded, tone: SboxTone.danger)
          else if (_calls == 0)
            const SettingsNote(
              'Chưa có lượt gọi AI nào trong khoảng này. Số liệu chỉ tính từ lúc máy chủ bật ghi nhận token.',
              icon: Icons.info_outline_rounded,
              tone: SboxTone.neutral,
            )
          else ...[
            _summary(),
            const SizedBox(height: 14),
            _bars('Theo tính năng', _byFeature, _featureLabel),
            _bars('Theo ngày', _byDay.reversed.take(10).toList().reversed.toList(), _dayLabel),
            _bars('Theo mô hình', _byModel, (k) => k),
            const SettingsNote(
              'Token «suy nghĩ» là phần mô hình tự nghĩ trước khi trả lời: không hiện ra câu trả lời nhưng vẫn tính tiền.',
              icon: Icons.psychology_outlined,
              tone: SboxTone.neutral,
            ),
          ],
        ],
      );

  Widget _summary() {
    final prompt = _n(_totals['promptTokens']);
    final answer = _n(_totals['answerTokens']);
    final thought = _n(_totals['thoughtTokens']);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SboxColors.slate50,
        border: Border.all(color: SboxColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(SboxFmt.number(_total),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: SboxColors.brand600)),
        Text(tr('token · $_calls lượt gọi trong $_days ngày'),
            style: const TextStyle(fontSize: 13, color: SboxColors.slate600)),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _part('Gửi đi', prompt),
          _part('Trả về', answer),
          _part('Suy nghĩ', thought),
        ]),
      ]),
    );
  }

  Widget _part(String label, int value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr(label), style: const TextStyle(fontSize: 11, color: SboxColors.slate600)),
          Text(SboxFmt.number(value), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _bars(String title, List<Map<String, dynamic>> rows, String Function(String) label) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final max = rows.map((r) => _n(r['totalTokens'])).fold<int>(1, (a, b) => b > a ? b : a);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(tr(title), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
      for (final r in rows) _bar(label(r['key']?.toString() ?? ''), _n(r['totalTokens']), _n(r['calls']), max),
      const SizedBox(height: 14),
    ]);
  }

  Widget _bar(String label, int value, int calls, int max) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text(SboxFmt.number(value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(tr('($calls lượt)'), style: const TextStyle(fontSize: 11, color: SboxColors.slate600)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: max <= 0 ? 0 : value / max,
              minHeight: 6,
              backgroundColor: SboxColors.slate100,
              valueColor: const AlwaysStoppedAnimation(SboxColors.brand600),
            ),
          ),
        ]),
      );
}
