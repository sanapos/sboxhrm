import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'notification_overlay.dart';

/// Reusable AI text-assist bottom sheet.
///
/// Hiển thị 1 sheet cho phép user mô tả, chọn tone, AI trả về văn bản.
/// Người dùng có thể "Áp dụng" để chèn text vào controller, hoặc "Sao chép".
///
/// Cách dùng:
/// ```dart
/// await showAiAssistSheet(
///   context,
///   kind: 'feedback',
///   title: 'AI soạn phản ánh',
///   targetController: _contentCtrl,
///   contextText: 'Phản ánh về: $category',
/// );
/// ```
Future<String?> showAiAssistSheet(
  BuildContext context, {
  required String kind,
  String title = 'AI hỗ trợ soạn thảo',
  TextEditingController? targetController,
  String? contextText,
  String initialPrompt = '',
  String defaultTone = 'professional',
  int maxTokens = 1024,
  /// Callback nhận text sinh ra (thay vì/cộng thêm set vào controller).
  void Function(String text)? onApply,
}) async {
  return await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiAssistSheet(
      kind: kind,
      title: title,
      targetController: targetController,
      contextText: contextText,
      initialPrompt: initialPrompt,
      defaultTone: defaultTone,
      maxTokens: maxTokens,
      onApply: onApply,
    ),
  );
}

class _AiAssistSheet extends StatefulWidget {
  final String kind;
  final String title;
  final TextEditingController? targetController;
  final String? contextText;
  final String initialPrompt;
  final String defaultTone;
  final int maxTokens;
  final void Function(String text)? onApply;

  const _AiAssistSheet({
    required this.kind,
    required this.title,
    this.targetController,
    this.contextText,
    this.initialPrompt = '',
    this.defaultTone = 'professional',
    this.maxTokens = 1024,
    this.onApply,
  });

  @override
  State<_AiAssistSheet> createState() => _AiAssistSheetState();
}

class _AiAssistSheetState extends State<_AiAssistSheet> {
  final _api = ApiService();
  final _promptCtrl = TextEditingController();
  final _resultCtrl = TextEditingController();
  String _tone = 'professional';
  bool _isGenerating = false;

  static const _tones = [
    ('professional', 'Chuyên nghiệp'),
    ('formal', 'Trang trọng'),
    ('friendly', 'Thân thiện'),
    ('concise', 'Ngắn gọn'),
    ('empathetic', 'Đồng cảm'),
  ];

  @override
  void initState() {
    super.initState();
    _tone = widget.defaultTone;
    _promptCtrl.text = widget.initialPrompt;
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _resultCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) {
      NotificationOverlayManager().showWarning(
          title: 'Thiếu nội dung',
          message: 'Vui lòng mô tả điều bạn muốn AI viết');
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final res = await _api.aiAssist(
        kind: widget.kind,
        prompt: prompt,
        context: widget.contextText,
        tone: _tone,
        maxTokens: widget.maxTokens,
      );
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] != null) {
        final text = (res['data']['text'] ?? '').toString();
        setState(() => _resultCtrl.text = text);
      } else {
        NotificationOverlayManager().showError(
            title: 'Lỗi AI',
            message: res['message']?.toString() ?? 'Không tạo được nội dung');
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _apply({bool append = false}) {
    final text = _resultCtrl.text.trim();
    if (text.isEmpty) return;
    if (widget.onApply != null) {
      widget.onApply!(text);
    } else if (widget.targetController != null) {
      if (append && widget.targetController!.text.trim().isNotEmpty) {
        widget.targetController!.text =
            '${widget.targetController!.text.trimRight()}\n\n$text';
      } else {
        widget.targetController!.text = text;
      }
    }
    Navigator.pop(context, text);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _resultCtrl.text));
    if (mounted) {
      NotificationOverlayManager()
          .showSuccess(title: 'Đã sao chép', message: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: EdgeInsets.only(bottom: viewInsets),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome,
                          color: Color(0xFF8B5CF6), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _promptCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Mô tả nội dung muốn AI viết *',
                        hintText: 'VD: Phản ánh về bữa trưa hôm nay ít rau...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Giọng văn',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _tones.map((t) {
                        final selected = _tone == t.$1;
                        return ChoiceChip(
                          label: Text(t.$2),
                          selected: selected,
                          onSelected: (_) => setState(() => _tone = t.$1),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isGenerating ? null : _generate,
                        icon: _isGenerating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.auto_awesome, size: 18),
                        label: Text(_isGenerating
                            ? 'Đang tạo...'
                            : (_resultCtrl.text.isEmpty
                                ? 'Tạo nội dung'
                                : 'Tạo lại')),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_resultCtrl.text.isNotEmpty) ...[
                      Row(
                        children: [
                          Text('Kết quả AI',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _copy,
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Sao chép'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _resultCtrl,
                        maxLines: null,
                        minLines: 6,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (widget.targetController != null ||
                          widget.onApply != null)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _apply(append: true),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Nối vào'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _apply(append: false),
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('Áp dụng'),
                              ),
                            ),
                          ],
                        ),
                    ] else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.tips_and_updates_outlined,
                                color: Colors.grey[600], size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Nhập mô tả ngắn về điều bạn muốn viết, AI sẽ soạn giúp bạn bằng tiếng Việt.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact AI icon button – dùng để gắn vào đầu TextField.
class AiAssistIconButton extends StatelessWidget {
  final String kind;
  final String title;
  final TextEditingController? targetController;
  final String Function()? contextBuilder;
  final String? tooltip;
  final double size;
  final void Function(String text)? onApply;

  const AiAssistIconButton({
    super.key,
    required this.kind,
    this.title = 'AI soạn thảo',
    this.targetController,
    this.contextBuilder,
    this.tooltip,
    this.size = 20,
    this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip ?? 'AI hỗ trợ soạn thảo',
      iconSize: size,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size + 16, height: size + 16),
      icon: const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6)),
      onPressed: () => showAiAssistSheet(
        context,
        kind: kind,
        title: title,
        targetController: targetController,
        contextText: contextBuilder?.call(),
        onApply: onApply,
      ),
    );
  }
}
