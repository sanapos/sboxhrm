import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/pos/pos_theme.dart';

/// Điều khoản / chính sách / trợ giúp — cùng API app-pages với HRM.
class PosAppInfoScreen extends StatefulWidget {
  const PosAppInfoScreen({super.key, required this.type});

  /// `terms` | `privacy` | `help`
  final String type;

  @override
  State<PosAppInfoScreen> createState() => _PosAppInfoScreenState();
}

class _PosAppInfoScreenState extends State<PosAppInfoScreen> {
  bool _loading = true;
  String _title = '';
  String _content = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _fallbackTitle => switch (widget.type) {
        'terms' => 'Điều khoản sử dụng',
        'privacy' => 'Chính sách bảo mật',
        'help' => 'Trợ giúp',
        _ => 'Thông tin',
      };

  Future<void> _load() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.getAppPage(widget.type);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final data = res['data'] is Map
            ? Map<String, dynamic>.from(res['data'] as Map)
            : <String, dynamic>{};
        setState(() {
          _title = (data['title'] ?? '').toString();
          _content = (data['content'] ?? 'Chưa có nội dung.').toString();
          _loading = false;
        });
      } else {
        setState(() {
          _error = res['message']?.toString() ?? 'Không tải được nội dung.';
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Không tải được nội dung.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr(_title.isEmpty ? _fallbackTitle : _title)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(
                    tr(_error!),
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    tr(_content),
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: PosTheme.textPrimary,
                    ),
                  ),
                ),
    );
  }
}
