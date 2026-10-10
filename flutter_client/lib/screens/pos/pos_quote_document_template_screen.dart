import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_commercial_a4_editor.dart';

import '../../theme/sbox_tokens.dart';

/// Sửa riêng TOÀN BỘ nội dung một chứng từ (báo giá / hợp đồng / bàn giao / nghiệm thu / đề nghị TT):
/// sửa trên mẫu còn trường động {…} → lời văn, điều khoản, bố cục là của riêng chứng từ này, còn hàng hóa,
/// số tiền, đợt thanh toán vẫn lấy từ báo giá hiện tại (không bao giờ thành «bản cũ»).
/// Mẫu chung, báo giá / hợp đồng khác không đổi.
class PosQuoteDocumentTemplateScreen extends StatefulWidget {
  const PosQuoteDocumentTemplateScreen({
    super.key,
    required this.quoteId,
    required this.document,
  });

  final String quoteId;
  final PosQuoteDocument document;

  @override
  State<PosQuoteDocumentTemplateScreen> createState() => _PosQuoteDocumentTemplateScreenState();
}

class _PosQuoteDocumentTemplateScreenState extends State<PosQuoteDocumentTemplateScreen> {
  final _api = ApiService();
  final _editorKey = GlobalKey<PosCommercialA4EditorState>();
  String? _html;
  bool _isCustom = false;
  bool _hadWording = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.getPosQuoteDocumentCustomTemplate(widget.quoteId, widget.document.id);
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Không mở được',
        message: res['message']?.toString() ?? tr('Không tải được nội dung chứng từ'),
      );
      return;
    }
    final d = Map<String, dynamic>.from(res['data'] as Map);
    setState(() {
      _html = (d['html'] ?? '').toString();
      _isCustom = d['isCustom'] == true;
      _hadWording = d['isCustomWording'] == true;
      _loading = false;
    });
  }

  Future<String?> _livePreview(String html) async {
    final res = await _api.previewPosQuoteDocument(
      widget.quoteId,
      widget.document.kind,
      docId: widget.document.id,
      templateHtml: html,
    );
    if (res['isSuccess'] != true || res['data'] is! Map) return null;
    return (res['data'] as Map)['htmlContent']?.toString();
  }

  Future<void> _save() async {
    if (_saving) return;
    final html = await _editorKey.currentState?.flushHtml() ?? _html ?? '';
    if (html.trim().isEmpty) return;
    if (_hadWording && !_isCustom) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Thay bản lời văn đã chốt?')),
          content: Text(tr(
              'Chứng từ này đang in theo bản lời văn đã chốt. Lưu nội dung riêng mới sẽ in theo bản này (số liệu tự cập nhật). '
              'Bản đã chốt vẫn khôi phục được ở «Lịch sử nội dung».')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _saving = true);
    final res = await _api.savePosQuoteDocumentCustomTemplate(widget.quoteId, widget.document.id, html);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Chưa lưu',
        message: res['message']?.toString() ?? tr('Không lưu được nội dung riêng'),
      );
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: 'Đã lưu nội dung riêng',
      message: tr('Chỉ chứng từ này đổi — số liệu vẫn theo báo giá. Mẫu chung và chứng từ khác giữ nguyên.'),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _clear() async {
    if (_saving || !_isCustom) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Về mẫu chung')),
        content: Text(tr(
            'Chứng từ này in lại theo mẫu chung / mẫu đã chọn. Nội dung riêng vẫn khôi phục được ở «Lịch sử nội dung».')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Về mẫu chung'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final res = await _api.clearPosQuoteDocumentCustomTemplate(widget.quoteId, widget.document.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Chưa đổi',
        message: res['message']?.toString() ?? tr('Không bỏ được nội dung riêng'),
      );
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    return Scaffold(
      appBar: AppBar(
        title: Text('${doc.docNo} · ${tr('Sửa riêng')} ${PosQuoteDocument.kindLabel(doc.kind).toLowerCase()}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isCustom)
            TextButton(
              onPressed: _saving || _loading ? null : _clear,
              child: Text(tr('Về mẫu chung')),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving || _loading || _html == null ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr('Lưu riêng')),
            ),
          ),
        ],
      ),
      body: _loading || _html == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: SboxColors.brand50,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      tr('Sửa thoải mái lời văn, điều khoản, bố cục của riêng chứng từ này. Các ô {…} là số liệu tự '
                          'lấy từ báo giá (hàng hóa, tiền, đợt thanh toán) — giữ lại để luôn đúng số. «Xem trước» dùng số '
                          'liệu thật. Mẫu chung và báo giá / hợp đồng khác không đổi.'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                Expanded(
                  child: PosCommercialA4Editor(
                    key: _editorKey,
                    html: _html!,
                    documentType: doc.kind,
                    paperSize: PosPrintPaperSizes.a4,
                    onChanged: (html) => _html = html,
                    livePreview: _livePreview,
                  ),
                ),
              ],
            ),
    );
  }
}
