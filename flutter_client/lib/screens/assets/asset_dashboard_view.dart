import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../models/asset.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/asset_ui.dart';
import '../../utils/navigation_notifier.dart';
import '../../widgets/auth_cached_image.dart';
import '../../widgets/sbox/sbox_charts.dart';

/// Tổng quan tài sản: giá trị còn lại & khấu hao, tỷ lệ sử dụng, phân bổ,
/// việc cần xử lý, hoạt động gần đây. Dùng ở tab «Tổng quan» (Quản lý tài sản)
/// và tab đầu của Báo cáo tài sản.
class AssetDashboardView extends StatefulWidget {
  const AssetDashboardView({
    super.key,
    this.forReport = false,
    this.onOpenAssets,
  });

  /// Gọi API theo quyền Báo cáo tài sản.
  final bool forReport;

  /// Chạm thẻ số liệu → mở danh sách tài sản lọc theo trạng thái (null = tất cả).
  final void Function(AssetStatus? status)? onOpenAssets;

  @override
  State<AssetDashboardView> createState() => _AssetDashboardViewState();
}

class _AssetDashboardViewState extends State<AssetDashboardView> {
  final _api = ApiService();
  final _dateFmt = DateFormat('dd/MM/yyyy');
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _d = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getAssetDashboard(forReport: widget.forReport);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _d = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = res['message']?.toString() ?? 'Không tải được tổng quan tài sản';
      }
    });
  }

  static double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  Map<String, dynamic> get _k => _d['kpis'] is Map ? Map<String, dynamic>.from(_d['kpis'] as Map) : {};

  List<Map<String, dynamic>> _list(String key) {
    final raw = _d[key];
    return raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: SboxColors.slate400),
            const SizedBox(height: 8),
            Text(tr(_error!), style: const TextStyle(color: SboxColors.slate600)),
            TextButton(onPressed: _load, child: Text(tr('Thử lại'))),
          ],
        ),
      );
    }
    if (_n(_k['totalAssets']) == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AssetUi.typeAvatar(AssetType.other, size: 64),
            const SizedBox(height: 12),
            Text(tr('Chưa có tài sản nào'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(tr('Thêm tài sản để xem tổng quan giá trị, khấu hao và phân bổ'),
                  textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
            ),
            if (widget.forReport) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => NavigationNotifier.navigateToModule.value = 'Asset',
                icon: const Icon(Icons.add_rounded),
                label: Text(tr('Thêm tài sản')),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 980;
        final pad = c.maxWidth < 600 ? 12.0 : 20.0;
        Widget two(Widget a, Widget b) => wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: a),
                const SizedBox(width: 16),
                Expanded(child: b),
              ])
            : Column(children: [a, const SizedBox(height: 16), b]);

        return ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 40),
          children: [
            _hero(),
            const SizedBox(height: 16),
            _kpiGrid(c.maxWidth),
            const SizedBox(height: 16),
            two(_categoryCard(), _statusCard()),
            const SizedBox(height: 16),
            two(_purchasesCard(), _agingCard()),
            const SizedBox(height: 16),
            two(_attentionCard(), _activityCard()),
            const SizedBox(height: 16),
            two(_departmentCard(), _holdersAndInventoryCard()),
          ],
        );
      }),
    );
  }

  // ───────────────────────── Hero: giá trị còn lại ─────────────────────────
  Widget _hero() {
    final purchase = _n(_k['purchaseValue']);
    final book = _n(_k['bookValue']);
    final ratio = purchase > 0 ? (book / purchase).clamp(0.0, 1.0) : 1.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [SboxColors.brand800, SboxColors.brand500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: SboxColors.brand700.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Giá trị còn lại của tài sản'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(SboxFmt.money(book),
                      style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    color: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Nguyên giá ${SboxFmt.money(purchase)} · đã khấu hao '
                      '${SboxFmt.money(_n(_k['depreciation']))} (${SboxFmt.pct(_n(_k['depreciationPct']))})'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _heroPill(Icons.inventory_2_rounded, '${_n(_k['inUseAssets']).toInt()}', 'đang quản lý'),
              _heroPill(Icons.layers_rounded, SboxFmt.number(_n(_k['totalQuantity'])), 'đơn vị'),
              if (_n(_k['disposed']) + _n(_k['lost']) > 0)
                _heroPill(Icons.archive_rounded,
                    '${(_n(_k['disposed']) + _n(_k['lost'])).toInt()}', 'thanh lý / mất'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroPill(IconData icon, String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(width: 4),
          Text(tr(label), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
        ]),
      );

  // ───────────────────────── Thẻ số liệu ─────────────────────────
  Widget _kpiGrid(double width) {
    final cols = width >= 980 ? 4 : (width >= 560 ? 2 : 2);
    final tiles = [
      _KpiTile(
        icon: Icons.assignment_ind_rounded,
        color: SboxColors.success,
        value: '${_n(_k['assigned']).toInt()}',
        label: 'Đang cấp phát',
        foot: 'Tỷ lệ sử dụng ${SboxFmt.pct(_n(_k['utilizationPct']))}',
        progress: _n(_k['utilizationPct']) / 100,
        onTap: () => widget.onOpenAssets?.call(AssetStatus.active),
      ),
      _KpiTile(
        icon: Icons.warehouse_rounded,
        color: SboxColors.brand600,
        value: '${_n(_k['inStock']).toInt()}',
        label: 'Trong kho',
        foot: _n(_k['idleInStock']) > 0 ? '${_n(_k['idleInStock']).toInt()} nằm kho quá 90 ngày' : 'Không có tài sản tồn lâu',
        onTap: () => widget.onOpenAssets?.call(AssetStatus.inStock),
      ),
      _KpiTile(
        icon: Icons.build_circle_rounded,
        color: SboxColors.danger,
        value: '${(_n(_k['broken']) + _n(_k['maintenance'])).toInt()}',
        label: 'Hỏng / bảo trì',
        foot: '${_n(_k['broken']).toInt()} hỏng · ${_n(_k['maintenance']).toInt()} đang bảo trì',
        onTap: () => widget.onOpenAssets?.call(AssetStatus.broken),
      ),
      _KpiTile(
        icon: Icons.verified_user_rounded,
        color: SboxColors.warning,
        value: '${_n(_k['warrantyExpiringSoon']).toInt()}',
        label: 'Sắp hết bảo hành',
        foot: 'Trong 30 ngày · ${_n(_k['warrantyExpired']).toInt()} đã hết BH',
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      );
    });
  }

  // ───────────────────────── Biểu đồ ─────────────────────────
  Widget _categoryCard() {
    final rows = _list('byCategory');
    final maxV = rows.fold<double>(0, (m, r) => _n(r['bookValue']) > m ? _n(r['bookValue']) : m);
    return _Section(
      title: 'Giá trị theo danh mục',
      subtitle: 'Giá trị còn lại · số tài sản',
      child: rows.isEmpty
          ? _empty('Chưa phân danh mục')
          : Column(children: [
              for (final r in rows.take(7))
                _BarRow(
                  label: r['name'].toString(),
                  trailing: SboxFmt.money(_n(r['bookValue'])),
                  caption: '${_n(r['count']).toInt()} tài sản · nguyên giá ${SboxFmt.money(_n(r['purchaseValue']))}',
                  ratio: maxV > 0 ? _n(r['bookValue']) / maxV : 0,
                  color: SboxColors.brand500,
                ),
            ]),
    );
  }

  Widget _statusCard() {
    final rows = _list('byStatus');
    return _Section(
      title: 'Tình trạng tài sản',
      subtitle: 'Chạm để xem danh sách',
      child: Column(children: [
        SboxDonutChart(
          valueFormat: (v) => '${SboxFmt.number(v)} TS',
          slices: [
            for (final r in rows)
              SboxSlice(r['name'].toString(), _n(r['count']),
                  color: AssetUi.statusColor(AssetUi.statusFromIndex(_n(r['status']).toInt()))),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in rows)
            InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () => widget.onOpenAssets?.call(AssetUi.statusFromIndex(_n(r['status']).toInt())),
              child: AssetUi.statusChip(AssetUi.statusFromIndex(_n(r['status']).toInt())),
            ),
        ]),
      ]),
    );
  }

  Widget _purchasesCard() {
    final rows = _list('purchasesByMonth');
    return _Section(
      title: 'Mua sắm 12 tháng',
      subtitle: 'Giá trị tài sản mua mới theo tháng',
      child: SboxBarChart(
        height: 220,
        showLegend: false,
        labels: [for (final r in rows) r['month'].toString().substring(0, 2)],
        series: [
          SboxSeries(name: 'Giá trị mua', values: [for (final r in rows) _n(r['value'])], color: SboxColors.brand500),
        ],
      ),
    );
  }

  Widget _agingCard() {
    final rows = _list('aging');
    final total = rows.fold<double>(0, (s, r) => s + _n(r['count']));
    const colors = [SboxColors.success, SboxColors.brand500, SboxColors.warning, SboxColors.danger];
    return _Section(
      title: 'Tuổi tài sản',
      subtitle: 'Tính từ ngày mua',
      child: Column(children: [
        for (var i = 0; i < rows.length; i++)
          _BarRow(
            label: rows[i]['label'].toString(),
            trailing: '${_n(rows[i]['count']).toInt()} TS',
            caption: 'Giá trị còn lại ${SboxFmt.money(_n(rows[i]['bookValue']))}',
            ratio: total > 0 ? _n(rows[i]['count']) / total : 0,
            color: colors[i % colors.length],
          ),
      ]),
    );
  }

  // ───────────────────────── Danh sách ─────────────────────────
  Widget _attentionCard() {
    final rows = _list('attention');
    return _Section(
      title: 'Cần xử lý',
      subtitle: 'Hỏng, sắp hết bảo hành, bảo trì, nằm kho lâu',
      child: rows.isEmpty
          ? Row(children: [
              const Icon(Icons.task_alt_rounded, color: SboxColors.success),
              const SizedBox(width: 8),
              Text(tr('Không có việc cần xử lý'), style: const TextStyle(color: SboxColors.successText)),
            ])
          : Column(children: [for (final r in rows) _attentionRow(r)]),
    );
  }

  Widget _attentionRow(Map<String, dynamic> r) {
    final sev = _n(r['severity']).toInt();
    final color = sev >= 3 ? SboxColors.danger : (sev == 2 ? SboxColors.warning : SboxColors.brand500);
    final img = (r['imageUrl'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(width: 4, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 40,
            height: 40,
            child: img.isEmpty
                ? AssetUi.typeAvatar(AssetType.other, size: 40)
                : AuthCachedImage(imagePath: img, apiService: _api, width: 40, height: 40),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['name'].toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(tr('${r['code']} · ${r['reason']}${(r['assignee'] ?? '').toString().isEmpty ? '' : ' · ${r['assignee']}'}'),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.95))),
          ]),
        ),
      ]),
    );
  }

  Widget _activityCard() {
    final rows = _list('recentActivity');
    IconData icon(int t) => switch (t) {
          0 => Icons.person_add_alt_1_rounded,
          1 => Icons.swap_horiz_rounded,
          2 => Icons.keyboard_return_rounded,
          3 => Icons.build_rounded,
          _ => Icons.delete_outline_rounded,
        };
    return _Section(
      title: 'Hoạt động gần đây',
      subtitle: 'Cấp phát, chuyển giao, thu hồi',
      child: rows.isEmpty
          ? _empty('Chưa có hoạt động')
          : Column(children: [
              for (var i = 0; i < rows.length; i++)
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Column(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: SboxColors.brand50, shape: BoxShape.circle),
                        child: Icon(icon(_n(rows[i]['type']).toInt()), size: 16, color: SboxColors.brand600),
                      ),
                      if (i < rows.length - 1)
                        Expanded(child: Container(width: 2, color: SboxColors.slate200)),
                    ]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('${rows[i]['typeName']} · ${rows[i]['assetName']}'),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            tr([
                              if ((rows[i]['from'] ?? '').toString().isNotEmpty) 'từ ${rows[i]['from']}',
                              if ((rows[i]['to'] ?? '').toString().isNotEmpty) 'cho ${rows[i]['to']}',
                              _date(rows[i]['date']),
                              if (rows[i]['confirmed'] != true && _n(rows[i]['type']) <= 1) 'chờ xác nhận',
                            ].join(' · ')),
                            style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                ),
            ]),
    );
  }

  Widget _departmentCard() {
    final rows = _list('byDepartment');
    final maxV = rows.fold<double>(0, (m, r) => _n(r['bookValue']) > m ? _n(r['bookValue']) : m);
    return _Section(
      title: 'Phân bổ theo phòng ban',
      subtitle: 'Tài sản đang cấp phát',
      child: rows.isEmpty
          ? _empty('Chưa cấp phát tài sản nào')
          : Column(children: [
              for (final r in rows.take(8))
                _BarRow(
                  label: r['name'].toString(),
                  trailing: SboxFmt.money(_n(r['bookValue'])),
                  caption: '${_n(r['count']).toInt()} tài sản · ${_n(r['employees']).toInt()} nhân viên',
                  ratio: maxV > 0 ? _n(r['bookValue']) / maxV : 0,
                  color: SboxColors.violet,
                ),
            ]),
    );
  }

  Widget _holdersAndInventoryCard() {
    final holders = _list('topAssignees');
    final inv = _d['lastInventory'] is Map ? Map<String, dynamic>.from(_d['lastInventory'] as Map) : null;
    return _Section(
      title: 'Người giữ nhiều tài sản',
      subtitle: 'Theo giá trị còn lại',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (holders.isEmpty) _empty('Chưa cấp phát tài sản nào'),
        for (final h in holders)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: SboxColors.brand100,
              child: Text(
                h['name'].toString().trim().isEmpty ? '?' : h['name'].toString().trim().split(' ').last[0].toUpperCase(),
                style: const TextStyle(color: SboxColors.brand700, fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(h['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr('${(h['department'] ?? '').toString().isEmpty ? '' : '${h['department']} · '}${_n(h['count']).toInt()} tài sản')),
            trailing: Text(SboxFmt.money(_n(h['bookValue'])), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        const Divider(height: 24),
        Row(children: [
          const Icon(Icons.fact_check_rounded, color: SboxColors.brand600),
          const SizedBox(width: 8),
          Expanded(
            child: inv == null
                ? Text(tr('Chưa có đợt kiểm kê hoàn thành — nên kiểm kê ít nhất mỗi quý'),
                    style: const TextStyle(color: SboxColors.warningText, fontSize: 13))
                : Text(
                    tr('Kiểm kê gần nhất ${_date(inv['date'])}: ${_n(inv['checked']).toInt()}/${_n(inv['total']).toInt()} đã kiểm'
                        '${_n(inv['issues']) > 0 ? ' · ${_n(inv['issues']).toInt()} vấn đề' : ' · không có vấn đề'}'),
                    style: const TextStyle(fontSize: 13),
                  ),
          ),
        ]),
      ]),
    );
  }

  String _date(dynamic v) {
    final d = v == null ? null : DateTime.tryParse(v.toString());
    return d == null ? '' : _dateFmt.format(d.toLocal());
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(tr(text), style: const TextStyle(color: SboxColors.slate500)),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SboxColors.slate200),
          boxShadow: [BoxShadow(color: SboxColors.slate900.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: SboxColors.slate900)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(tr(subtitle!), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            ),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.foot,
    this.progress,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String foot;
  final double? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SboxColors.slate200),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                if (onTap != null) const Icon(Icons.chevron_right_rounded, color: SboxColors.slate300),
              ]),
              const SizedBox(height: 10),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
              Text(tr(label), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SboxColors.slate700)),
              const SizedBox(height: 6),
              if (progress != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0.0, 1.0),
                    minHeight: 5,
                    color: color,
                    backgroundColor: SboxColors.slate100,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(tr(foot), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
            ]),
          ),
        ),
      );
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.trailing,
    required this.caption,
    required this.ratio,
    required this.color,
  });

  final String label;
  final String trailing;
  final String caption;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Text(trailing, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 8,
              color: color,
              backgroundColor: SboxColors.slate100,
            ),
          ),
          const SizedBox(height: 3),
          Text(tr(caption), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
        ]),
      );
}
