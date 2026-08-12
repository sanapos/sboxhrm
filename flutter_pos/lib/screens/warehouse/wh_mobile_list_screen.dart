import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/permission_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/warehouse/wh_doc_type.dart';
import '../../widgets/warehouse/wh_mobile_components.dart';
import '../../widgets/warehouse/wh_mobile_doc_service.dart';
import '../../widgets/warehouse/wh_mobile_theme.dart';
import 'wh_mobile_detail_screen.dart';
import 'wh_mobile_editor_router.dart';
import '../../l10n/app_tr.dart';

/// Danh sách phiếu kho — UI mobile mới, thống nhất cho mọi loại phiếu.
class WhMobileDocListScreen extends StatefulWidget {
  const WhMobileDocListScreen({super.key, required this.docType});

  final WhDocType docType;

  static void open(BuildContext context, WhDocType type) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PosHubScope(
          embeddedInHub: false,
          pushedSubPage: true,
          child: WhMobileDocListScreen(docType: type),
        ),
      ),
    );
  }

  @override
  State<WhMobileDocListScreen> createState() => _WhMobileDocListScreenState();
}

class _WhMobileDocListScreenState extends State<WhMobileDocListScreen> {
  final _svc = WhMobileDocService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<WhDocListItem> _items = [];
  int _total = 0;
  int _page = 1;
  String _statusFilter = 'all';

  WhDocType get _type => widget.docType;

  List<String> get _statuses => switch (_statusFilter) {
        'draft' => [_type.draftStatus],
        'done' => ['Completed'],
        'cancelled' => ['Cancelled'],
        _ => [_type.draftStatus, 'Completed', 'Cancelled'],
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    setState(() => _loading = true);
    final result = await _svc.loadList(
      _type,
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      statuses: _statuses,
      page: page,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _page = page;
      _items = result.items;
      _total = result.total;
    });
  }

  Future<void> _openCreate() async {
    final ok = await WhMobileEditorRouter.openCreate(context, _type);
    if (ok == true && mounted) _load(page: _page);
  }

  Future<void> _openItem(WhDocListItem item) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PosHubScope(
          embeddedInHub: false,
          pushedSubPage: true,
          child: WhMobileDocDetailScreen(docType: _type, docId: item.id),
        ),
      ),
    );
    if (ok == true && mounted) _load(page: _page);
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canEdit = perm.canEdit(_type.moduleCode) || perm.canEdit('PosProducts');

    return WhMobileScaffold(
      title: _type.listTitle,
      subtitle: '$_total phiếu',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          color: WhMobileTheme.primary,
          onPressed: _loading ? null : () => _load(page: _page),
        ),
      ],
      floatingAction: canEdit
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              backgroundColor: _type.accentColor,
              elevation: 0,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text(tr(_type.createLabel),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WhMobileTheme.padH,
              WhMobileTheme.gap,
              WhMobileTheme.padH,
              0,
            ),
            child: WhSearchField(
              controller: _searchCtrl,
              hint: 'Tìm mã phiếu, ghi chú…',
              onSubmitted: (_) => _load(),
              onChanged: (_) {},
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: WhMobileTheme.padH),
              children: [
                _FilterChip(label: 'Tất cả', value: 'all', group: _statusFilter, onSelect: () => _onFilter('all')),
                _FilterChip(label: _type.draftStatusLabel, value: 'draft', group: _statusFilter, onSelect: () => _onFilter('draft')),
                _FilterChip(label: 'Hoàn thành', value: 'done', group: _statusFilter, onSelect: () => _onFilter('done')),
                _FilterChip(label: 'Đã hủy', value: 'cancelled', group: _statusFilter, onSelect: () => _onFilter('cancelled')),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: LoadingWidget())
                : _items.isEmpty
                    ? WhEmptyState(
                        icon: _type.icon,
                        title: 'Chưa có phiếu',
                        subtitle: canEdit ? 'Bấm nút bên dưới để tạo phiếu mới' : null,
                        action: canEdit
                            ? FilledButton.icon(
                                onPressed: _openCreate,
                                style: WhMobileTheme.primaryButton(),
                                icon: const Icon(Icons.add_rounded, size: 20),
                                label: Text(tr(_type.createLabel)),
                              )
                            : null,
                      )
                    : RefreshIndicator(
                        onRefresh: () => _load(page: _page),
                        color: WhMobileTheme.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            WhMobileTheme.padH,
                            WhMobileTheme.gap,
                            WhMobileTheme.padH,
                            100,
                          ),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            return WhDocListTile(
                              docNo: item.docNo,
                              status: item.status,
                              draftLabel: _type.draftStatusLabel,
                              amountLabel: _svc.formatMoney(item.amount),
                              subtitle: item.subtitle,
                              meta: item.meta ?? '',
                              onTap: () => _openItem(item),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _onFilter(String v) {
    setState(() => _statusFilter = v);
    _load();
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.group,
    required this.onSelect,
  });

  final String label;
  final String value;
  final String group;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = group == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(tr(label)),
        selected: selected,
        onSelected: (_) => onSelect(),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? WhMobileTheme.primary : WhMobileTheme.textSecondary,
        ),
        backgroundColor: WhMobileTheme.surface,
        selectedColor: WhMobileTheme.primaryMuted,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
