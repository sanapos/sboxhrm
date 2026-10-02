import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_tr.dart';
import '../../../services/api_service.dart';
import '../../../widgets/sbox/sbox_ui.dart';
import '../service_packages_tab.dart';
import 'sa_v2_common.dart';

/// Gói dịch vụ v2: danh sách gói (giá, dòng sản phẩm, số cửa hàng, key, cảnh báo) + trình sửa gói.
class PackagesV2Tab extends StatefulWidget {
  const PackagesV2Tab({super.key, this.apiOverride});
  final ApiService? apiOverride;

  @override
  State<PackagesV2Tab> createState() => PackagesV2TabState();
}

class PackagesV2TabState extends State<PackagesV2Tab> {
  late final ApiService _api = widget.apiOverride ?? ApiService();
  bool _loading = true;
  SaCatalog? _catalog;
  List<Map<String, dynamic>> packages = [];
  String _line = '';
  String _q = '';

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() => _loading = true);
    final rs = await Future.wait([_api.saCatalog(), _api.saPackages()]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (rs[0]['isSuccess'] == true && rs[0]['data'] is Map) _catalog = SaCatalog.fromJson(Map<String, dynamic>.from(rs[0]['data'] as Map));
      packages = rs[1]['data'] is List
          ? (rs[1]['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
    });
  }

  Future<void> _edit(Map<String, dynamic>? pkg, {bool copy = false}) async {
    final c = _catalog;
    if (c == null) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PackageEditorPage(api: _api, catalog: c, package: pkg, asCopy: copy),
    ));
    if (saved == true) loadData();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = SboxSpace.pagePadding(w);
    if (_loading && packages.isEmpty) return const SboxLoading();
    final list = packages.where((p) {
      if (_line.isNotEmpty && (p['productLine'] ?? 'both') != _line) return false;
      if (_q.isNotEmpty && !'${p['name']} ${p['description'] ?? ''}'.toLowerCase().contains(_q.toLowerCase())) return false;
      return true;
    }).toList();
    final totalStores = packages.fold<int>(0, (a, p) => a + ((p['stores'] as num?)?.toInt() ?? 0));
    final warn = packages.where((p) => (p['missing'] as List? ?? []).isNotEmpty || (p['unknown'] as List? ?? []).isNotEmpty).length;
    final cols = w >= 1300 ? 3 : w >= 820 ? 2 : 1;

    return ColoredBox(
      color: SboxColors.page,
      child: RefreshIndicator(
        onRefresh: loadData,
        child: ListView(padding: EdgeInsets.all(pad), children: [
          SboxPageHeader(
            title: 'Gói dịch vụ',
            subtitle: 'Chức năng, giá bán, giới hạn và cửa hàng đang dùng',
            actions: [
              SboxButton.ghost(
                label: 'Giao diện cũ',
                icon: Icons.history_rounded,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(appBar: AppBar(title: Text(tr('Gói dịch vụ (giao diện cũ)'))), body: const ServicePackagesTab()),
                )),
              ),
              SboxButton(label: 'Tạo gói', icon: Icons.add_rounded, onPressed: () => _edit(null)),
            ],
          ),
          const SizedBox(height: SboxSpace.md),
          SboxKpiStrip(maxColumns: 4, items: [
            SboxKpi(label: 'Gói đang bán', value: '${packages.where((p) => p['isActive'] == true && p['isPublic'] == true).length}', icon: Icons.storefront_outlined),
            SboxKpi(label: 'Gói gán tay', value: '${packages.where((p) => p['isPublic'] != true).length}', icon: Icons.lock_outline, tone: SboxTone.neutral),
            SboxKpi(label: 'Cửa hàng dùng gói', value: '$totalStores', icon: Icons.store_mall_directory_outlined, tone: SboxTone.success),
            SboxKpi(label: 'Gói cần kiểm tra', value: '$warn', icon: Icons.warning_amber_rounded, tone: warn > 0 ? SboxTone.warning : SboxTone.neutral,
                note: 'Thiếu chức năng phụ thuộc / mã cũ'),
          ]),
          const SizedBox(height: SboxSpace.md),
          Row(children: [
            Expanded(
              child: SaSegment<String>(
                value: _line,
                options: const {'': 'Tất cả', 'pos': 'Bán hàng', 'hrm': 'Nhân sự', 'both': 'Bán hàng + Nhân sự'},
                onChanged: (v) => setState(() => _line = v),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                decoration: saInput('Tìm gói').copyWith(prefixIcon: const Icon(Icons.search_rounded, size: 18)),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          ]),
          const SizedBox(height: SboxSpace.md),
          if (list.isEmpty)
            const SboxEmptyState(icon: Icons.inventory_2_outlined, title: 'Chưa có gói phù hợp')
          else
            SboxGrid(columns: cols, children: [for (final p in list) _PackageCard(pkg: p, catalog: _catalog, onEdit: () => _edit(p), onCopy: () => _edit(p, copy: true))]),
        ]),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.pkg, required this.catalog, required this.onEdit, required this.onCopy});
  final Map<String, dynamic> pkg;
  final SaCatalog? catalog;
  final VoidCallback onEdit;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final line = '${pkg['productLine'] ?? 'both'}';
    final mods = (pkg['modules'] as List? ?? []).map((e) => '$e').toList();
    final missing = (pkg['missing'] as List? ?? []);
    final unknown = (pkg['unknown'] as List? ?? []);
    String lim(dynamic v, String unit) {
      final n = (v as num?)?.toInt() ?? 0;
      return n <= 0 ? 'Không giới hạn $unit' : '$n $unit';
    }

    final byCat = <String, int>{};
    for (final m in mods) {
      final c = catalog?.module(m)?.category;
      if (c != null) byCat[c] = (byCat[c] ?? 0) + 1;
    }
    return Container(
      decoration: BoxDecoration(
        color: SboxColors.white,
        borderRadius: SboxRadius.lgAll,
        border: Border.all(color: pkg['isFeatured'] == true ? SboxColors.brand400 : SboxColors.border, width: pkg['isFeatured'] == true ? 1.5 : 1),
      ),
      padding: const EdgeInsets.all(SboxSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${pkg['name']}', style: SboxType.titleSmStyle(), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (pkg['badge'] != null) ...[SboxStatusChip(label: '${pkg['badge']}', tone: SboxTone.warning), const SizedBox(width: 4)],
          SboxStatusChip(label: saProductLineLabel(line), tone: saProductLineTone(line)),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          SboxStatusChip(label: pkg['isActive'] == true ? 'Đang bật' : 'Đã tắt', tone: pkg['isActive'] == true ? SboxTone.success : SboxTone.neutral, dot: true),
          SboxStatusChip(label: pkg['isPublic'] == true ? 'Hiện trên đăng ký' : 'Gán tay', tone: SboxTone.neutral),
          if ((pkg['trialDays'] as num? ?? 0) > 0) SboxStatusChip(label: 'Dùng thử ${pkg['trialDays']} ngày', tone: SboxTone.brand),
        ]),
        const SizedBox(height: SboxSpace.sm),
        Text(
          pkg['monthlyPrice'] == null ? 'Giá: liên hệ' : '${saMoney(pkg['monthlyPrice'] as num)} / tháng'
              '${pkg['yearlyPrice'] != null ? ' · ${saMoney(pkg['yearlyPrice'] as num)} / năm' : ''}',
          style: SboxType.bodyStrong(SboxColors.brand800),
        ),
        Text('${lim(pkg['maxUsers'], 'tài khoản')} · ${lim(pkg['maxBranches'], 'chi nhánh')} · ${lim(pkg['maxDevices'], 'máy chấm công')}',
            style: SboxType.captionStyle()),
        const SizedBox(height: SboxSpace.sm),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final e in byCat.entries)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: SboxColors.slate100, borderRadius: SboxRadius.smAll),
              child: Text('${e.key} ${e.value}', style: SboxType.captionStyle(SboxColors.textSecondary)),
            ),
        ]),
        if (missing.isNotEmpty || unknown.isNotEmpty) ...[
          const SizedBox(height: SboxSpace.sm),
          Container(
            padding: const EdgeInsets.all(SboxSpace.sm),
            decoration: BoxDecoration(color: SboxColors.warningSoft, borderRadius: SboxRadius.smAll),
            child: Text(
              [
                if (missing.isNotEmpty) '${missing.length} chức năng thiếu phụ thuộc',
                if (unknown.isNotEmpty) '${unknown.length} mã không còn dùng',
              ].join(' · '),
              style: SboxType.captionStyle(SboxColors.warningText),
            ),
          ),
        ],
        const SizedBox(height: SboxSpace.sm),
        Row(children: [
          Expanded(
            child: Text(
              '${pkg['stores'] ?? 0} cửa hàng (${pkg['activeStores'] ?? 0} hoạt động, ${pkg['expiringStores'] ?? 0} sắp hết hạn) · ${pkg['unusedKeys'] ?? 0} key chưa dùng',
              style: SboxType.captionStyle(),
            ),
          ),
          IconButton(tooltip: tr('Tạo bản sao'), icon: const Icon(Icons.copy_all_outlined, size: 18), onPressed: onCopy),
          SboxButton.secondary(label: 'Sửa', icon: Icons.edit_outlined, size: SboxButtonSize.sm, onPressed: onEdit),
        ]),
      ]),
    );
  }
}

