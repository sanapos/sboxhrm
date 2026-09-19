import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_quote.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_quote_editor_screen.dart';

class PosQuoteListScreen extends StatefulWidget {
  const PosQuoteListScreen({super.key});

  @override
  State<PosQuoteListScreen> createState() => _PosQuoteListScreenState();
}

class _PosQuoteListScreenState extends State<PosQuoteListScreen> {
  final _search = TextEditingController();
  final _money = NumberFormat('#,##0', 'vi_VN');
  String? _status;
  bool _loading = true;
  String? _error;
  List<PosQuote> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<AuthProvider>().apiService;
    final res = await api.getPosQuotes(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      status: _status,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được báo giá';
      });
      return;
    }
    final data = res['data'];
    final raw = data is Map ? (data['items'] as List? ?? []) : <dynamic>[];
    setState(() {
      _loading = false;
      _items = raw
          .whereType<Map>()
          .map((e) => PosQuote.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });
  }

  Future<void> _openEditor([PosQuote? q]) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PosQuoteEditorScreen(quoteId: q?.id),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    if (!perm.canView('PosQuotes')) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Báo giá'))),
        body: Center(child: Text(tr('Không có quyền xem báo giá'))),
      );
    }
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Báo giá')),
        actions: [
          if (perm.canCreate('PosQuotes'))
            TextButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(tr('Tạo mới'),
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: PosTheme.inputDecoration(
                      label: 'Số BG / khách / SĐT',
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: _status,
                  hint: Text(tr('Trạng thái')),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tất cả')),
                    for (final s in const [
                      'Draft',
                      'Sent',
                      'Revised',
                      'Accepted',
                      'Rejected',
                      'Expired',
                      'Cancelled',
                    ])
                      DropdownMenuItem(
                        value: s,
                        child: Text(PosQuote.statusLabel(s)),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _status = v);
                    _load();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _items.isEmpty
                        ? Center(
                            child: Text(tr(
                                'Chưa có báo giá — tạo mới, không liên quan màn bán hàng')),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final q = _items[i];
                                final until = q.validUntil;
                                return Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  child: ListTile(
                                    title: Text(
                                      '${q.quoteNo} · ${q.customerName?.isNotEmpty == true ? q.customerName : 'Chưa chọn khách'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    subtitle: Text([
                                      PosQuote.statusLabel(q.status),
                                      if (q.status == 'Accepted')
                                        PosQuote.stageLabel(q.commercialStage),
                                      if (until != null)
                                        'Hạn ${DateFormat('dd/MM/yyyy').format(until.toLocal())}',
                                      '${_money.format(q.total)} đ',
                                    ].join('  ·  ')),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openEditor(q),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
