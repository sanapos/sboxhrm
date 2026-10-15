import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../models/downloaded_document.dart';
import '../services/downloaded_documents_service.dart';
import '../utils/responsive_helper.dart';
import '../utils/share_origin.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_collapsible_overview.dart';
import '../widgets/page_top_actions.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/safe_layout_widgets.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/app_scroll_safe.dart';
import '../widgets/hrm_mini_stat_chip.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../theme/sbox_tokens.dart';
const _theme = HrmPageChrome.primaryNavy;

class DownloadedDocumentsScreen extends StatefulWidget {
  const DownloadedDocumentsScreen({super.key});

  @override
  State<DownloadedDocumentsScreen> createState() =>
      _DownloadedDocumentsScreenState();
}

class _DownloadedDocumentsScreenState extends State<DownloadedDocumentsScreen> {
  final _svc = DownloadedDocumentsService.instance;
  final _fmt = DateFormat('dd/MM/yyyy HH:mm');
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _showOverviewPanel = true;
  String _category = DownloadDocCategories.all;
  String _fileType = DownloadFileKinds.all;
  String _datePreset = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  DownloadSort _sort = DownloadSort.newest;
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;
  bool get _hasFilter =>
      _category != DownloadDocCategories.all ||
      _fileType != DownloadFileKinds.all ||
      _datePreset != 'all' ||
      _searchCtrl.text.trim().isNotEmpty;

