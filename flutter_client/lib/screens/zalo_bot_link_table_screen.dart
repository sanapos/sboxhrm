import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_tr.dart';
import '../services/zalo_bot_api.dart';
import '../utils/pos_sell_store_settings.dart';
import '../utils/vn_search.dart';
import '../utils/zalo_link_print.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/sbox/sbox_ui.dart';

/// Bảng liên kết Zalo cả cửa hàng: mọi nhân viên đang làm (kể cả không có tài khoản app), cấp mã 6 số hạn 7 ngày,
/// in phiếu cắt phát riêng từng người, xuất Excel theo dõi ai đã / chưa liên kết.
class ZaloBotLinkTableScreen extends StatefulWidget {
  const ZaloBotLinkTableScreen({super.key, this.api, this.botName, this.botLink});

  final ZaloBotApi? api;
  final String? botName;
  final String? botLink;

  @override
  State<ZaloBotLinkTableScreen> createState() => _ZaloBotLinkTableScreenState();
}

enum _Filter { all, unlinked, linked }

class _ZaloBotLinkTableScreenState extends State<ZaloBotLinkTableScreen> {
  late final ZaloBotApi _api = widget.api ?? ZaloBotApi();
  final _search = TextEditingController();
  List<ZaloLinkRow> _rows = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  _Filter _filter = _Filter.unlinked;
  String? _dept;
  String _storeName = '';

