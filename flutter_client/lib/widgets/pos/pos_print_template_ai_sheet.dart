import 'package:flutter/material.dart';

import '../../models/pos_print_template.dart';
import '../../models/pos_print_template_v2.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Kết quả AI sửa mẫu — chưa lưu; trình soạn áp dụng như một bước sửa (hoàn tác được).
class PosPrintTemplateAiResult {
  const PosPrintTemplateAiResult(this.template, this.summary, this.warnings);
  final PosPrintTemplateV2 template;
  final String summary;
  final List<String> warnings;
}

/// Trường được dùng theo loại chứng từ — gửi AI để không bịa tên trường.
({List<(String, String)> fields, List<(String, String)> line, List<(String, String)> totals}) posPrintAiFieldSets(
    String documentType) {
  final isLabel = PosPrintPaperSizes.isLabelDoc(documentType);
  final fields = <(String, String)>[
    if (documentType == PosPrintDocumentTypes.scaleLabel) ...PosPrintTokens.scaleLabel,
    if (documentType == PosPrintDocumentTypes.specLabel || documentType == PosPrintDocumentTypes.barcodeLabel)
      ...PosPrintTokens.specLabel,
    ...PosPrintTokens.store,
    ...PosPrintTokens.order,
    ...PosPrintTokens.customer,
    if (isLabel) ...PosPrintTokens.label,
    ...PosPrintTokens.totals,
  ];
  final seen = <String>{};
  return (
    fields: [for (final f in fields) if (seen.add(f.$1)) f],
    line: PosPrintTokens.line,
    totals: PosPrintTokens.totals,
  );
}

/// Gợi ý bấm nhanh theo loại phiếu.
List<String> posPrintAiSuggestions(PosPrintTemplateV2 t) {
  if (PosPrintPaperSizes.isLabelDoc(t.documentType)) {
    return const [
      'Tên hàng to và đậm hơn',
      'Giá bán in to, căn giữa',
      'Bỏ mã vạch, chỉ giữ tên và giá',
      'Thêm tên cửa hàng nhỏ ở trên cùng',
    ];
  }
  if (t.documentType == PosPrintDocumentTypes.kitchenSlip || t.documentType == PosPrintDocumentTypes.kitchenVoid) {
    return const [
      'Tên món và số bàn to hơn để bếp dễ đọc',
      'Gọn lại, tiết kiệm giấy',
      'Thêm giờ gửi và người gửi',
    ];
  }
  return [
    'Tên cửa hàng to, đậm, căn giữa',
    'Chữ tổng cộng to và đậm hơn',
    'Thêm dòng «Cảm ơn quý khách, hẹn gặp lại!» ở cuối',
    'Thêm Wi-Fi ở cuối bill: tên mạng … mật khẩu …',
    'Gọn lại, tiết kiệm giấy',
    if (t.paperSize == PosPrintPaperSizes.k80) 'Chữ to hơn cho dễ đọc',
    'Thêm số điện thoại và địa chỉ khách hàng',
    'Thêm mã QR thanh toán dưới phần tổng',
  ];
}

/// Logo base64 có thể vài trăm KB — thay bằng chuỗi giữ chỗ trước khi gửi AI, trả lại sau.
(Map<String, dynamic>, Map<String, String>) posPrintAiStripImages(PosPrintTemplateV2 t) {
  final json = t.toJson();
  final images = <String, String>{};
  final blocks = (json['blocks'] as List).cast<Map<String, dynamic>>();
  for (final b in blocks) {
    final data = b['imageData'];
    if (data is String && data.isNotEmpty) {
      final key = '__IMAGE_${images.length}__';
      images[key] = data;
      b['imageData'] = key;
    }
  }
  return (json, images);
}

