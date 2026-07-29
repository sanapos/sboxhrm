import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../design_system/design_system.dart';

import '../models/downloaded_document.dart';
import '../services/downloaded_documents_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/safe_layout_widgets.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/app_scroll_safe.dart';
import '../widgets/hrm_mini_stat_chip.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _theme = Color(0xFF7C3AED);

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
  bool _showOverviewPanel = false;
  String _category = DownloadDocCategories.all;
  String _fileType = 'all';
  String _datePreset = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;

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
    await _svc.ensureLoaded(rescan: true);
    if (mounted) setState(() => _loading = false);
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
    await Share.shareXFiles(
      [XFile(doc.localPath, mimeType: doc.mimeType)],
      text: tr(doc.displayName),
    );
  }

  Future<void> _rename(DownloadedDocument doc) async {
    final ctrl = TextEditingController(text: tr(doc.displayName));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Đổi tên tệp')),
        content: TextField(
          controller: ctrl,
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

  Future<void> _delete(DownloadedDocument doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Xóa tệp')),
        content: Text(tr('Xóa "${doc.displayName}" khỏi danh sách quản lý?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _svc.delete(doc.id);
    if (mounted) setState(() {});
  }

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
    if (doc.isImage) return const Color(0xFF2563EB);
    if (doc.isExcel) return const Color(0xFF059669);
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final list = _filtered;

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: Column(
        children: [
          _buildHeader(isMobile),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: list.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(height: 120),
                              Center(
                                child: Text(tr('Chưa có tệp tải xuống.\nXuất Excel/ảnh từ báo cáo sẽ hiện tại đây.'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFF71717A)),
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
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          isMobile ? 14 : 24, isMobile ? 12 : 18, isMobile ? 14 : 24, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_theme, _theme.withValues(alpha: 0.85)],
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_special_rounded,
              color: Colors.white, size: isMobile ? 22 : 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Quản lý tài liệu tải xuống'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 17 : 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(tr('Chỉ trên thiết bị này · Excel, PNG — mở, chia sẻ, xóa'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: isMobile ? 11 : 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.sync_rounded, color: Colors.white),
            tooltip: tr('Quét lại thư mục SBOX HRM'),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewSection(int visibleCount) {
    final total = _svc.items.length;
    final excel =
        _svc.items.where((e) => e.isExcel).length;
    final images =
        _svc.items.where((e) => e.isImage).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () =>
              setState(() => _showOverviewPanel = !_showOverviewPanel),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.info.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.analytics_outlined,
                    size: 16, color: AppColors.info.shade700),
                const SizedBox(width: 6),
                Text(tr('Tổng quan & bộ lọc'),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.info.shade700)),
                const Spacer(),
                Text(tr('$visibleCount/$total'),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.info.shade700)),
                const SizedBox(width: 4),
                Icon(
                    _showOverviewPanel
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: AppColors.info.shade700),
              ],
            ),
          ),
        ),
        if (_showOverviewPanel) ...[
          const SizedBox(height: 8),
          HrmPageChrome.horizontalStatCards(
            cards: [
              _statCard('Tổng tệp', '$total', Icons.folder_open),
              _statCard('Excel', '$excel', Icons.table_chart),
              _statCard('Ảnh PNG', '$images', Icons.image),
            ],
            minCardWidth: 100,
            gap: 8,
          ),
          const SizedBox(height: 10),
          _buildFilterBar(),
        ],
      ],
    );
  }

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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
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
              _fileType == 'excel'
                  ? 'Excel'
                  : _fileType == 'image'
                      ? 'Ảnh'
                      : 'Tất cả',
              Icons.description_rounded,
              _fileType != 'all',
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
      color: active ? _theme.withValues(alpha: 0.08) : const Color(0xFFFAFAFA),
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
              color: active ? _theme.withValues(alpha: 0.4) : const Color(0xFFE4E4E7),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: active ? _theme : Colors.grey),
                  const SizedBox(width: 4),
                  Text(tr(title),
                      style: const TextStyle(fontSize: 10, color: Color(0xFF71717A))),
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
                  color: active ? _theme : const Color(0xFF18181B),
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
          children: [
            ListTile(
                title: Text(tr('Tất cả')),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _fileType = 'all');
                }),
            ListTile(
                title: Text(tr('Excel (.xlsx)')),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _fileType = 'excel');
                }),
            ListTile(
                title: Text(tr('Ảnh PNG/JPG')),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _fileType = 'image');
                }),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                title: Text(tr('Tất cả')),
                onTap: () {
                  Navigator.pop(ctx);
                  _applyDatePreset('all');
                }),
            ListTile(
                title: Text(tr('Hôm nay')),
                onTap: () {
                  Navigator.pop(ctx);
                  _applyDatePreset('today');
                }),
            ListTile(
                title: Text(tr('Tuần này')),
                onTap: () {
                  Navigator.pop(ctx);
                  _applyDatePreset('week');
                }),
            ListTile(
                title: Text(tr('Tháng này')),
                onTap: () {
                  Navigator.pop(ctx);
                  _applyDatePreset('month');
                }),
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
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      child: InkWell(
        onTap: () => _open(doc),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      tr(doc.displayName),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      softWrap: true,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('${doc.category} · ${_fmt.format(doc.downloadedAt)} · ${_formatSize(doc.sizeBytes)}'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF71717A),
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
                  if (v == 'delete') _delete(doc);
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
