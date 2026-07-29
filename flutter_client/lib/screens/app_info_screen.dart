import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'settings_hub_screen.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class AppInfoScreen extends StatefulWidget {
  /// type: 'terms' | 'privacy' | 'help' | 'bugreport'
  final String type;
  const AppInfoScreen({super.key, required this.type});

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  bool _loading = true;
  String _title = '';
  String _content = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.type != 'bugreport') _loadPage();
  }

  Future<void> _loadPage() async {
    final api = ApiService();
    try {
      final res = await api.getAppPage(widget.type);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final pageData = res['data'] as Map<String, dynamic>? ?? {};
        setState(() {
          _title = pageData['title'] as String? ?? '';
          _content = pageData['content'] as String? ?? 'Chưa có nội dung.';
          _loading = false;
        });
      } else {
        setState(() {
          _error = res['message'] as String? ?? 'Không tải được nội dung.';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Không tải được nội dung.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.type == 'bugreport') {
      return _BugReportForm(onBack: () => SettingsHubScreen.goBack(context));
    }

    String appBarTitle;
    switch (widget.type) {
      case 'terms': appBarTitle = 'Điều khoản sử dụng'; break;
      case 'privacy': appBarTitle = 'Chính sách bảo mật'; break;
      case 'help': appBarTitle = 'Trợ giúp'; break;
      default: appBarTitle = _title;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(appBarTitle)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => SettingsHubScreen.goBack(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(tr(_error!), style: const TextStyle(color: Colors.red)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_title.isNotEmpty) ...[
                        Text(tr(_title),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                      ],
                      Text(tr(_content), style: const TextStyle(fontSize: 15, height: 1.6)),
                    ],
                  ),
                ),
    );
  }
}

class _BugReportForm extends StatefulWidget {
  final VoidCallback onBack;
  const _BugReportForm({required this.onBack});

  @override
  State<_BugReportForm> createState() => _BugReportFormState();
}

class _BugReportFormState extends State<_BugReportForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String _type = 'Bug';
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final api = ApiService();
    try {
      final res = await api.submitAppBugReport({
        'type': _type,
        'title': _titleCtrl.text.trim(),
        'content': _contentCtrl.text.trim(),
        'appVersion': '1.0.0',
        'deviceInfo': 'Flutter App',
      });
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        setState(() { _submitted = true; _submitting = false; });
      } else {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(res['message'] as String? ?? 'Gửi thất bại')), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Gửi thất bại: $e')), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Báo lỗi & Góp ý')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: _submitted
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 64),
                  const SizedBox(height: 16),
                  Text(tr('Cảm ơn bạn đã gửi phản hồi!'),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(tr('Chúng tôi sẽ xem xét và phản hồi sớm nhất có thể.'),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: widget.onBack,
                    child: Text(tr('Quay lại')),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr('Loại phản hồi'),
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: 'Bug', child: Text(tr('🐛 Báo lỗi'))),
                        DropdownMenuItem(value: 'Suggestion', child: Text(tr('💡 Góp ý / Đề xuất'))),
                        DropdownMenuItem(value: 'Other', child: Text(tr('📝 Khác'))),
                      ],
                      onChanged: (v) => setState(() => _type = v!),
                    ),
                    const SizedBox(height: 16),
                    Text(tr('Tiêu đề'),
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleCtrl,
                      decoration: InputDecoration(
                        hintText: tr('Mô tả ngắn gọn vấn đề...'),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tiêu đề' : null,
                    ),
                    const SizedBox(height: 16),
                    Text(tr('Nội dung chi tiết'),
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _contentCtrl,
                      maxLines: 6,
                      decoration: InputDecoration(
                        hintText: tr('Mô tả chi tiết lỗi, cách tái hiện, hoặc ý kiến góp ý...'),
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Vui lòng nhập nội dung' : null,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send),
                        label: Text(tr(_submitting ? 'Đang gửi...' : 'Gửi phản hồi')),
                        style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