// ─── Trình sửa gói ───────────────────────────────────────────────────

class PackageEditorPage extends StatefulWidget {
  const PackageEditorPage({super.key, required this.api, required this.catalog, this.package, this.asCopy = false});
  final ApiService api;
  final SaCatalog catalog;
  final Map<String, dynamic>? package;
  final bool asCopy;

  @override
  State<PackageEditorPage> createState() => _PackageEditorPageState();
}

class _PackageEditorPageState extends State<PackageEditorPage> {
  Map<String, dynamic> get p => widget.package ?? const {};
  bool get _isEdit => widget.package != null && !widget.asCopy;

  late final _name = TextEditingController(text: widget.asCopy ? '${p['name'] ?? ''} (bản sao)' : '${p['name'] ?? ''}');
  late final _desc = TextEditingController(text: '${p['description'] ?? ''}');
  late final _days = TextEditingController(text: '${p['defaultDurationDays'] ?? 30}');
  late final _users = TextEditingController(text: '${p['maxUsers'] ?? 10}');
  late final _devices = TextEditingController(text: '${p['maxDevices'] ?? 2}');
  late final _access = TextEditingController(text: '${p['maxAccessDevices'] ?? 0}');
  late final _branches = TextEditingController(text: '${p['maxBranches'] ?? 0}');
  late final _monthly = TextEditingController(text: p['monthlyPrice'] == null ? '' : '${(p['monthlyPrice'] as num).round()}');
  late final _yearly = TextEditingController(text: p['yearlyPrice'] == null ? '' : '${(p['yearlyPrice'] as num).round()}');
  late final _trial = TextEditingController(text: '${p['trialDays'] ?? 0}');
  late final _sort = TextEditingController(text: '${p['sortOrder'] ?? 0}');
  late final _badge = TextEditingController(text: '${p['badge'] ?? ''}');
  late final _highlights = TextEditingController(text: '${p['highlights'] ?? ''}');
  late final _retHour = TextEditingController(text: '${p['retentionRunHour'] ?? 3}');
  late final _retAttendance = TextEditingController(text: '${p['attendanceRetentionMonths'] ?? 0}');
  late final _retSaleOrders = TextEditingController(text: '${p['saleOrderRetentionMonths'] ?? 0}');
  late String _line = '${p['productLine'] ?? 'both'}';
  late bool _active = p['isActive'] != false;
  late bool _public = p['isPublic'] != false;
  late bool _featured = p['isFeatured'] == true;
  late bool _web = p['allowWeb'] != false;
  late bool _mobile = p['allowMobile'] != false;
  late bool _fcm = p['allowFcm'] != false;
  late final Set<String> _mods = {...(p['modules'] as List? ?? []).map((e) => '$e')};
  late final Set<String> _fcmCats = {...(p['fcmCategories'] as List? ?? []).map((e) => '$e')};
  String _q = '';
  String _lineFilter = '';
  bool _saving = false;