  static const _sortLabels = {
    DownloadSort.newest: 'Mới nhất',
    DownloadSort.oldest: 'Cũ nhất',
    DownloadSort.name: 'Tên A → Z',
    DownloadSort.size: 'Dung lượng lớn nhất',
  };

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      await _svc.ensureLoaded(force: true);
    } catch (e) {
      debugPrint('DownloadedDocumentsScreen._reload: $e');
      if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: tr('Không tải được danh sách tài liệu'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyDatePreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _datePreset = preset;
      switch (preset) {
        case 'today':
          _dateFrom = today;
          _dateTo = today;
          break;
        case 'week':
          _dateFrom = today.subtract(Duration(days: today.weekday - 1));
          _dateTo = today;
          break;
        case 'month':
          _dateFrom = DateTime(today.year, today.month, 1);
          _dateTo = today;
          break;
        case 'all':
        default:
          _dateFrom = null;
          _dateTo = null;
      }
    });
  }

  List<DownloadedDocument> get _filtered => _svc.filter(
        category: _category,
        type: _fileType,
        from: _dateFrom,
        to: _dateTo,
        search: _searchCtrl.text,
        sort: _sort,
      );

  Future<void> _open(DownloadedDocument doc) async {
    if (kIsWeb) {
      NotificationOverlayManager().showWarning(
        title: 'Mở tệp',
        message: tr('Trên web vui lòng mở từ thư mục Tải về trình duyệt.'),
      );
      return;
    }
    final result = await OpenFilex.open(doc.localPath, type: doc.mimeType);
    if (result.type != ResultType.done && mounted) {
      NotificationOverlayManager().showError(
        title: 'Không mở được',
        message: result.message,
      );
    }
  }

  Future<void> _share(DownloadedDocument doc) async {
    if (kIsWeb) return;
    try {
      await Share.shareXFiles(
        [XFile(doc.localPath, mimeType: doc.mimeType, name: doc.fileName)],
        text: doc.displayName,
        // iPad / iPhone ném lỗi nếu thiếu điểm neo hộp chia sẻ.
        sharePositionOrigin: shareOriginRect(),
      );
    } catch (e) {
      debugPrint('share document: $e');
      if (mounted) {
        NotificationOverlayManager().showError(
            title: 'Không chia sẻ được', message: tr('Thử lại sau hoặc mở tệp rồi chia sẻ từ ứng dụng xem tệp'));
      }
    }
  }

  Future<void> _importPublic() async {
    final n = await _svc.importFromPublicFolders();
    if (!mounted) return;
    setState(() {});
    NotificationOverlayManager().showSuccess(
      title: 'Nhập tệp',
      message: tr(n > 0 ? 'Đã nhập thêm $n tệp từ thư mục SBOX HRM' : 'Không có tệp mới trong thư mục SBOX HRM'),
    );
  }

  Future<void> _rename(DownloadedDocument doc) async {
    final ctrl = TextEditingController(text: doc.displayName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Đổi tên tệp')),
        content: TextField(
          controller: ctrl,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: tr('Tên hiển thị'),
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final success = await _svc.rename(doc.id, ctrl.text.trim());
    ctrl.dispose();
    if (!mounted) return;
    if (success) {
      setState(() {});
      NotificationOverlayManager()
          .showSuccess(title: 'Đã đổi tên', message: tr('Cập nhật thành công'));
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: tr('Không đổi được tên'));
    }
  }

  Future<void> _delete(List<DownloadedDocument> docs) async {
    if (docs.isEmpty) return;
    final hasPublic = !kIsWeb && docs.any((d) => d.externalUri != null);
    var alsoPublic = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => ScrollableAlertDialog(
          title: Text(tr(docs.length == 1 ? 'Xóa tệp' : 'Xóa ${docs.length} tệp')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(docs.length == 1
                ? tr('Xóa "${docs.first.displayName}" khỏi danh sách quản lý?')
                : tr('Xóa ${docs.length} tệp đã chọn khỏi danh sách quản lý?')),
            if (hasPublic) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: alsoPublic,
                onChanged: (v) => setD(() => alsoPublic = v ?? false),
                title: Text(tr('Xóa luôn bản trong thư mục Tải xuống')),
                subtitle: Text(tr(alsoPublic
                    ? 'Tệp sẽ mất hẳn khỏi máy.'
                    : 'Bản trong Tải xuống được giữ lại và sẽ không bị nhập lại vào danh sách.')),
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Xóa')),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    await _svc.deleteMany(docs.map((d) => d.id), deletePublicCopy: alsoPublic);
    if (!mounted) return;
    setState(() => _selected.removeAll(docs.map((d) => d.id)));
  }

  void _toggleSelect(DownloadedDocument doc) =>
      setState(() => _selected.contains(doc.id) ? _selected.remove(doc.id) : _selected.add(doc.id));

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconFor(DownloadedDocument doc) {
    if (doc.isImage) return Icons.image_rounded;
    if (doc.isExcel) return Icons.table_chart_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _iconColor(DownloadedDocument doc) {
    if (doc.isImage) return SboxColors.brand600;
    if (doc.isExcel) return SboxColors.success;
    return SboxColors.slate500;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final list = _filtered;

    return RegisterPageTopActions(
      actions: _selecting
          ? [
              HrmTopBarAction(
                icon: Icons.delete_outline,
                label: 'Xóa ${_selected.length} tệp đã chọn',
                onPressed: () => _delete(_svc.items.where((d) => _selected.contains(d.id)).toList()),
              ),
              HrmTopBarAction(icon: Icons.close_rounded, label: 'Bỏ chọn', onPressed: () => setState(_selected.clear)),
            ]
          : [
              if (!kIsWeb && _svc.isImportSupported)
                HrmTopBarAction(
                  icon: Icons.download_for_offline_outlined,
                  label: 'Nhập từ thư mục SBOX HRM',
                  onPressed: _importPublic,
                ),
              HrmTopBarAction(icon: Icons.sync_rounded, label: 'Làm mới', onPressed: _reload),
            ],
      child: Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: _svc.items.isEmpty || list.isEmpty
                        ? ListView(
                            children: [
                              if (_svc.items.isNotEmpty)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(isMobile ? 10 : 16, 8, isMobile ? 10 : 16, 0),
                                  child: _buildOverviewSection(0),
                                ),
                              const SizedBox(height: 80),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24),
                                  child: Column(children: [
                                    Text(
                                      tr(kIsWeb
                                          ? 'Trên web, tệp xuất Excel/ảnh được tải thẳng vào thư mục Tải về của trình duyệt.\nMở thư mục Downloads để xem — danh sách trong app chỉ có trên điện thoại/máy tính cài app.'
                                          : _svc.items.isEmpty
                                              ? 'Chưa có tệp tải xuống.\nXuất Excel/PDF/ảnh từ báo cáo sẽ hiện tại đây.'
                                              : 'Không có tệp nào khớp bộ lọc.'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: SboxColors.slate500),
                                    ),
                                    if (_svc.items.isNotEmpty && _hasFilter) ...[
                                      const SizedBox(height: 12),
                                      OutlinedButton(onPressed: _clearFilters, child: Text(tr('Bỏ bộ lọc'))),
                                    ],
                                  ]),
                                ),
                              ),
                            ],
                          )
                        : ListView(
                            padding: EdgeInsets.fromLTRB(
                                isMobile ? 10 : 16, 8, isMobile ? 10 : 16, 24),
                            children: [
                              _buildOverviewSection(list.length),
                              const SizedBox(height: 12),
                              ...list.map(_buildFileCard),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildOverviewSection(int visibleCount) {
    final total = _svc.items.length;
    final excel = _svc.items.where((e) => e.isExcel).length;
    final docs = _svc.items.where((e) => e.isPdf || e.isWord || e.isCsv).length;
    final images = _svc.items.where((e) => e.isImage).length;

    return HrmCollapsibleOverview(
      expanded: _showOverviewPanel,
      onToggle: () =>
          setState(() => _showOverviewPanel = !_showOverviewPanel),
      trailing: Text(
        tr('$visibleCount/$total'),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: PosTheme.kiotBlue,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HrmPageChrome.horizontalStatCards(
            cards: [
              _statCard('Tổng tệp', '$total', Icons.folder_open),
              _statCard('Excel', '$excel', Icons.table_chart),
              _statCard('PDF/Word/CSV', '$docs', Icons.description),
              _statCard('Ảnh', '$images', Icons.image),
              _statCard('Dung lượng', _formatSize(_svc.totalBytes), Icons.sd_storage_outlined),
            ],
            minCardWidth: 100,
            gap: 8,
          ),
          const SizedBox(height: 10),
          _buildFilterBar(),
          const SizedBox(height: 6),
          Text(
            tr('Bản trong app tự dọn sau ${DownloadedDocumentsService.retentionDays} ngày hoặc khi quá ${DownloadedDocumentsService.maxStoredBytes ~/ (1024 * 1024)} MB; bản ở thư mục Tải xuống không bị xóa trừ khi bạn chọn xóa cả hai.'),
            style: const TextStyle(fontSize: 11, color: SboxColors.slate500),
          ),
        ],
      ),
    );
  }

  void _clearFilters() => setState(() {
        _category = DownloadDocCategories.all;
        _fileType = DownloadFileKinds.all;
        _datePreset = 'all';
        _dateFrom = null;
        _dateTo = null;
        _searchCtrl.clear();
      });

  Widget _statCard(String label, String value, IconData icon) {
    return HrmStatSummaryCard(
      icon: icon,
      value: value,
      label: label,
      color: _theme,
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: Column(
        children: [
          _filterRow([
            _filterChip(
              'Nhóm',
              _category,
              Icons.category_rounded,
              _category != DownloadDocCategories.all,
              () => _pickCategory(),
            ),
            _filterChip(
              'Loại tệp',
              DownloadFileKinds.labels[_fileType] ?? 'Tất cả',
              Icons.description_rounded,
              _fileType != DownloadFileKinds.all,
              () => _pickFileType(),
            ),
          ]),
          const SizedBox(height: 8),
          _filterRow([
            _filterChip(
              'Ngày tải',
              _datePreset == 'all'
                  ? 'Tất cả'
                  : _datePreset == 'today'
                      ? 'Hôm nay'
                      : _datePreset == 'week'
                          ? 'Tuần này'
                          : _datePreset == 'custom'
                              ? '${DateFormat('dd/MM').format(_dateFrom!)} – ${DateFormat('dd/MM').format(_dateTo!)}'
                              : 'Tháng này',
              Icons.date_range_rounded,
              _datePreset != 'all',
              () => _pickDate(),
            ),
            _filterChip(
              'Tìm kiếm',
              _searchCtrl.text.isEmpty ? 'Tên tệp…' : _searchCtrl.text,
              Icons.search_rounded,
              _searchCtrl.text.isNotEmpty,
              _pickSearch,
            ),
          ]),
          const SizedBox(height: 8),
          _filterRow([
            _filterChip(
              'Sắp xếp',
              _sortLabels[_sort]!,
              Icons.sort_rounded,
              _sort != DownloadSort.newest,
              _pickSort,
            ),
            _filterChip(
              'Bộ lọc',
              _hasFilter ? 'Bỏ tất cả bộ lọc' : 'Chưa lọc',
              Icons.filter_alt_off_outlined,
              _hasFilter,
              _hasFilter ? _clearFilters : () {},
            ),
          ]),
        ],
      ),
    );
  }

  Widget _filterRow(List<Widget> chips) {
    return SafeEqualHeightRow(children: chips);
  }

  Widget _filterChip(String title, String value, IconData icon, bool active,
      VoidCallback onTap) {
    return Material(
      color: active ? _theme.withValues(alpha: 0.08) : SboxColors.slate50,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? _theme.withValues(alpha: 0.4) : SboxColors.slate200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: active ? _theme : SboxColors.slate500),
                  const SizedBox(width: 4),
                  Text(tr(title),
                      style: const TextStyle(fontSize: 10, color: SboxColors.slate500)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tr(value),
                maxLines: 2,
                overflow: TextOverflow.visible,
                softWrap: true,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? _theme : SboxColors.slate900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCategory() async {
    final cats = _svc.categoriesInUse();
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: cats
              .map((c) => ListTile(
                    title: Text(tr(c)),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _category = c);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  Future<void> _pickFileType() async {
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: DownloadFileKinds.labels.entries
              .map((e) => ListTile(
                    title: Text(tr(e.value)),
                    trailing: _fileType == e.key ? const Icon(Icons.check, size: 18) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _fileType = e.key);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  Future<void> _pickSort() async {
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _sortLabels.entries
              .map((e) => ListTile(
                    title: Text(tr(e.value)),
                    trailing: _sort == e.key ? const Icon(Icons.check, size: 18) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _sort = e.key);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _dateFrom != null && _dateTo != null ? DateTimeRange(start: _dateFrom!, end: _dateTo!) : null,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _datePreset = 'custom';
      _dateFrom = picked.start;
      _dateTo = picked.end;
    });
  }

  Future<void> _pickDate() async {
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in const [('Tất cả', 'all'), ('Hôm nay', 'today'), ('Tuần này', 'week'), ('Tháng này', 'month')])
              ListTile(
                title: Text(tr(e.$1)),
                trailing: _datePreset == e.$2 ? const Icon(Icons.check, size: 18) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _applyDatePreset(e.$2);
                },
              ),
            ListTile(
              leading: const Icon(Icons.date_range_rounded, size: 20),
              title: Text(tr('Chọn khoảng ngày…')),
              trailing: _datePreset == 'custom' ? const Icon(Icons.check, size: 18) : null,
              onTap: () {
                Navigator.pop(ctx);
                _pickCustomRange();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSearch() async {
    final ctrl = TextEditingController(text: tr(_searchCtrl.text));
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('Tìm tên tệp / nhóm'),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                _searchCtrl.text = v;
                Navigator.pop(ctx);
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                _searchCtrl.text = ctrl.text;
                Navigator.pop(ctx);
                setState(() {});
              },
              child: Text(tr('Áp dụng')),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  Widget _buildFileCard(DownloadedDocument doc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: SboxColors.slate200),
      ),
      color: _selected.contains(doc.id) ? _theme.withValues(alpha: 0.06) : null,
      child: InkWell(
        onTap: () => _selecting ? _toggleSelect(doc) : _open(doc),
        onLongPress: () => _toggleSelect(doc),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 10),
                  child: Icon(
                    _selected.contains(doc.id) ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: _selected.contains(doc.id) ? _theme : SboxColors.slate400,
                  ),
                ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _iconColor(doc).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconFor(doc), color: _iconColor(doc)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${tr(doc.category)} · ${_fmt.format(doc.downloadedAt)} · ${_formatSize(doc.sizeBytes)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: SboxColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'open') _open(doc);
                  if (v == 'share') _share(doc);
                  if (v == 'rename') _rename(doc);
                  if (v == 'delete') _delete([doc]);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'open',
                    child: Row(
                      children: [
                        Icon(Icons.open_in_new, size: 20),
                        SizedBox(width: 10),
                        Text(tr('Mở xem')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share_rounded, size: 20),
                        SizedBox(width: 10),
                        Text(tr('Chia sẻ')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.drive_file_rename_outline, size: 20),
                        SizedBox(width: 10),
                        Text(tr('Đổi tên')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 20, color: Colors.red),
                        SizedBox(width: 10),
                        Text(tr('Xóa'), style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