/// Đọc mẫu AI trả: khôi phục logo, giữ khổ / loại chứng từ, cảnh báo trường lạ.
PosPrintTemplateAiResult posPrintAiParseResult(
  Map<String, dynamic> data,
  PosPrintTemplateV2 original,
  Map<String, String> images,
) {
  final raw = Map<String, dynamic>.from(data['template'] as Map);
  final blocks = ((raw['blocks'] as List?) ?? const []).whereType<Map>().map((b) {
    final m = Map<String, dynamic>.from(b);
    final img = m['imageData'];
    if (img is String && img.startsWith('__IMAGE_')) {
      final real = images[img];
      if (real == null) {
        m.remove('imageData');
      } else {
        m['imageData'] = real;
      }
    }
    if (m['style'] is Map) m['style'] = Map<String, dynamic>.from(m['style'] as Map);
    if (m['rightStyle'] is Map) m['rightStyle'] = Map<String, dynamic>.from(m['rightStyle'] as Map);
    return m;
  }).toList();
  raw['blocks'] = blocks;
  final parsed = PosPrintTemplateV2.fromJson(raw);
  final tpl = parsed.copyWith(
    paperSize: original.paperSize,
    documentType: original.documentType,
    printerProfile: original.printerProfile,
    name: original.name,
    blocks: parsed.blocks
        .map((b) => b.copyWith(style: b.style.copyWith(fontSize: b.style.fontSize.clamp(12.0, 72.0))))
        .toList(),
  );

  final sets = posPrintAiFieldSets(original.documentType);
  final known = {
    for (final f in [...sets.fields, ...sets.line, ...sets.totals, ...PosPrintTokens.label]) f.$1,
    'SDT',
    'Gio',
  };
  final unknown = <String>{};
  void check(String? f) {
    if (f != null && f.isNotEmpty && !known.contains(f)) unknown.add(f);
  }

  for (final b in tpl.blocks) {
    check(b.field);
    check(b.leftField);
    check(b.rightField);
    for (final f in b.fields ?? const <String>[]) {
      check(f);
    }
  }
  final warnings = [
    ...((data['warnings'] as List?) ?? const []).map((e) => e.toString()),
    if (unknown.isNotEmpty) 'Trường lạ sẽ in trống: ${unknown.join(', ')}',
  ];
  final summary = (data['summary'] ?? '').toString().trim();
  return PosPrintTemplateAiResult(tpl, summary.isEmpty ? 'Đã sửa mẫu theo yêu cầu.' : summary, warnings);
}

/// Tấm «AI sửa nhanh»: gõ hoặc bấm gợi ý → AI trả mẫu đã sửa (chưa lưu).
Future<PosPrintTemplateAiResult?> showPosPrintTemplateAiSheet(
  BuildContext context, {
  required PosPrintTemplateV2 template,
}) {
  return showModalBottomSheet<PosPrintTemplateAiResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _AiSheet(template: template),
  );
}

class _AiSheet extends StatefulWidget {
  const _AiSheet({required this.template});
  final PosPrintTemplateV2 template;

  @override
  State<_AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends State<_AiSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final instruction = (text ?? _ctrl.text).trim();
    if (instruction.isEmpty || _busy) return;
    if (text != null) _ctrl.text = text;
    setState(() {
      _busy = true;
      _error = null;
    });
    final (json, images) = posPrintAiStripImages(widget.template);
    final sets = posPrintAiFieldSets(widget.template.documentType);
    List<Map<String, String>> list(List<(String, String)> l) => [for (final f in l) {'key': f.$1, 'label': f.$2}];
    final res = await ApiService().aiEditPosPrintTemplate({
      'instruction': instruction,
      'template': json,
      'fields': list(sets.fields),
      'lineFields': list(sets.line),
      'totalsFields': list(sets.totals),
    });
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map && (res['data'] as Map)['template'] is Map) {
      try {
        final result = posPrintAiParseResult(Map<String, dynamic>.from(res['data'] as Map), widget.template, images);
        Navigator.of(context).pop(result);
        return;
      } catch (e) {
        setState(() {
          _busy = false;
          _error = tr('AI trả mẫu lỗi — thử lại hoặc diễn đạt khác.');
        });
        return;
      }
    }
    setState(() {
      _busy = false;
      _error = (res['message'] ?? '').toString().trim().isEmpty
          ? tr('Không gọi được AI — kiểm tra mạng rồi thử lại.')
          : res['message'].toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = posPrintAiSuggestions(widget.template);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.auto_awesome, color: SboxColors.brand600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('AI sửa nhanh mẫu in'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              tr('Nói điều muốn đổi — AI sửa ngay trên bản xem trước. Chưa lưu cho tới khi bấm Lưu, sai thì Hoàn tác.'),
              style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('ai-print-instruction'),
              controller: _ctrl,
              enabled: !_busy,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: tr('vd. Tên quán to hơn, thêm wifi «sbox123» ở cuối, bỏ dòng mã đơn'),
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            // Một hàng cuộn ngang: điện thoại nhỏ (V2s) vẫn thấy nút gửi bên dưới.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(tr(s), style: const TextStyle(fontSize: 12)),
                        // Gợi ý còn chỗ «…» cần điền: chỉ điền sẵn vào ô để sửa, không gửi ngay.
                        onPressed: _busy
                            ? null
                            : () => s.contains('…') ? _ctrl.text = tr(s) : _send(tr(s)),
                      ),
                    ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('ai-print-send'),
              onPressed: _busy ? null : () => _send(),
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(tr(_busy ? 'AI đang sửa…' : 'Sửa bằng AI')),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
          ],
        ),
      ),
    );
  }
}