  SaCatalog get c => widget.catalog;

  bool _has(String code) => _mods.any((m) => m.toLowerCase() == code.toLowerCase());
  void _toggle(String code, bool on) => setState(() {
        if (on) {
          _mods.add(code);
        } else {
          _mods.removeWhere((m) => m.toLowerCase() == code.toLowerCase());
        }
      });

  Future<void> _applyPreset(SaPreset preset) async {
    final ok = await SboxDialogs.confirm(context,
        title: 'Áp mẫu «${preset.name}»?',
        message: '${preset.description}\n\nDanh sách chức năng hiện tại sẽ được thay bằng ${preset.modules.length} chức năng của mẫu.',
        confirmLabel: 'Áp mẫu');
    if (!ok) return;
    setState(() {
      _mods
        ..clear()
        ..addAll(preset.modules);
      if (preset.productLine != 'both' || _line == 'both') _line = preset.productLine;
    });
  }

  int? _int(TextEditingController t) => int.tryParse(t.text.replaceAll(RegExp(r'[^0-9]'), ''));

  Map<String, dynamic> _payload() => {
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'defaultDurationDays': _int(_days) ?? 30,
        'maxUsers': _int(_users) ?? 10,
        'maxDevices': _int(_devices) ?? 2,
        'maxAccessDevices': _int(_access) ?? 0,
        'maxBranches': _int(_branches) ?? 0,
        'allowWeb': _web,
        'allowMobile': _mobile,
        'allowFcm': _fcm,
        'allowedFcmCategories': _fcmCats.toList(),
        'allowedModules': [for (final m in c.modules) if (_has(m.code)) m.code],
        'isActive': _active,
        'isPublic': _public,
        'retentionRunHour': (_int(_retHour) ?? 3).clamp(0, 23),
        'attendanceRetentionMonths': (_int(_retAttendance) ?? 0).clamp(0, 120),
        'saleOrderRetentionMonths': (_int(_retSaleOrders) ?? 0).clamp(0, 120),
      };

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return saToast(context, 'Nhập tên gói', error: true);
    final payload = _payload();
    final missing = c.missing(_mods);
    if (missing.isNotEmpty) {
      final go = await SboxDialogs.confirm(context,
          title: 'Còn ${missing.length} chức năng thiếu phụ thuộc',
          message: 'Ví dụ: «${c.nameOf(missing.first.$1)}» cần «${c.nameOf(missing.first.$2)}». Vẫn lưu?',
          confirmLabel: 'Vẫn lưu');
      if (!go || !mounted) return;
    }
    if (_isEdit && ((p['stores'] as num?) ?? 0) > 0) {
      final r = await widget.api.saPackageImpact({
        'packageId': p['id'],
        'modules': payload['allowedModules'],
        'maxUsers': payload['maxUsers'],
        'maxBranches': payload['maxBranches'],
        'maxDevices': payload['maxDevices'],
      });
      if (!mounted) return;
      final d = r['data'];
      if (r['isSuccess'] == true && d is Map && ((d['affectedStores'] as num?) ?? 0) > 0) {
        final go = await _showImpact(Map<String, dynamic>.from(d));
        if (go != true || !mounted) return;
      }
    }
    setState(() => _saving = true);
    final r = _isEdit ? await widget.api.updateServicePackage('${p['id']}', payload) : await widget.api.createServicePackage(payload);
    var id = _isEdit ? '${p['id']}' : null;
    if (!_isEdit && r['isSuccess'] == true && r['data'] is Map) id = '${(r['data'] as Map)['id']}';
    if (r['isSuccess'] == true && id != null) {
      await widget.api.saSavePackageCommercial(id, {
        'productLine': _line,
        'monthlyPrice': _int(_monthly),
        'yearlyPrice': _int(_yearly),
        'trialDays': _int(_trial) ?? 0,
        'sortOrder': _int(_sort) ?? 0,
        'isFeatured': _featured,
        'badge': _badge.text.trim(),
        'highlights': _highlights.text.trim(),
      });
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (saOk(context, r, _isEdit ? 'Đã lưu gói' : 'Đã tạo gói')) Navigator.pop(context, true);
  }