  static final _date = DateFormat('dd/MM');

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
    PosSellStoreSettings.load().then((s) {
      if (mounted) setState(() => _storeName = s.storeName.trim());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setRows(Map<String, dynamic> r) {
    _rows = [
      if (r['data'] is List)
        for (final e in r['data'] as List)
          if (e is Map) ZaloLinkRow(Map<String, dynamic>.from(e)),
    ];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.getEmployeeLinks();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true) {
        _setRows(r);
      } else {
        _error = (r['message'] ?? 'Không tải được bảng liên kết').toString();
      }
    });
  }

  /// [ids] null = mọi người chưa liên kết.
  Future<void> _createCodes({List<String>? ids, bool renew = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await _api.createEmployeeCodes(employeeIds: ids, renew: renew);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r['isSuccess'] == true) _setRows(r);
    });
    if (r['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Xong', message: renew ? 'Đã đổi mã liên kết' : 'Đã tạo mã liên kết');
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: (r['message'] ?? 'Không tạo được mã').toString());
    }
  }

  Future<void> _unlink(ZaloLinkRow row) async {
    final ok = await SboxDialogs.confirm(
      context,
      title: 'Hủy liên kết Zalo?',
      message: tr('{name} sẽ không nhận thông báo qua Zalo nữa.').replaceAll('{name}', row.name),
      confirmLabel: 'Hủy liên kết',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = row.employeeId != null ? await _api.unlinkEmployee(row.employeeId!) : await _api.unlinkUser(row.userId ?? '');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      await _load();
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: (r['message'] ?? 'Không thực hiện được').toString());
    }
  }

  List<String> get _departments {
    final set = <String>{for (final r in _rows) if ((r.department ?? '').trim().isNotEmpty) r.department!.trim()};
    return set.toList()..sort();
  }

  List<ZaloLinkRow> get _visible {
    final q = _search.text.trim();
    return _rows.where((r) {
      if (_filter == _Filter.linked && !r.linked) return false;
      if (_filter == _Filter.unlinked && r.linked) return false;
      if (_dept != null && (r.department ?? '').trim() != _dept) return false;
      if (q.isEmpty) return true;
      return vnContains(r.name, q) || vnContains(r.employeeCode, q) || vnContains(r.phone, q);
    }).toList();
  }

  Future<void> _print() async {
    final rows = _visible.where((r) => !r.linked && r.code != null).toList();
    if (rows.isEmpty) {
      NotificationOverlayManager().showWarning(
          title: 'Chưa có mã', message: tr('Bấm «Tạo mã» cho người chưa liên kết trước khi in.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await printZaloLinkSlips(
        rows: rows,
        storeName: _storeName.isNotEmpty ? _storeName : (widget.botName ?? 'SBOX'),
        botName: widget.botName,
        botLink: widget.botLink,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _excel() async {
    setState(() => _busy = true);
    try {
      final rows = _visible;
      await exportZaloLinksExcel(rows, storeName: _storeName.isNotEmpty ? _storeName : (widget.botName ?? 'SBOX'));
      // Android lưu thẳng vào Tải xuống/SBOX HRM, không mở gì — phải báo để biết đã xong.
      NotificationOverlayManager().showSuccess(title: 'Xuất Excel', message: tr('Đã xuất file Excel (${rows.length} bản ghi)'));
    } catch (e) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: tr('Không thể xuất Excel: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = _rows.where((r) => r.linked).length;
    final unlinked = _rows.length - linked;
    final withCode = _rows.where((r) => !r.linked && r.code != null).length;
    final noAccount = _rows.where((r) => !r.hasAccount && r.employeeId != null).length;
    final rows = _visible;
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        title: Text(tr('Bảng liên kết Zalo')),
        actions: [
          IconButton(tooltip: tr('Tải lại'), onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const SboxLoading(message: 'Đang tải bảng liên kết…')
          : _error != null
              ? SboxEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Không tải được',
                  message: _error,
                  action: SboxButton.secondary(label: 'Thử lại', icon: Icons.refresh_rounded, onPressed: _load),
                )
              : LayoutBuilder(builder: (context, c) {
                  final pad = c.maxWidth < 600 ? 12.0 : 20.0;
                  // Điện thoại nằm ngang (V2s cao ~330dp): 4 thẻ số 2×2 chiếm trọn màn → gom thành 1 hàng nhãn.
                  final short = c.maxHeight < 520;
                  return ListView(
                    padding: EdgeInsets.fromLTRB(pad, pad, pad, 32),
                    children: [
                      if (short)
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _stat(Icons.verified_user_outlined, 'Đã liên kết', '$linked/${_rows.length}', SboxTone.success),
                          _stat(Icons.link_off_rounded, 'Chưa liên kết', '$unlinked',
                              unlinked > 0 ? SboxTone.warning : SboxTone.success),
                          _stat(Icons.pin_outlined, 'Có mã chờ gửi', '$withCode', SboxTone.brand),
                          _stat(Icons.person_off_outlined, 'Không có tài khoản app', '$noAccount', SboxTone.neutral),
                        ])
                      else
                        SboxKpiStrip(maxColumns: 4, items: [
                          SboxKpi(label: 'Đã liên kết', value: '$linked/${_rows.length}', icon: Icons.verified_user_outlined,
                              tone: SboxTone.success, note: 'Nhận tin qua Zalo'),
                          SboxKpi(label: 'Chưa liên kết', value: '$unlinked', icon: Icons.link_off_rounded,
                              tone: unlinked > 0 ? SboxTone.warning : SboxTone.success),
                          SboxKpi(label: 'Có mã chờ gửi', value: '$withCode', icon: Icons.pin_outlined, tone: SboxTone.brand,
                              note: 'Mã dùng 7 ngày'),
                          SboxKpi(label: 'Không có tài khoản app', value: '$noAccount', icon: Icons.person_off_outlined,
                              tone: SboxTone.neutral, note: 'Vẫn nhận qua Zalo'),
                        ]),
                      const SizedBox(height: 12),
                      _howTo(),
                      const SizedBox(height: 12),
                      _toolbar(),
                      const SizedBox(height: 10),
                      if (rows.isEmpty)
                        SboxEmptyState(
                          icon: Icons.groups_outlined,
                          title: _rows.isEmpty ? 'Chưa có nhân viên' : 'Không có người phù hợp',
                          message: _rows.isEmpty ? 'Thêm nhân viên ở Hồ sơ nhân sự trước.' : 'Đổi bộ lọc hoặc từ khóa tìm kiếm.',
                        )
                      else
                        SboxCard(
                          padding: EdgeInsets.zero,
                          child: Column(children: [
                            for (var i = 0; i < rows.length; i++) ...[
                              if (i > 0) const Divider(height: 1, color: SboxColors.divider),
                              _row(rows[i]),
                            ],
                          ]),
                        ),
                    ],
                  );
                }),
    );
  }

  Widget _stat(IconData icon, String label, String value, SboxTone tone) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: tone.fg),
          const SizedBox(width: 6),
          Text(tr(label), style: TextStyle(fontSize: 12.5, color: tone.fg)),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: tone.fg)),
        ]),
      );

  Widget _howTo() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: SboxColors.brand700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('1. Bấm «Tạo mã» → 2. «In phiếu mã», cắt và phát riêng từng người (không dán công khai — ai cầm mã '
                  'là nhận được tin của người đó) → 3. Nhân viên quét QR mở bot, gửi mã 6 số. Không cần tài khoản app. '
                  'Kiểm cột «Tên Zalo» để chắc đúng người.'),
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: SboxColors.brand800),
            ),
          ),
        ]),
      );

  Widget _toolbar() {
    final depts = _departments;
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(
        width: 240,
        height: 40,
        child: TextField(
          controller: _search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: tr('Tên, mã NV, SĐT'),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      SegmentedButton<_Filter>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: _Filter.unlinked, label: Text(tr('Chưa liên kết'))),
          ButtonSegment(value: _Filter.linked, label: Text(tr('Đã liên kết'))),
          ButtonSegment(value: _Filter.all, label: Text(tr('Tất cả'))),
        ],
        selected: {_filter},
        onSelectionChanged: (s) => setState(() => _filter = s.first),
      ),
      if (depts.isNotEmpty)
        DropdownButton<String?>(
          value: _dept,
          hint: Text(tr('Mọi phòng ban')),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(tr('Mọi phòng ban'))),
            for (final d in depts) DropdownMenuItem<String?>(value: d, child: Text(d)),
          ],
          onChanged: (v) => setState(() => _dept = v),
        ),
      SboxButton(
        label: 'Tạo mã cho người chưa liên kết',
        icon: Icons.pin_outlined,
        loading: _busy,
        onPressed: _busy ? null : () => _createCodes(),
      ),
      SboxButton.secondary(label: 'In phiếu mã', icon: Icons.print_outlined, onPressed: _busy ? null : _print),
      SboxButton.secondary(label: 'Excel', icon: Icons.table_chart_outlined, onPressed: _busy ? null : _excel),
    ]);
  }

  Widget _row(ZaloLinkRow r) {
    final meta = [
      if ((r.employeeCode ?? '').isNotEmpty) r.employeeCode!,
      if ((r.department ?? '').isNotEmpty) r.department!,
    ].join(' · ');
    final Widget status;
    if (r.linked) {
      status = Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        const SboxStatusChip(label: 'Đã liên kết', tone: SboxTone.success, icon: Icons.check_circle_outline_rounded),
        if ((r.zaloName ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('${tr('Zalo')}: ${r.zaloName}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
          ),
      ]);
    } else if (r.code != null) {
      status = Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        SelectableText(r.codeDisplay!,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 2, color: SboxColors.brand700)),
        if (r.codeExpiresAt != null)
          Text(tr('dùng đến {d}').replaceAll('{d}', _date.format(r.codeExpiresAt!)),
              style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
      ]);
    } else {
      status = TextButton.icon(
        onPressed: _busy || r.employeeId == null ? null : () => _createCodes(ids: [r.employeeId!]),
        icon: const Icon(Icons.pin_outlined, size: 18),
        label: Text(tr('Tạo mã')),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: r.linked ? SboxColors.successSoft : SboxColors.slate100,
          child: Text(r.name.isEmpty ? '?' : r.name.trim().split(' ').last.characters.first.toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.w700, color: r.linked ? SboxColors.successText : SboxColors.slate600)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate900)),
            const SizedBox(height: 2),
            Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (meta.isNotEmpty) Text(meta, style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              if (!r.hasAccount)
                Text(tr('Không có tài khoản app'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.warningText, fontWeight: FontWeight.w600)),
              if (r.employeeId == null)
                Text(tr('Tài khoản (không có hồ sơ NV)'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        status,
        PopupMenuButton<String>(
          tooltip: tr('Thao tác'),
          enabled: !_busy,
          onSelected: (v) => switch (v) {
            'renew' => _createCodes(ids: [r.employeeId!], renew: true),
            'unlink' => _unlink(r),
            _ => null,
          },
          itemBuilder: (_) => [
            if (!r.linked && r.employeeId != null)
              PopupMenuItem(value: 'renew', child: Text(tr(r.code == null ? 'Tạo mã' : 'Đổi mã (mã cũ hết dùng)'))),
            if (r.linked) PopupMenuItem(value: 'unlink', child: Text(tr('Hủy liên kết'))),
          ],
        ),
      ]),
    );
  }
}