  Future<bool?> _showImpact(Map<String, dynamic> d) {
    final stores = (d['stores'] as List? ?? []).whereType<Map>().toList();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Ảnh hưởng tới ${d['affectedStores']}/${d['totalStores']} cửa hàng')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((d['removed'] as List? ?? []).isNotEmpty)
                Text('Bỏ: ${(d['removed'] as List).join(', ')}', style: SboxType.smallStyle(SboxColors.dangerText)),
              if ((d['added'] as List? ?? []).isNotEmpty)
                Text('Thêm: ${(d['added'] as List).join(', ')}', style: SboxType.smallStyle(SboxColors.successText)),
              const SizedBox(height: 8),
              for (final s in stores.take(30))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '• ${s['name']} (${s['code']})'
                    '${(s['lost'] as List? ?? []).isNotEmpty ? ' — mất: ${(s['lost'] as List).join(', ')}' : ''}'
                    '${(s['over'] as List? ?? []).isNotEmpty ? ' — vượt: ${(s['over'] as List).join(', ')}' : ''}',
                    style: SboxType.smallStyle(SboxColors.text),
                  ),
                ),
              if (stores.length > 30) Text('… và ${stores.length - 30} cửa hàng khác', style: SboxType.captionStyle()),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Xem lại'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Vẫn lưu'))),
        ],
      ),
    );
  }

  // ─── Khung ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final info = _infoPanel();
    final modules = _modulesPanel();
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.white,
        surfaceTintColor: SboxColors.white,
        title: Text(tr(_isEdit ? 'Sửa gói «${p['name']}»' : widget.asCopy ? 'Tạo bản sao gói' : 'Tạo gói dịch vụ')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: SboxButton(label: 'Lưu gói', icon: Icons.save_outlined, loading: _saving, size: SboxButtonSize.sm, onPressed: _saving ? null : _save)),
          ),
        ],
      ),
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 420, child: ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [info])),
              const VerticalDivider(width: 1),
              Expanded(child: ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [modules])),
            ])
          : ListView(padding: const EdgeInsets.all(SboxSpace.md), children: [info, const SizedBox(height: SboxSpace.md), modules]),
    );
  }

  Widget _numField(TextEditingController t, String label, {String? suffix, String? helper}) => TextField(
        controller: t,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: saInput(label, suffix: suffix, helper: helper),
      );

  Widget _infoPanel() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SboxCard(
        title: 'Thông tin gói',
        child: Column(children: [
          TextField(controller: _name, decoration: saInput('Tên gói')),
          const SizedBox(height: SboxSpace.md),
          TextField(controller: _desc, maxLines: 2, decoration: saInput('Mô tả ngắn')),
          const SizedBox(height: SboxSpace.sm),
          SaSegment<String>(
            value: _line,
            options: const {'pos': 'Bán hàng', 'hrm': 'Nhân sự', 'both': 'Bán hàng + Nhân sự'},
            onChanged: (v) => setState(() => _line = v),
          ),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v),
              title: Text(tr('Gói đang bật'))),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: _public, onChanged: (v) => setState(() => _public = v),
              title: Text(tr('Hiện trên form đăng ký / bảng giá')), subtitle: Text(tr('Tắt = chỉ Super Admin / đại lý gán tay'))),
        ]),
      ),
      const SizedBox(height: SboxSpace.md),
      SboxCard(
        title: 'Giá & bán hàng',
        child: Column(children: [
          Row(children: [
            Expanded(child: _numField(_monthly, 'Giá / tháng', suffix: '₫', helper: 'Trống = liên hệ')),
            const SizedBox(width: SboxSpace.sm),
            Expanded(child: _numField(_yearly, 'Giá / năm', suffix: '₫', helper: 'Trống = không bán theo năm')),
          ]),
          const SizedBox(height: SboxSpace.md),
          Row(children: [
            Expanded(child: _numField(_days, 'Hạn mặc định', suffix: 'ngày')),
            const SizedBox(width: SboxSpace.sm),
            Expanded(child: _numField(_trial, 'Dùng thử', suffix: 'ngày')),
            const SizedBox(width: SboxSpace.sm),
            Expanded(child: _numField(_sort, 'Thứ tự')),
          ]),
          const SizedBox(height: SboxSpace.md),
          TextField(controller: _badge, decoration: saInput('Nhãn', hint: 'VD: Tiết kiệm 20%')),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: _featured, onChanged: (v) => setState(() => _featured = v),
              title: Text(tr('Đánh dấu «Phổ biến» trên bảng giá'))),
          TextField(controller: _highlights, maxLines: 4, decoration: saInput('Điểm nổi bật (mỗi dòng một ý)')),
        ]),
      ),
      const SizedBox(height: SboxSpace.md),
      SboxCard(
        title: 'Giới hạn',
        subtitle: '0 = không giới hạn',
        child: Column(children: [
          Row(children: [
            Expanded(child: _numField(_users, 'Tài khoản')),
            const SizedBox(width: SboxSpace.sm),
            Expanded(child: _numField(_branches, 'Chi nhánh')),
          ]),
          const SizedBox(height: SboxSpace.md),
          Row(children: [
            Expanded(child: _numField(_devices, 'Máy chấm công')),
            const SizedBox(width: SboxSpace.sm),
            Expanded(child: _numField(_access, 'Thiết bị đăng nhập')),
          ]),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: _web, onChanged: (v) => setState(() => _web = v), title: Text(tr('Dùng trên web'))),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: _mobile, onChanged: (v) => setState(() => _mobile = v), title: Text(tr('Dùng trên điện thoại'))),
        ]),
      ),
      const SizedBox(height: SboxSpace.md),
      SboxCard(
        title: 'Lưu trữ dữ liệu',
        subtitle: 'Tự xoá dữ liệu cũ của cửa hàng dùng gói này · 0 = giữ mãi',
        child: Column(children: [
          Row(children: [
            Expanded(child: _numField(_retAttendance, 'Chấm công giữ', suffix: 'tháng', helper: 'Tối đa 120')),
            const SizedBox(width: SboxSpace.sm),
            Expanded(child: _numField(_retSaleOrders, 'Đơn bán hàng giữ', suffix: 'tháng', helper: 'Tối đa 120')),
          ]),
          const SizedBox(height: SboxSpace.md),
          _numField(_retHour, 'Giờ chạy dọn dữ liệu', suffix: 'giờ', helper: '0–23, nên chọn giờ vắng khách'),
        ]),
      ),
      const SizedBox(height: SboxSpace.md),
      SboxCard(
        title: 'Thông báo đẩy',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: _fcm, onChanged: (v) => setState(() => _fcm = v), title: Text(tr('Cho phép thông báo đẩy'))),
          if (_fcm)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final f in c.fcm)
                FilterChip(
                  label: Text(tr(f.name), style: SboxType.captionStyle()),
                  selected: _fcmCats.contains(f.code),
                  onSelected: (v) => setState(() => v ? _fcmCats.add(f.code) : _fcmCats.remove(f.code)),
                ),
            ]),
          if (_fcm)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('Không chọn loại nào = nhận mọi loại'), style: SboxType.captionStyle()),
            ),
        ]),
      ),
    ]);
  }

  Widget _modulesPanel() {
    final q = _q.trim().toLowerCase();
    final missing = c.missing(_mods);
    final cats = c.categories.where((cat) => _lineFilter.isEmpty || cat.productLine == _lineFilter || cat.productLine == 'common').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Chức năng trong gói (${_mods.length})', style: SboxType.titleSmStyle())),
        TextButton(onPressed: () => setState(_mods.clear), child: Text(tr('Bỏ chọn hết'))),
      ]),
      const SizedBox(height: SboxSpace.xs),
      Text(tr('Áp mẫu nhanh'), style: SboxType.captionStyle()),
      const SizedBox(height: SboxSpace.xs),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final pr in c.presets)
          ActionChip(
            avatar: Icon(Icons.auto_fix_high_outlined, size: 16, color: saProductLineTone(pr.productLine).fg),
            label: Text('${pr.name} (${pr.modules.length})', style: SboxType.captionStyle(SboxColors.text)),
            onPressed: () => _applyPreset(pr),
          ),
      ]),
      const SizedBox(height: SboxSpace.md),
      if (missing.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: SboxSpace.md),
          padding: const EdgeInsets.all(SboxSpace.md),
          decoration: BoxDecoration(color: SboxColors.dangerSoft, borderRadius: SboxRadius.mdAll),
          child: Row(children: [
            const Icon(Icons.link_off_rounded, color: SboxColors.danger),
            const SizedBox(width: SboxSpace.sm),
            Expanded(
              child: Text(
                missing.take(3).map((m) => '«${c.nameOf(m.$1)}» cần «${c.nameOf(m.$2)}»').join(' · ') +
                    (missing.length > 3 ? ' · +${missing.length - 3}' : ''),
                style: SboxType.smallStyle(SboxColors.dangerText),
              ),
            ),
            SboxButton.secondary(
              label: 'Tự thêm',
              size: SboxButtonSize.sm,
              onPressed: () => setState(() {
                final all = c.withDependencies(_mods);
                _mods
                  ..clear()
                  ..addAll(all);
              }),
            ),
          ]),
        ),
      Row(children: [
        Expanded(
          child: SaSegment<String>(
            value: _lineFilter,
            options: const {'': 'Mọi nhóm', 'pos': 'Bán hàng', 'hrm': 'Nhân sự'},
            onChanged: (v) => setState(() => _lineFilter = v),
          ),
        ),
        SizedBox(
          width: 220,
          child: TextField(
            decoration: saInput('Tìm chức năng').copyWith(prefixIcon: const Icon(Icons.search_rounded, size: 18)),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
      ]),
      const SizedBox(height: SboxSpace.sm),
      for (final cat in cats) _categoryTile(cat.name, q),
    ]);
  }

  Widget _categoryTile(String category, String q) {
    final all = c.modules.where((m) => m.category == category).toList();
    final items = q.isEmpty ? all : all.where((m) => '${m.name} ${m.description} ${m.code}'.toLowerCase().contains(q)).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final on = all.where((m) => _has(m.code)).length;
    final state = on == 0 ? false : on == all.length ? true : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: SboxSpace.sm),
      child: Material(
      color: SboxColors.white,
      shape: RoundedRectangleBorder(borderRadius: SboxRadius.mdAll, side: const BorderSide(color: SboxColors.border)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('cat_$category'),
          initiallyExpanded: q.isNotEmpty || (on > 0 && on < all.length),
          tilePadding: const EdgeInsets.symmetric(horizontal: SboxSpace.sm),
          leading: Checkbox(
            value: state,
            tristate: true,
            onChanged: (_) => setState(() {
              if (state == true) {
                for (final m in all) {
                  _mods.removeWhere((x) => x.toLowerCase() == m.code.toLowerCase());
                }
              } else {
                for (final m in all) {
                  if (!_has(m.code)) _mods.add(m.code);
                }
              }
            }),
          ),
          title: Text(tr(category), style: SboxType.bodyStrong()),
          subtitle: Text('$on/${all.length} chức năng', style: SboxType.captionStyle()),
          children: [
            for (final m in items)
              CheckboxListTile(
                dense: true,
                value: _has(m.code),
                onChanged: (v) => _toggle(m.code, v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(tr(m.name), style: SboxType.bodyStyle()),
                subtitle: Text(
                  [m.description, if (m.requires.isNotEmpty) 'Cần: ${m.requires.map(c.nameOf).join(', ')}'].join(' · '),
                  style: SboxType.captionStyle(),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}
