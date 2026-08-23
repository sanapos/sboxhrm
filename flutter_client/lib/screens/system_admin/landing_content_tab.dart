import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../../services/api_service.dart';
import '../../utils/landing_guide_url.dart';
import '../../utils/landing_usage_guide.dart';
import 'system_admin_helpers.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// SuperAdmin – Tab quản lý nội dung trang Landing Page của SBOX HRM.
class LandingContentTab extends StatefulWidget {
  const LandingContentTab({super.key});

  @override
  State<LandingContentTab> createState() => LandingContentTabState();
}

class LandingContentTabState extends State<LandingContentTab>
    with SingleTickerProviderStateMixin {
  late final TabController _sub;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 9, vsync: this);
  }

  @override
  void dispose() {
    _sub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AdminHelpers.bgLight,
          child: TabBar(
            controller: _sub,
            isScrollable: true,
            labelColor: AdminHelpers.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AdminHelpers.primary,
            tabs: [
              Tab(icon: Icon(Icons.home_rounded), text: tr('Hero & Liên hệ')),
              Tab(icon: Icon(Icons.star_rounded), text: tr('Tính năng')),
              Tab(icon: Icon(Icons.inventory_2_rounded), text: tr('Gói dịch vụ')),
              Tab(icon: Icon(Icons.list_alt_rounded), text: tr('Hướng dẫn')),
              Tab(icon: Icon(Icons.video_library_rounded), text: tr('Video')),
              Tab(icon: Icon(Icons.devices_rounded), text: tr('Sản phẩm')),
              Tab(icon: Icon(Icons.download_rounded), text: tr('Tải về')),
              Tab(icon: Icon(Icons.help_outline_rounded), text: tr('FAQ')),
              Tab(icon: Icon(Icons.travel_explore_rounded), text: tr('SEO Google')),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _sub,
            children: [
              _HeroContactSubTab(api: _api),
              _FeaturesSubTab(api: _api),
              _PricingSubTab(api: _api),
              _GuideSubTab(api: _api),
              _VideoSubTab(api: _api),
              _ProductsSubTab(api: _api),
              _DownloadsSubTab(api: _api),
              _FaqSubTab(api: _api),
              _SeoGoogleSubTab(api: _api),
            ],
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------
// Sub-tab 1: Hero & Liên hệ
// -------------------------------------------------------
class _HeroContactSubTab extends StatefulWidget {
  const _HeroContactSubTab({required this.api});
  final ApiService api;

  @override
  State<_HeroContactSubTab> createState() => _HeroContactSubTabState();
}

class _HeroContactSubTabState extends State<_HeroContactSubTab> {
  bool _loading = false;
  bool _saving = false;

  // Keys phải khớp với AppSettingKeys trong backend
  final _fields = <String, TextEditingController>{
    'landing_hero_title': TextEditingController(),
    'landing_hero_subtext': TextEditingController(),
    'technical_support_phone': TextEditingController(),
    'zalo_url': TextEditingController(),
    'technical_support_email': TextEditingController(),
    'company_address': TextEditingController(),
  };

  static const _labels = {
    'landing_hero_title': 'Tiêu đề Hero',
    'landing_hero_subtext': 'Mô tả Hero',
    'technical_support_phone': 'Số điện thoại / Hotline',
    'zalo_url': 'Số Zalo (hoặc link zalo.me/...)',
    'technical_support_email': 'Email liên hệ',
    'company_address': 'Địa chỉ',
  };

  static const _multiline = {
    'landing_hero_title',
    'landing_hero_subtext',
    'company_address'
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getAllAppSettings();
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final list = List<Map<String, dynamic>>.from(res['data'] ?? []);
        for (final s in list) {
          final key = s['key']?.toString() ?? '';
          if (_fields.containsKey(key)) {
            _fields[key]!.text = s['value']?.toString() ?? '';
          }
        }
      }
    } catch (e) {
      debugPrint('HeroContact load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updates = _fields.entries
          .map((e) => {'key': e.key, 'value': e.value.text.trim()})
          .toList();
      final res = await widget.api.updateAppSettingsBatch(updates);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        AdminHelpers.showSuccess(context, 'Đã lưu nội dung Hero & Liên hệ!');
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      if (mounted) AdminHelpers.showError(context, 'Lỗi: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Hero Section', Icons.web_rounded),
          const SizedBox(height: 4),
          Text(tr('Nội dung hiển thị ở phần đầu trang chủ'),
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
          const SizedBox(height: 16),
          ...[
            'landing_hero_title',
            'landing_hero_subtext',
          ].map((k) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildField(k),
              )),
          const Divider(height: 32),
          _sectionHeader('Thông tin liên hệ', Icons.contact_phone_rounded),
          const SizedBox(height: 16),
          ...[
            'technical_support_phone',
            'zalo_url',
            'technical_support_email',
            'company_address',
          ].map((k) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildField(k),
              )),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (context.systemAdminCanEdit && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(tr(_saving ? 'Đang lưu...' : 'Lưu thay đổi')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String key) {
    final isMulti = _multiline.contains(key);
    return TextFormField(
      controller: _fields[key],
      maxLines: isMulti ? 3 : 1,
      decoration: InputDecoration(
        labelText: tr(_labels[key] ?? key),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(children: [
      Icon(icon, color: AdminHelpers.primary, size: 20),
      const SizedBox(width: 8),
      Text(tr(title),
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Color(0xFF111827))),
    ]);
  }
}

// -------------------------------------------------------
// Sub-tab 2: Tính năng
// -------------------------------------------------------
class _FeaturesSubTab extends StatefulWidget {
  const _FeaturesSubTab({required this.api});
  final ApiService api;

  @override
  State<_FeaturesSubTab> createState() => _FeaturesSubTabState();
}

class _FeaturesSubTabState extends State<_FeaturesSubTab> {
  bool _loading = false;
  bool _saving = false;
  List<_FeatureItem> _items = [];

  static const _defaultFeatures = [
    (
      'Chấm công mobile khuôn mặt',
      'Nhận diện khuôn mặt bằng AI ngay trên điện thoại. Xác minh GPS và WiFi để đảm bảo chấm công đúng địa điểm.'
    ),
    (
      'Kết nối máy chấm công Realtime',
      'Đồng bộ máy ZKTeco qua ADMS/PUSH theo thời gian thực — dữ liệu chấm công về hệ thống ngay khi quẹt.'
    ),
    (
      'Quản lý ca làm việc',
      'Tạo ca linh hoạt, xoay ca, tăng ca, nghỉ bù. Hỗ trợ ca qua đêm và lịch làm việc phức tạp.'
    ),
    (
      'Tính lương tự động',
      'Tự động tính lương theo ngày công, phụ cấp, thưởng, khấu trừ BHXH/thuế TNCN.'
    ),
    (
      'Quản lý nghỉ phép',
      'Theo dõi ngày phép, xét duyệt trực tuyến, tổng hợp báo cáo nghỉ phép theo tháng/năm.'
    ),
    (
      'Chấm công ngoài hiện trường',
      'GPS check-in/check-out có ảnh xác thực khuôn mặt, hỗ trợ nhân viên field sales.'
    ),
    (
      'Báo cáo & Phân tích',
      'Dashboard trực quan, báo cáo chuyên cần, tổng hợp lương, xuất Excel tức thì.'
    ),
    (
      'Quản lý bữa ăn',
      'Đăng ký xuất ăn, theo dõi khẩu phần thực tế, báo cáo chi phí bữa ăn hàng ngày.'
    ),
    (
      'Quản lý công việc',
      'Giao việc, theo dõi tiến độ, KPI cá nhân và phòng ban theo thời gian thực.'
    ),
    (
      'App Mobile',
      'Ứng dụng Android/iOS đầy đủ tính năng – chấm công, xem lịch, phê duyệt nghỉ phép mọi nơi.'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.titleCtrl.dispose();
      item.descCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getAllAppSettings();
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final list = List<Map<String, dynamic>>.from(res['data'] ?? []);
        final entry = list.firstWhere(
            (s) => s['key'] == 'landing_features_json',
            orElse: () => {});
        final raw = entry['value']?.toString() ?? '';
        if (raw.isNotEmpty) {
          final arr = jsonDecode(raw) as List;
          _items = arr
              .map((e) => _FeatureItem(e['title'] ?? '', e['desc'] ?? ''))
              .toList();
        }
      }
    } catch (_) {}
    if (_items.isEmpty) {
      _items = _defaultFeatures.map((e) => _FeatureItem(e.$1, e.$2)).toList();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final json = jsonEncode(_items
          .where((i) => i.titleCtrl.text.trim().isNotEmpty)
          .map((i) => {
                'title': i.titleCtrl.text.trim(),
                'desc': i.descCtrl.text.trim()
              })
          .toList());
      final res = await widget.api.updateAppSettingsBatch([
        {'key': 'landing_features_json', 'value': json}
      ]);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        AdminHelpers.showSuccess(context, 'Đã lưu danh sách tính năng!');
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      if (mounted) AdminHelpers.showError(context, 'Lỗi: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _addItem() => setState(() => _items.add(_FeatureItem('', '')));
  void _removeItem(int idx) => setState(() {
        _items[idx].titleCtrl.dispose();
        _items[idx].descCtrl.dispose();
        _items.removeAt(idx);
      });

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text(tr('Danh sách tính năng'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              FilledButton.icon(
                onPressed: context.systemAdminCanEdit ? _addItem : null,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(tr('Thêm')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _items.length,
            onReorder: (from, to) {
              setState(() {
                final item = _items.removeAt(from);
                _items.insert(to > from ? to - 1 : to, item);
              });
            },
            itemBuilder: (_, idx) {
              final item = _items[idx];
              return Card(
                key: ValueKey(idx),
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 14, right: 8),
                        child: Icon(Icons.drag_handle_rounded,
                            color: Colors.grey, size: 20),
                      ),
                      Expanded(
                        child: Column(children: [
                          TextField(
                            controller: item.titleCtrl,
                            decoration: InputDecoration(
                              labelText: tr('Tiêu đề tính năng'),
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: item.descCtrl,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: tr('Mô tả chi tiết'),
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ]),
                      ),
                      IconButton(
                        onPressed: context.systemAdminCanEdit ? () => _removeItem(idx) : null,
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.red),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (context.systemAdminCanEdit && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(tr(_saving ? 'Đang lưu...' : 'Lưu danh sách tính năng')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureItem {
  _FeatureItem(String title, String desc)
      : titleCtrl = TextEditingController(text: tr(title)),
        descCtrl = TextEditingController(text: tr(desc));
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
}

// -------------------------------------------------------
// Sub-tab 3: Gói dịch vụ (giá)
// -------------------------------------------------------
class _PricingSubTab extends StatefulWidget {
  const _PricingSubTab({required this.api});
  final ApiService api;

  @override
  State<_PricingSubTab> createState() => _PricingSubTabState();
}

class _PricePlan {
  _PricePlan(String name, String price, String unit, String desc,
      {this.highlight = false,
      this.contactOnly = false,
      List<String>? features})
      : nameCtrl = TextEditingController(text: tr(name)),
        priceCtrl = TextEditingController(text: tr(price)),
        unitCtrl = TextEditingController(text: tr(unit)),
        descCtrl = TextEditingController(text: tr(desc)),
        featureCtrlsList = (features ?? [])
            .map((f) => TextEditingController(text: tr(f)))
            .toList();

  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController unitCtrl;
  final TextEditingController descCtrl;
  bool highlight;
  bool contactOnly;
  List<TextEditingController> featureCtrlsList;

  void disposeAll() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    unitCtrl.dispose();
    descCtrl.dispose();
    for (final c in featureCtrlsList) {
      c.dispose();
    }
  }
}

class _PricingSubTabState extends State<_PricingSubTab> {
  bool _loading = false;
  bool _saving = false;
  List<_PricePlan> _plans = [];

  static List<_PricePlan> _defaultPlans() => [
        _PricePlan(
            'Miễn phí', '0', 'đ/năm', 'Trải nghiệm đầy đủ tính năng cơ bản',
            features: [
              'Tối đa 10 nhân viên',
              '1 thiết bị ZKTeco',
              'Chấm công & báo cáo cơ bản',
              'App mobile',
              'Hỗ trợ qua email'
            ]),
        _PricePlan('Hộ kinh doanh', '900.000', 'đ/năm',
            'Dành cho hộ kinh doanh & cửa hàng nhỏ',
            highlight: true,
            features: [
              'Tối đa 30 nhân viên',
              '2 thiết bị ZKTeco',
              'Chấm công & ca làm việc',
              'Tính lương tự động',
              'Quản lý nghỉ phép',
              'Báo cáo chi tiết',
              'Hỗ trợ Zalo 24/7'
            ]),
        _PricePlan(
            'Doanh nghiệp', '1.450.000', 'đ/năm', 'Cho doanh nghiệp vừa và lớn',
            features: [
              'Không giới hạn nhân viên',
              '5 thiết bị ZKTeco',
              'Đầy đủ tính năng HRM',
              'Chấm công ngoài hiện trường',
              'KPI & công việc',
              'Quản lý bữa ăn',
              'Google Sheets sync',
              'Hỗ trợ ưu tiên 24/7'
            ]),
        _PricePlan('Nhà máy SX', 'Từ 1.950.000', 'đ/năm',
            'Tối ưu cho nhà máy sản xuất',
            contactOnly: true,
            features: [
              'Không giới hạn nhân viên',
              'Không giới hạn thiết bị',
              'Chấm công nhiều ca / dây chuyền',
              'Sản lượng & KPI sản xuất',
              'Tích hợp ERP/Odoo',
              'Báo cáo nhà máy chuyên sâu',
              'Triển khai tại chỗ (on-premise)',
              'Hỗ trợ kỹ thuật riêng'
            ]),
      ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final p in _plans) {
      p.disposeAll();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getAllAppSettings();
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final list = List<Map<String, dynamic>>.from(res['data'] ?? []);
        final entry = list.firstWhere((s) => s['key'] == 'landing_pricing_json',
            orElse: () => {});
        final raw = entry['value']?.toString() ?? '';
        if (raw.isNotEmpty) {
          final arr = jsonDecode(raw) as List;
          _plans = arr
              .map((e) => _PricePlan(
                    e['name'] ?? '',
                    e['price'] ?? '',
                    e['unit'] ?? 'đ/năm',
                    e['desc'] ?? '',
                    highlight: e['highlight'] == true,
                    contactOnly: e['contactOnly'] == true,
                    features: (e['features'] as List?)
                            ?.map((f) => f.toString())
                            .toList() ??
                        [],
                  ))
              .toList();
        }
      }
    } catch (_) {}
    if (_plans.isEmpty) _plans = _defaultPlans();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final json = jsonEncode(_plans
          .map((p) => {
                'name': p.nameCtrl.text.trim(),
                'price': p.priceCtrl.text.trim(),
                'unit': p.unitCtrl.text.trim(),
                'desc': p.descCtrl.text.trim(),
                'highlight': p.highlight,
                'contactOnly': p.contactOnly,
                'features': p.featureCtrlsList
                    .map((c) => c.text.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
              })
          .toList());
      final res = await widget.api.updateAppSettingsBatch([
        {'key': 'landing_pricing_json', 'value': json}
      ]);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        AdminHelpers.showSuccess(context, 'Đã lưu bảng giá!');
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      if (mounted) AdminHelpers.showError(context, 'Lỗi: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _addPlan() =>
      setState(() => _plans.add(_PricePlan('', '', 'đ/năm', '')));
  void _removePlan(int idx) => setState(() {
        _plans[idx].disposeAll();
        _plans.removeAt(idx);
      });
  void _addFeature(int planIdx) => setState(() {
        _plans[planIdx].featureCtrlsList.add(TextEditingController());
      });
  void _removeFeature(int planIdx, int featIdx) => setState(() {
        _plans[planIdx].featureCtrlsList[featIdx].dispose();
        _plans[planIdx].featureCtrlsList.removeAt(featIdx);
      });

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                  child: Text(tr('Gói dịch vụ & Bảng giá'),
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15))),
              FilledButton.icon(
                onPressed: context.systemAdminCanEdit ? _addPlan : null,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(tr('Thêm gói')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _plans.length,
            itemBuilder: (_, idx) {
              final p = _plans[idx];
              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: p.nameCtrl,
                              decoration: InputDecoration(
                                labelText: tr('Tên gói'),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: context.systemAdminCanEdit ? () => _removePlan(idx) : null,
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: Colors.red),
                            tooltip: tr('Xóa gói'),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: p.priceCtrl,
                              decoration: InputDecoration(
                                labelText: tr('Giá (VD: 900.000)'),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: p.unitCtrl,
                              decoration: InputDecoration(
                                labelText: tr('Đơn vị (đ/năm)'),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        TextField(
                          controller: p.descCtrl,
                          decoration: InputDecoration(
                            labelText: tr('Mô tả gói'),
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          Checkbox(
                            value: p.highlight,
                            activeColor: AdminHelpers.primary,
                            onChanged: (v) =>
                                setState(() => p.highlight = v ?? false),
                          ),
                          Text(tr('Nổi bật (highlight)'),
                              style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 20),
                          Checkbox(
                            value: p.contactOnly,
                            activeColor: AdminHelpers.primary,
                            onChanged: (v) =>
                                setState(() => p.contactOnly = v ?? false),
                          ),
                          Text(tr('Liên hệ để báo giá'),
                              style: TextStyle(fontSize: 13)),
                        ]),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(tr('Tính năng trong gói'),
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            TextButton.icon(
                              onPressed: context.systemAdminCanEdit
                                  ? () => _addFeature(idx)
                                  : null,
                              icon: const Icon(Icons.add_circle_outline_rounded,
                                  size: 16),
                              label: Text(tr('Thêm tính năng'),
                                  style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                  foregroundColor: AdminHelpers.primary,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4)),
                            ),
                          ],
                        ),
                        if (p.featureCtrlsList.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Text(tr('Chưa có tính năng. Nhấn "Thêm tính năng" dể bổ sung.'),
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic)),
                          )
                        else
                          ...List.generate(
                              p.featureCtrlsList.length,
                              (fi) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(children: [
                                      const Icon(
                                          Icons.check_circle_outline_rounded,
                                          size: 16,
                                          color: Colors.blueGrey),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: TextField(
                                          controller: p.featureCtrlsList[fi],
                                          decoration: InputDecoration(
                                            hintText: tr('VD: Tối đa 30 nhân viên'),
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8),
                                          ),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      if (context.systemAdminCanEdit)
                                        IconButton(
                                          onPressed: () =>
                                              _removeFeature(idx, fi),
                                          icon: const Icon(
                                              Icons
                                                  .remove_circle_outline_rounded,
                                              color: Colors.red,
                                              size: 18),
                                          tooltip: tr('Xóa'),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 32, minHeight: 32),
                                      ),
                                    ]),
                                  )),
                      ]),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (context.systemAdminCanEdit && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(tr(_saving ? 'Đang lưu...' : 'Lưu bảng giá')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------
// Sub-tab 4: Hướng dẫn (cơ bản + nâng cao)
// -------------------------------------------------------
class _GuideSubTab extends StatefulWidget {
  const _GuideSubTab({required this.api});
  final ApiService api;

  @override
  State<_GuideSubTab> createState() => _GuideSubTabState();
}

class _GuideSubTabState extends State<_GuideSubTab>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  bool _saving = false;
  late final TabController _guideTab;
  List<_GuideStepEditor> _basicSteps = [];
  List<_GuideStepEditor> _advancedSteps = [];
  List<_GuideStepEditor> _posSteps = [];

  @override
  void initState() {
    super.initState();
    _guideTab = TabController(length: 3, vsync: this);
    _guideTab.addListener(() {
      if (!_guideTab.indexIsChanging && mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _guideTab.dispose();
    for (final s in [..._basicSteps, ..._advancedSteps, ..._posSteps]) {
      s.dispose();
    }
    super.dispose();
  }

  void _setFromDocument(LandingGuideData doc) {
    for (final s in [..._basicSteps, ..._advancedSteps, ..._posSteps]) {
      s.dispose();
    }
    _basicSteps = doc.basic.map(_GuideStepEditor.fromStep).toList();
    _advancedSteps = doc.advanced.map(_GuideStepEditor.fromStep).toList();
    _posSteps = doc.pos.map(_GuideStepEditor.fromStep).toList();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    var raw = '';
    try {
      final res = await widget.api.getAllAppSettings();
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final list = List<Map<String, dynamic>>.from(res['data'] ?? []);
        final entry = list.firstWhere((s) => s['key'] == 'landing_guide_json',
            orElse: () => {});
        raw = entry['value']?.toString() ?? '';
      }
    } catch (_) {}
    _setFromDocument(LandingGuideData.fromApiJson(raw.isEmpty ? null : raw));
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final doc = LandingGuideData(
        basic: _basicSteps.map((e) => e.toStep()).toList(),
        advanced: _advancedSteps.map((e) => e.toStep()).toList(),
        pos: _posSteps.map((e) => e.toStep()).toList(),
      );
      final res = await widget.api.updateAppSettingsBatch([
        {'key': 'landing_guide_json', 'value': doc.toJsonString()}
      ]);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        AdminHelpers.showSuccess(context, 'Đã lưu hướng dẫn!');
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      if (mounted) AdminHelpers.showError(context, 'Lỗi: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _copyGuideLink(String sectionKey, String stepId) async {
    final link = LandingGuideUrl.buildLink(section: sectionKey, stepId: stepId);
    await Clipboard.setData(ClipboardData(text: tr(link)));
    if (mounted) {
      AdminHelpers.showSuccess(context, 'Đã copy link hướng dẫn');
    }
  }

  void _resetCurrentSection() {
    final idx = _guideTab.index;
    setState(() {
      if (idx == 0) {
        for (final s in _basicSteps) {
          s.dispose();
        }
        _basicSteps = LandingGuideData.defaults.basic
            .map(_GuideStepEditor.fromStep)
            .toList();
      } else if (idx == 1) {
        for (final s in _advancedSteps) {
          s.dispose();
        }
        _advancedSteps = LandingGuideData.defaults.advanced
            .map(_GuideStepEditor.fromStep)
            .toList();
      } else {
        for (final s in _posSteps) {
          s.dispose();
        }
        _posSteps = LandingGuideData.defaults.pos
            .map(_GuideStepEditor.fromStep)
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Container(
          color: AdminHelpers.bgLight,
          child: TabBar(
            controller: _guideTab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AdminHelpers.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AdminHelpers.primary,
            tabs: [
              Tab(text: tr('Triển khai (${_basicSteps.length})')),
              Tab(text: tr('Nâng cao (${_advancedSteps.length})')),
              Tab(text: tr('POS (${_posSteps.length})')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr(switch (_guideTab.index) {
                    1 => 'Vận hành HRM sau triển khai (lịch, KPI, phép…)',
                    2 => 'POS: A6/A7, in, bếp, kho, báo cáo bán hàng',
                    _ => 'Triển khai từ đăng ký đến báo cáo HRM',
                  }),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              TextButton.icon(
                onPressed: context.systemAdminCanEdit ? _resetCurrentSection : null,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: Text(tr('Khôi phục mặc định')),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _guideTab,
            children: [
              _buildStepList(_basicSteps, 'basic'),
              _buildStepList(_advancedSteps, 'advanced'),
              _buildStepList(_posSteps, 'pos'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (context.systemAdminCanEdit && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(tr(_saving ? 'Đang lưu...' : 'Lưu hướng dẫn')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepList(List<_GuideStepEditor> steps, String sectionKey) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: steps.length,
      onReorder: context.systemAdminCanEdit
          ? (from, to) {
              setState(() {
                final item = steps.removeAt(from);
                steps.insert(to > from ? to - 1 : to, item);
              });
            }
          : (_, __) {},
      itemBuilder: (_, idx) {
        final step = steps[idx];
        return Card(
          key: ValueKey('$sectionKey-${step.id}'),
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (context.systemAdminCanEdit)
                  ReorderableDragStartListener(
                    index: idx,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, right: 10),
                      child: Icon(Icons.drag_handle_rounded,
                          color: Colors.grey[500]),
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.only(top: 6, right: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AdminHelpers.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(tr('${idx + 1}'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(tr('ID: ${step.id}'),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600])),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () =>
                                _copyGuideLink(sectionKey, step.id),
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: Text(tr('Copy link')),
                            style: TextButton.styleFrom(
                              foregroundColor: AdminHelpers.primary,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SelectableText(
                          tr(LandingGuideUrl.buildLink(
                            section: sectionKey,
                            stepId: step.id,
                          )),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: step.titleCtrl,
                        readOnly: !context.systemAdminCanEdit,
                        decoration: InputDecoration(
                          labelText: tr('Tiêu đề'),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: step.descCtrl,
                        readOnly: !context.systemAdminCanEdit,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: tr('Mô tả'),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: step.bulletsCtrl,
                        readOnly: !context.systemAdminCanEdit,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: tr('Các bước (mỗi dòng một ý — nên bắt đầu bằng Bước 1, Bước 2…)'),
                          isDense: true,
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: step.keywordsCtrl,
                        readOnly: !context.systemAdminCanEdit,
                        decoration: InputDecoration(
                          labelText: tr('Từ khóa tìm kiếm (cách nhau bằng dấu phẩy)'),
                          isDense: true,
                          border: OutlineInputBorder(),
                          hintText: tr('vd: máy chấm công, vân tay, ADMS'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: step.tipCtrl,
                        readOnly: !context.systemAdminCanEdit,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: tr('Mẹo / lưu ý (tuỳ chọn)'),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: step.videoUrlCtrl,
                        readOnly: !context.systemAdminCanEdit,
                        decoration: InputDecoration(
                          labelText: tr('Video (link YouTube)'),
                          isDense: true,
                          border: OutlineInputBorder(),
                          hintText: tr('https://www.youtube.com/watch?v=...'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: step.imageUrlsCtrl,
                        readOnly: !context.systemAdminCanEdit,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: tr('Hình ảnh (mỗi dòng một URL)'),
                          isDense: true,
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                          hintText: tr('https://sboxhrm.com/images/...'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GuideStepEditor {
  _GuideStepEditor({
    required this.id,
    required this.icon,
    required this.accent,
    required String title,
    required String desc,
    required List<String> bullets,
    required String tip,
    required List<String> imageUrls,
    required String videoUrl,
    required List<String> keywords,
  })  : titleCtrl = TextEditingController(text: tr(title)),
        descCtrl = TextEditingController(text: tr(desc)),
        bulletsCtrl = TextEditingController(text: tr(bullets.join('\n'))),
        tipCtrl = TextEditingController(text: tr(tip)),
        imageUrlsCtrl = TextEditingController(text: tr(imageUrls.join('\n'))),
        videoUrlCtrl = TextEditingController(text: tr(videoUrl)),
        keywordsCtrl = TextEditingController(text: tr(keywords.join(', ')));

  factory _GuideStepEditor.fromStep(LandingUsageGuideStep step) {
    return _GuideStepEditor(
      id: step.id,
      icon: step.icon,
      accent: step.accent,
      title: step.title,
      desc: step.desc,
      bullets: step.bullets,
      tip: step.tip,
      imageUrls: step.imageUrls,
      videoUrl: step.videoUrl,
      keywords: step.keywords,
    );
  }

  final String id;
  final IconData icon;
  final Color accent;
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final TextEditingController bulletsCtrl;
  final TextEditingController tipCtrl;
  final TextEditingController imageUrlsCtrl;
  final TextEditingController videoUrlCtrl;
  final TextEditingController keywordsCtrl;

  void dispose() {
    titleCtrl.dispose();
    descCtrl.dispose();
    bulletsCtrl.dispose();
    tipCtrl.dispose();
    imageUrlsCtrl.dispose();
    videoUrlCtrl.dispose();
    keywordsCtrl.dispose();
  }

  LandingUsageGuideStep toStep() {
    final bullets = bulletsCtrl.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final imageUrls = imageUrlsCtrl.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final keywords = keywordsCtrl.text
        .split(RegExp(r'[,;|/]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return LandingUsageGuideStep(
      id: id,
      icon: icon,
      accent: accent,
      title: titleCtrl.text.trim(),
      desc: descCtrl.text.trim(),
      bullets: bullets,
      tip: tipCtrl.text.trim(),
      imageUrls: imageUrls,
      videoUrl: videoUrlCtrl.text.trim(),
      keywords: keywords,
    );
  }
}

// -------------------------------------------------------
// Sub-tab 5: Video
// -------------------------------------------------------
class _VideoSubTab extends StatefulWidget {
  const _VideoSubTab({required this.api});
  final ApiService api;

  @override
  State<_VideoSubTab> createState() => _VideoSubTabState();
}

class _VideoSubTabState extends State<_VideoSubTab> {
  bool _loading = false;
  bool _saving = false;

  // Video 1: Giời thiểu
  final _introUrlCtrl = TextEditingController();
  final _introTitleCtrl = TextEditingController(text: tr('Video giới thiệu'));
  final _introSubtitleCtrl = TextEditingController(
      text: tr('Tổng quan SBOX HRM – chấm công, lương, ca làm, báo cáo'));
  final _introBadgeCtrl = TextEditingController(text: tr('Xem ngay'));
  final _introDurationCtrl = TextEditingController(text: tr('3:45'));

  // Video 2: Hướng dẫn
  final _guideUrlCtrl = TextEditingController();
  final _guideTitleCtrl = TextEditingController(text: tr('Video hướng dẫn'));
  final _guideSubtitleCtrl = TextEditingController(
      text: tr('Thiết lập từ A–Z: kết nối máy, thêm nhân viên, cài ca'));
  final _guideBadgeCtrl = TextEditingController(text: tr('Học ngay'));
  final _guideDurationCtrl = TextEditingController(text: tr('12:00'));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _introUrlCtrl.dispose();
    _introTitleCtrl.dispose();
    _introSubtitleCtrl.dispose();
    _introBadgeCtrl.dispose();
    _introDurationCtrl.dispose();
    _guideUrlCtrl.dispose();
    _guideTitleCtrl.dispose();
    _guideSubtitleCtrl.dispose();
    _guideBadgeCtrl.dispose();
    _guideDurationCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getAllAppSettings();
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final list = List<Map<String, dynamic>>.from(res['data'] ?? []);

        void loadVideo(
            String key,
            TextEditingController urlCtrl,
            TextEditingController titleCtrl,
            TextEditingController subtitleCtrl,
            TextEditingController badgeCtrl,
            TextEditingController durationCtrl) {
          final entry =
              list.firstWhere((s) => s['key'] == key, orElse: () => {});
          final raw = entry['value']?.toString() ?? '';
          if (raw.isEmpty) return;
          try {
            final m = jsonDecode(raw) as Map<String, dynamic>;
            urlCtrl.text = m['url']?.toString() ?? '';
            if ((m['title']?.toString() ?? '').isNotEmpty) {
              titleCtrl.text = m['title']!;
            }
            if ((m['subtitle']?.toString() ?? '').isNotEmpty) {
              subtitleCtrl.text = m['subtitle']!;
            }
            if ((m['badge']?.toString() ?? '').isNotEmpty) {
              badgeCtrl.text = m['badge']!;
            }
            if ((m['duration']?.toString() ?? '').isNotEmpty) {
              durationCtrl.text = m['duration']!;
            }
          } catch (_) {
            // old format: plain URL
            if (raw.startsWith('http')) urlCtrl.text = raw;
          }
        }

        loadVideo('landing_video_intro', _introUrlCtrl, _introTitleCtrl,
            _introSubtitleCtrl, _introBadgeCtrl, _introDurationCtrl);
        loadVideo('landing_video_guide', _guideUrlCtrl, _guideTitleCtrl,
            _guideSubtitleCtrl, _guideBadgeCtrl, _guideDurationCtrl);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final introJson = jsonEncode({
        'url': _introUrlCtrl.text.trim(),
        'title': _introTitleCtrl.text.trim(),
        'subtitle': _introSubtitleCtrl.text.trim(),
        'badge': _introBadgeCtrl.text.trim(),
        'duration': _introDurationCtrl.text.trim(),
      });
      final guideJson = jsonEncode({
        'url': _guideUrlCtrl.text.trim(),
        'title': _guideTitleCtrl.text.trim(),
        'subtitle': _guideSubtitleCtrl.text.trim(),
        'badge': _guideBadgeCtrl.text.trim(),
        'duration': _guideDurationCtrl.text.trim(),
      });
      final res = await widget.api.updateAppSettingsBatch([
        {'key': 'landing_video_intro', 'value': introJson},
        {'key': 'landing_video_guide', 'value': guideJson},
      ]);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        AdminHelpers.showSuccess(context, 'Đã lưu cài đặt video!');
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      if (mounted) AdminHelpers.showError(context, 'Lỗi: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVideoCard(
            label: 'Video 1 – Giới thiệu',
            icon: Icons.play_circle_outline_rounded,
            color: const Color(0xFF0C56D0),
            urlCtrl: _introUrlCtrl,
            titleCtrl: _introTitleCtrl,
            subtitleCtrl: _introSubtitleCtrl,
            badgeCtrl: _introBadgeCtrl,
            durationCtrl: _introDurationCtrl,
          ),
          const SizedBox(height: 24),
          _buildVideoCard(
            label: 'Video 2 – Hướng dẫn',
            icon: Icons.school_rounded,
            color: const Color(0xFF1565C0),
            urlCtrl: _guideUrlCtrl,
            titleCtrl: _guideTitleCtrl,
            subtitleCtrl: _guideSubtitleCtrl,
            badgeCtrl: _guideBadgeCtrl,
            durationCtrl: _guideDurationCtrl,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (context.systemAdminCanEdit && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(tr(_saving ? 'Đang lưu...' : 'Lưu cài đặt video')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCard({
    required String label,
    required IconData icon,
    required Color color,
    required TextEditingController urlCtrl,
    required TextEditingController titleCtrl,
    required TextEditingController subtitleCtrl,
    required TextEditingController badgeCtrl,
    required TextEditingController durationCtrl,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(tr(label),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 16),
          TextFormField(
            controller: urlCtrl,
            decoration: InputDecoration(
              labelText: tr('URL YouTube (bắt buộc)'),
              hintText: tr('https://www.youtube.com/watch?v=...'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.link_rounded),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: tr('Tiêu đề video'),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: badgeCtrl,
                decoration: InputDecoration(
                  labelText: tr('Nhãn (badge)'),
                  hintText: tr('Xem ngay'),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 90,
              child: TextFormField(
                controller: durationCtrl,
                decoration: InputDecoration(
                  labelText: tr('Thời lượng'),
                  hintText: tr('3:45'),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: subtitleCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: tr('Mô tả ngắn'),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
      ),
    );
  }
}

// -------------------------------------------------------
// Sub-tab 6: Sản phẩm (Máy chấm công)
// -------------------------------------------------------
class _ProductsSubTab extends StatefulWidget {
  const _ProductsSubTab({required this.api});
  final ApiService api;

  @override
  State<_ProductsSubTab> createState() => _ProductsSubTabState();
}

class _ProductItem {
  _ProductItem({
    String name = '',
    String sub = '',
    String price = '',
    String oldPrice = '',
    String badge = '',
    String specs = '',
    this.specsDetail = '',
    String imageUrl = '',
    String link = '',
    String brand = '',
  })  : nameCtrl = TextEditingController(text: tr(name)),
        subCtrl = TextEditingController(text: tr(sub)),
        priceCtrl = TextEditingController(text: tr(price)),
        oldPriceCtrl = TextEditingController(text: tr(oldPrice)),
        badgeCtrl = TextEditingController(text: tr(badge)),
        specsCtrl = TextEditingController(text: tr(specs)),
        imageUrlCtrl = TextEditingController(text: tr(imageUrl)),
        linkCtrl = TextEditingController(text: tr(link)),
        brandCtrl = TextEditingController(text: tr(brand));

  final TextEditingController nameCtrl;
  final TextEditingController subCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController oldPriceCtrl;
  final TextEditingController badgeCtrl;
  final TextEditingController specsCtrl;
  String specsDetail;
  final TextEditingController imageUrlCtrl;
  final TextEditingController linkCtrl;
  final TextEditingController brandCtrl;

  void dispose() {
    nameCtrl.dispose();
    subCtrl.dispose();
    priceCtrl.dispose();
    oldPriceCtrl.dispose();
    badgeCtrl.dispose();
    specsCtrl.dispose();
    imageUrlCtrl.dispose();
    linkCtrl.dispose();
    brandCtrl.dispose();
  }

  Map<String, String> toJson() => {
        'name': nameCtrl.text.trim(),
        'sub': subCtrl.text.trim(),
        'price': priceCtrl.text.trim(),
        'oldPrice': oldPriceCtrl.text.trim(),
        'badge': badgeCtrl.text.trim(),
        'specs': specsCtrl.text.trim(),
        'specsDetail': specsDetail,
        'imageUrl': imageUrlCtrl.text.trim(),
        'link': linkCtrl.text.trim(),
        'brand': brandCtrl.text.trim(),
      };
}

class _ProductsSubTabState extends State<_ProductsSubTab> {
  bool _loading = false;
  bool _saving = false;
  final List<_ProductItem> _items = [];

  static const _defaults = [
    (
      name: 'ZKTeco LX35',
      sub: 'Máy chấm công vân tay WiFi',
      price: '1.500.000 d',
      oldPrice: '1.700.000 d',
      badge: 'Giảm 12%',
      specs: 'Vân tay – WiFi – 500 users',
      imageUrl:
          'https://maychamcong24h.vn/wp-content/uploads/2024/12/May-cham-cong-Wifi-LX35.jpg',
      link: 'https://maychamcong24h.vn/may-cham-cong-van-tay-wifi-zkteco-lx35/',
      brand: 'ZKTeco'
    ),
    (
      name: 'ZKTeco SenseFace 2A',
      sub: 'Nhận diện khuôn mặt',
      price: '2.530.000 d',
      oldPrice: '',
      badge: '',
      specs: 'Khuôn mặt – Vân tay – Thẻ – WiFi',
      imageUrl:
          'https://maychamcong24h.vn/wp-content/uploads/2024/11/may-cham-cong-khuon-mat-zkteco-senseface-2a-10.jpg',
      link:
          'https://maychamcong24h.vn/may-cham-cong-khuon-mat-zkteco-senseface-2a/',
      brand: 'ZKTeco'
    ),
    (
      name: 'Ronald Jack 8300Pro',
      sub: 'Máy chấm công vân tay ADMS',
      price: '2.300.000 d',
      oldPrice: '2.500.000 d',
      badge: 'Giảm 8%',
      specs: 'Vân tay – Thẻ – TCP/IP – ADMS',
      imageUrl:
          'https://maychamcong24h.vn/wp-content/uploads/2024/10/36628_ronald_jack_ua300_ha1.jpg',
      link:
          'https://maychamcong24h.vn/may-cham-cong-van-tay-ronald-jack-8300pro/',
      brand: 'Ronald Jack'
    ),
    (
      name: 'ZKTeco MB10VL',
      sub: 'Nhận diện khuôn mặt ADMS',
      price: '2.100.000 d',
      oldPrice: '2.500.000 d',
      badge: 'Giảm 16%',
      specs: 'Khuôn mặt – Vân tay – Thẻ – ADMS',
      imageUrl:
          'https://maychamcong24h.vn/wp-content/uploads/2024/11/May-cham-cong-khuon-mat-Zkteco-MB10VL.jpg',
      link: 'https://maychamcong24h.vn/may-cham-cong-khuon-mat-zkteco-mb10vl/',
      brand: 'ZKTeco'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getAllAppSettings();
      if (!mounted) return;
      final list = <_ProductItem>[];
      if (res['isSuccess'] == true) {
        final settings = List<Map<String, dynamic>>.from(res['data'] ?? []);
        final entry = settings.firstWhere((s) => s['key'] == 'landing_products',
            orElse: () => {});
        final raw = entry['value']?.toString() ?? '';
        if (raw.isNotEmpty) {
          try {
            final arr = jsonDecode(raw) as List;
            for (final e in arr) {
              if (e is Map) {
                list.add(_ProductItem(
                  name: e['name']?.toString() ?? '',
                  sub: e['sub']?.toString() ?? '',
                  price: e['price']?.toString() ?? '',
                  oldPrice: e['oldPrice']?.toString() ?? '',
                  badge: e['badge']?.toString() ?? '',
                  specs: e['specs']?.toString() ?? '',
                  specsDetail: e['specsDetail']?.toString() ?? '',
                  imageUrl: e['imageUrl']?.toString() ?? '',
                  link: e['link']?.toString() ?? '',
                  brand: e['brand']?.toString() ?? '',
                ));
              }
            }
          } catch (_) {}
        }
      }
      // Fallback to defaults if nothing saved yet
      if (list.isEmpty) {
        for (final d in _defaults) {
          list.add(_ProductItem(
              name: d.name,
              sub: d.sub,
              price: d.price,
              oldPrice: d.oldPrice,
              badge: d.badge,
              specs: d.specs,
              imageUrl: d.imageUrl,
              link: d.link,
              brand: d.brand));
        }
      }
      _items.clear();
      _items.addAll(list);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final json = jsonEncode(_items.map((i) => i.toJson()).toList());
      final res = await widget.api.updateAppSettingsBatch([
        {'key': 'landing_products', 'value': json},
      ]);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        AdminHelpers.showSuccess(context, 'Đã lưu danh sách sản phẩm!');
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      if (mounted) AdminHelpers.showError(context, 'Lỗi: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _addProduct() {
    setState(() => _items.add(_ProductItem()));
  }

  void _removeProduct(int idx) {
    setState(() {
      _items[idx].dispose();
      _items.removeAt(idx);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.devices_rounded,
                  size: 18, color: Color(0xFF0C56D0)),
              const SizedBox(width: 8),
              Text(tr('Danh sách máy chấm công'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              TextButton.icon(
                onPressed: context.systemAdminCanEdit ? _addProduct : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(tr('Thêm máy')),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _items.length,
            itemBuilder: (_, idx) => _buildProductCard(idx),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (context.systemAdminCanEdit && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(tr(_saving ? 'Đang lưu...' : 'Lưu danh sách sản phẩm')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(int idx) {
    final p = _items[idx];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFFEBF2FF),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(tr('Sản phẩm ${idx + 1}'),
                  style: const TextStyle(
                      color: Color(0xFF0C56D0),
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ),
            const Spacer(),
            IconButton(
              onPressed:
                  context.systemAdminCanEdit ? () => _removeProduct(idx) : null,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red, size: 20),
              tooltip: tr('Xóa sản phẩm'),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 12),
          // Row 1: Tên, Thương hiệu
          Row(children: [
            Expanded(
                flex: 3,
                child: _tf(p.nameCtrl, 'Tên sản phẩm', hint: 'ZKTeco LX35')),
            const SizedBox(width: 10),
            Expanded(
                flex: 2,
                child: _tf(p.brandCtrl, 'Thương hiệu', hint: 'ZKTeco')),
          ]),
          const SizedBox(height: 10),
          _tf(p.subCtrl, 'Mô tả ngắn', hint: 'Máy chấm công vân tay WiFi'),
          const SizedBox(height: 10),
          // Row 2: Giá, Giá gốc, Nhãn giảm
          Row(children: [
            Expanded(child: _tf(p.priceCtrl, 'Giá bán', hint: '1.500.000 d')),
            const SizedBox(width: 10),
            Expanded(
                child: _tf(p.oldPriceCtrl, 'Giá gốc (nếu có)',
                    hint: '1.700.000 d')),
            const SizedBox(width: 10),
            Expanded(
                child: _tf(p.badgeCtrl, 'Nhãn giảm giá', hint: 'Giảm 12%')),
          ]),
          const SizedBox(height: 10),
          _tf(p.specsCtrl, 'Thông số tóm tắt',
              hint: 'Vân tay – WiFi – 500 users'),
          const SizedBox(height: 10),
          _buildSpecsPreviewButton(p),
          const SizedBox(height: 10),
          _tf(p.imageUrlCtrl, 'URL ảnh sản phẩm',
              hint: 'https://...', icon: Icons.image_rounded),
          const SizedBox(height: 10),
          _tf(p.linkCtrl, 'Link xem chi tiết',
              hint: 'https://maychamcong24h.vn/...', icon: Icons.link_rounded),
        ]),
      ),
    );
  }

  Widget _buildSpecsPreviewButton(_ProductItem p) {
    final preview = _deltaToPreview(p.specsDetail);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Thông số kỹ thuật chi tiết'),
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _openSpecsEditor(p),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFF9FAFB),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr(preview.isEmpty
                        ? 'Chưa có thông số chi tiết — nhấn để soạn thảo'
                        : preview),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: preview.isEmpty
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF374151),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.edit_note_rounded,
                    size: 20, color: Color(0xFF6B7280)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openSpecsEditor(_ProductItem p) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _SpecsEditorDialog(initialDelta: p.specsDetail),
      ),
    );
    if (result != null && mounted) {
      setState(() => p.specsDetail = result);
    }
  }

  static String _deltaToPreview(String raw) {
    if (raw.isEmpty) return '';
    try {
      final list = jsonDecode(raw) as List;
      final sb = StringBuffer();
      for (final op in list) {
        if (op is Map && op['insert'] is String) sb.write(op['insert']);
      }
      return sb.toString().trim();
    } catch (_) {
      return raw;
    }
  }

  Widget _tf(TextEditingController ctrl, String label,
      {String? hint, IconData? icon}) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: tr(label),
        hintText: trN(hint),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
      ),
    );
  }
}

class _DownloadItem {
  _DownloadItem({
    String title = '',
    String desc = '',
    String version = '',
    String badge = '',
    String platform = '',
    String url = '',
  })  : titleCtrl = TextEditingController(text: tr(title)),
        descCtrl = TextEditingController(text: tr(desc)),
        versionCtrl = TextEditingController(text: tr(version)),
        badgeCtrl = TextEditingController(text: tr(badge)),
        platformCtrl = TextEditingController(text: tr(platform)),
        urlCtrl = TextEditingController(text: tr(url));

  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final TextEditingController versionCtrl;
  final TextEditingController badgeCtrl;
  final TextEditingController platformCtrl;
  final TextEditingController urlCtrl;

  void dispose() {
    titleCtrl.dispose();
    descCtrl.dispose();
    versionCtrl.dispose();
    badgeCtrl.dispose();
    platformCtrl.dispose();
    urlCtrl.dispose();
  }

  Map<String, String> toJson() => {
        'title': titleCtrl.text.trim(),
        'desc': descCtrl.text.trim(),
        'version': versionCtrl.text.trim(),
        'badge': badgeCtrl.text.trim(),
        'platform': platformCtrl.text.trim(),
        'url': urlCtrl.text.trim(),
      };
}

class _DownloadsSubTab extends StatefulWidget {
  const _DownloadsSubTab({required this.api});
  final ApiService api;

  @override
  State<_DownloadsSubTab> createState() => _DownloadsSubTabState();
}

class _DownloadsSubTabState extends State<_DownloadsSubTab> {
  bool _loading = false;
  bool _saving = false;
  final List<_DownloadItem> _items = [];

  static const _defaults = [
    (
      title: 'APK Android mới nhất',
      desc: 'Cài thủ công cho thiết bị Android nội bộ',
      version: 'v1.0',
      badge: 'APK',
      platform: 'android',
      url: 'https://sboxhrm.com/#/register'
    ),
    (
      title: 'Driver USB ZKTeco',
      desc: 'Driver kết nối máy chấm công với máy tính Windows',
      version: 'Windows',
      badge: 'Driver',
      platform: 'windows',
      url: 'https://sboxhrm.com/#/contact'
    ),
    (
      title: 'Bộ cài công cụ đồng bộ',
      desc: 'Tiện ích hỗ trợ cấu hình và kiểm tra kết nối thiết bị',
      version: 'v2.1',
      badge: 'Tool',
      platform: 'desktop',
      url: 'https://sboxhrm.com/#/contact'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getAllAppSettings();
      if (!mounted) return;
      final list = <_DownloadItem>[];
      if (res['isSuccess'] == true) {
        final settings = List<Map<String, dynamic>>.from(res['data'] ?? []);
        final entry = settings.firstWhere(
            (s) => s['key'] == 'landing_downloads_json',
            orElse: () => {});
        final raw = entry['value']?.toString() ?? '';
        if (raw.isNotEmpty) {
          try {
            final arr = jsonDecode(raw) as List;
            for (final e in arr) {
              if (e is Map) {
                list.add(_DownloadItem(
                  title: e['title']?.toString() ?? '',
                  desc: e['desc']?.toString() ?? '',
                  version: e['version']?.toString() ?? '',
                  badge: e['badge']?.toString() ?? '',
                  platform: e['platform']?.toString() ?? '',
                  url: e['url']?.toString() ?? '',
                ));
              }
            }
          } catch (_) {}
        }
      }
      if (list.isEmpty) {
        for (final d in _defaults) {
          list.add(_DownloadItem(
            title: d.title,
            desc: d.desc,
            version: d.version,
            badge: d.badge,
            platform: d.platform,
            url: d.url,
          ));
        }
      }
      _items
        ..clear()
        ..addAll(list);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final json = jsonEncode(_items
          .map((i) => i.toJson())
          .where((i) =>
              (i['title'] ?? '').isNotEmpty && (i['url'] ?? '').isNotEmpty)
          .toList());
      final res = await widget.api.updateAppSettingsBatch([
        {'key': 'landing_downloads_json', 'value': json},
      ]);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        AdminHelpers.showSuccess(context, 'Đã lưu danh sách tải về!');
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      if (mounted) AdminHelpers.showError(context, 'Lỗi: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _addItem() => setState(() => _items.add(_DownloadItem()));

  void _removeItem(int idx) {
    setState(() {
      _items[idx].dispose();
      _items.removeAt(idx);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.download_rounded,
                  size: 18, color: Color(0xFF0C56D0)),
              const SizedBox(width: 8),
              Text(tr('Danh sách file tải về'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              TextButton.icon(
                onPressed: context.systemAdminCanEdit ? _addItem : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(tr('Thêm file')),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _items.length,
            itemBuilder: (_, idx) => _buildCard(idx),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (context.systemAdminCanEdit && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(tr(_saving ? 'Đang lưu...' : 'Lưu danh sách tải về')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(int idx) {
    final item = _items[idx];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFFEBF2FF),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(tr('File ${idx + 1}'),
                  style: const TextStyle(
                      color: Color(0xFF0C56D0),
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ),
            const Spacer(),
            IconButton(
              onPressed: context.systemAdminCanEdit ? () => _removeItem(idx) : null,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red, size: 20),
              tooltip: tr('Xóa file'),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                flex: 3,
                child: _tf(item.titleCtrl, 'Tên hiển thị',
                    hint: 'APK Android mới nhất')),
            const SizedBox(width: 10),
            Expanded(
                flex: 2,
                child: _tf(item.platformCtrl, 'Nền tảng',
                    hint: 'android/windows/ios/driver')),
          ]),
          const SizedBox(height: 10),
          _tf(item.descCtrl, 'Mô tả ngắn',
              hint: 'Cài thủ công cho thiết bị Android nội bộ'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _tf(item.versionCtrl, 'Phiên bản', hint: 'v2.1.0')),
            const SizedBox(width: 10),
            Expanded(
                child:
                    _tf(item.badgeCtrl, 'Nhãn', hint: 'APK / Driver / Beta')),
          ]),
          const SizedBox(height: 10),
          _tf(item.urlCtrl, 'URL tải về',
              hint: 'https://...', icon: Icons.link_rounded),
        ]),
      ),
    );
  }

  Widget _tf(TextEditingController ctrl, String label,
      {String? hint, IconData? icon}) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: tr(label),
        hintText: trN(hint),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
      ),
    );
  }
}

// -------------------------------------------------------
// Sub-tab 8: FAQ trang chủ
// -------------------------------------------------------
class _FaqItem {
  _FaqItem(String q, String a)
      : qCtrl = TextEditingController(text: tr(q)),
        aCtrl = TextEditingController(text: tr(a));
  final TextEditingController qCtrl;
  final TextEditingController aCtrl;
}

class _FaqSubTab extends StatefulWidget {
  const _FaqSubTab({required this.api});
  final ApiService api;

  @override
  State<_FaqSubTab> createState() => _FaqSubTabState();
}

class _FaqSubTabState extends State<_FaqSubTab> {
  bool _loading = false;
  bool _saving = false;
  List<_FaqItem> _items = [];

  static const _defaults = [
    (
      'SBOX HRM chạy trên nền tảng nào?',
      'Đầy đủ Desktop/Web, Android (Google Play) và iOS. Dữ liệu đồng bộ realtime giữa các nền tảng.'
    ),
    (
      'SBOX HRM gồm những nghiệp vụ nào?',
      'Chấm công ZKTeco, ca làm, bảng lương, công tác phí, thu chi, giao việc & tiến độ, KPI & sản lượng, truyền thông nội bộ, góp ý/khiếu nại và hơn 30 tính năng HR.'
    ),
    (
      'Có hỗ trợ máy chấm công ZKTeco không?',
      'Có. Đồng bộ qua ADMS/PUSH (cổng 7070), quản lý nhân viên, vân tay và khuôn mặt từ phần mềm.'
    ),
    (
      'Có dùng thử miễn phí không?',
      'Có. Đăng ký tại sboxhrm.com hoặc tải app trên Google Play / liên hệ nhận bản iOS.'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.qCtrl.dispose();
      item.aCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getAllAppSettings();
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final list = List<Map<String, dynamic>>.from(res['data'] ?? []);
        final entry = list.firstWhere(
            (s) => s['key'] == 'landing_faq_json',
            orElse: () => {});
        final raw = entry['value']?.toString() ?? '';
        if (raw.isNotEmpty) {
          final arr = jsonDecode(raw) as List;
          _items = arr
              .map((e) => _FaqItem(
                    (e['q'] ?? e['question'] ?? '').toString(),
                    (e['a'] ?? e['answer'] ?? '').toString(),
                  ))
              .toList();
        }
      }
    } catch (_) {}
    if (_items.isEmpty) {
      _items = _defaults.map((e) => _FaqItem(e.$1, e.$2)).toList();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final json = jsonEncode(_items
          .where((i) => i.qCtrl.text.trim().isNotEmpty)
          .map((i) => {
                'q': i.qCtrl.text.trim(),
                'a': i.aCtrl.text.trim(),
              })
          .toList());
      final res = await widget.api.updateAppSettingsBatch([
        {'key': 'landing_faq_json', 'value': json}
      ]);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        AdminHelpers.showSuccess(context, 'Đã lưu FAQ trang chủ!');
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      if (mounted) AdminHelpers.showError(context, 'Lỗi: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _addItem() => setState(() => _items.add(_FaqItem('', '')));
  void _removeItem(int idx) => setState(() {
        _items[idx].qCtrl.dispose();
        _items[idx].aCtrl.dispose();
        _items.removeAt(idx);
      });

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(tr('Câu hỏi thường gặp (trang chủ)'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              FilledButton.icon(
                onPressed: context.systemAdminCanEdit ? _addItem : null,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(tr('Thêm')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _items.length,
            onReorder: (from, to) {
              setState(() {
                final item = _items.removeAt(from);
                _items.insert(to > from ? to - 1 : to, item);
              });
            },
            itemBuilder: (_, idx) {
              final item = _items[idx];
              return Card(
                key: ValueKey(idx),
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 14, right: 8),
                        child: Icon(Icons.drag_handle_rounded,
                            color: Colors.grey, size: 20),
                      ),
                      Expanded(
                        child: Column(children: [
                          TextField(
                            controller: item.qCtrl,
                            decoration: InputDecoration(
                              labelText: tr('Câu hỏi'),
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: item.aCtrl,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: tr('Câu trả lời'),
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ]),
                      ),
                      IconButton(
                        onPressed: context.systemAdminCanEdit
                            ? () => _removeItem(idx)
                            : null,
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.red),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (context.systemAdminCanEdit && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(tr(_saving ? 'Đang lưu...' : 'Lưu FAQ')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------
// Sub-tab 9: SEO Google
// -------------------------------------------------------
class _SeoGoogleSubTab extends StatefulWidget {
  const _SeoGoogleSubTab({required this.api});
  final ApiService api;

  @override
  State<_SeoGoogleSubTab> createState() => _SeoGoogleSubTabState();
}

class _SeoGoogleSubTabState extends State<_SeoGoogleSubTab> {
  bool _loading = false;
  bool _saving = false;

  final _fields = <String, TextEditingController>{
    'seo_meta_title': TextEditingController(),
    'seo_meta_description': TextEditingController(),
    'seo_meta_keywords': TextEditingController(),
    'seo_og_title': TextEditingController(),
    'seo_og_description': TextEditingController(),
    'seo_og_image': TextEditingController(),
    'seo_canonical_url': TextEditingController(),
    'google_site_verification': TextEditingController(),
    'google_tag_id': TextEditingController(),
  };

  static const _labels = {
    'seo_meta_title': 'Meta title (thẻ <title>)',
    'seo_meta_description': 'Meta description',
    'seo_meta_keywords': 'Meta keywords',
    'seo_og_title': 'Open Graph / Twitter title',
    'seo_og_description': 'Open Graph / Twitter description',
    'seo_og_image': 'Open Graph image URL',
    'seo_canonical_url': 'Canonical URL (vd: https://sboxhrm.com/)',
    'google_site_verification': 'Google Search Console – mã xác minh',
    'google_tag_id': 'Google Analytics / Ads ID (G-... hoặc AW-...)',
  };

  static const _multiline = {
    'seo_meta_description',
    'seo_og_description',
  };

  static const _hints = {
    'seo_meta_title':
        'SBOX HRM – Phần mềm quản lý nhân sự, chấm công khuôn mặt & bảng lương',
    'seo_meta_description':
        'SBOX HRM – Phần mềm quản lý nhân sự cho doanh nghiệp Việt Nam...',
    'google_site_verification': 'Chuỗi content trong thẻ google-site-verification',
    'google_tag_id': 'G-XXXXXXXX hoặc AW-XXXXXXXX',
    'seo_og_image': 'https://sboxhrm.com/images/landing/screenshot-01.jpg',
    'seo_canonical_url': 'https://sboxhrm.com/',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getAllAppSettings();
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final list = List<Map<String, dynamic>>.from(res['data'] ?? []);
        for (final key in _fields.keys) {
          final entry =
              list.firstWhere((s) => s['key'] == key, orElse: () => {});
          _fields[key]!.text = entry['value']?.toString() ?? '';
        }
      }
    } catch (e) {
      debugPrint('SEO load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final batch = _fields.entries
          .map((e) => {'key': e.key, 'value': e.value.text.trim()})
          .toList();
      final res = await widget.api.updateAppSettingsBatch(batch);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        AdminHelpers.showSuccess(context, 'Đã lưu thiết lập SEO Google!');
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      if (mounted) AdminHelpers.showError(context, 'Lỗi: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hdr('Meta trang chủ', Icons.search_rounded),
          const SizedBox(height: 4),
          Text(tr('Áp dụng cho trang chủ SEO (home.html). Để trống sẽ giữ nội dung mặc định trên trang.'),
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
          const SizedBox(height: 16),
          ...[
            'seo_meta_title',
            'seo_meta_description',
            'seo_meta_keywords',
            'seo_canonical_url',
          ].map(_field),
          const Divider(height: 32),
          _hdr('Open Graph / chia sẻ mạng xã hội', Icons.share_rounded),
          const SizedBox(height: 16),
          ...[
            'seo_og_title',
            'seo_og_description',
            'seo_og_image',
          ].map(_field),
          const Divider(height: 32),
          _hdr('Google Search Console & Analytics', Icons.analytics_rounded),
          const SizedBox(height: 4),
          Text(tr('Mã xác minh Search Console và Measurement ID (GA4 / Google Ads). Hiển thị công khai trên trang chủ.'),
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
          const SizedBox(height: 16),
          ...[
            'google_site_verification',
            'google_tag_id',
          ].map(_field),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (context.systemAdminCanEdit && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(tr(_saving ? 'Đang lưu...' : 'Lưu thiết lập SEO')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hdr(String title, IconData icon) {
    return Row(children: [
      Icon(icon, color: AdminHelpers.primary, size: 20),
      const SizedBox(width: 8),
      Text(tr(title),
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Color(0xFF111827))),
    ]);
  }

  Widget _field(String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _fields[key],
        maxLines: _multiline.contains(key) ? 3 : 1,
        decoration: InputDecoration(
          labelText: tr(_labels[key] ?? key),
          hintText: trN(_hints[key]),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
}

// --- Specs Editor Dialog – controller hoàn toàn thuộc về Dialog State --------
class _SpecsEditorDialog extends StatefulWidget {
  const _SpecsEditorDialog({required this.initialDelta});
  final String initialDelta;

  @override
  State<_SpecsEditorDialog> createState() => _SpecsEditorDialogState();
}

class _SpecsEditorDialogState extends State<_SpecsEditorDialog> {
  late final quill.QuillController _ctrl;
  late final TextEditingController _plainTextCtrl;
  late final FocusNode _focusNode;
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    _plainTextCtrl =
        TextEditingController(text: tr(_deltaToPlainText(widget.initialDelta)));
    _focusNode = FocusNode();
    _scrollCtrl = ScrollController();
    _ctrl = _initQuill(widget.initialDelta);
  }

  static quill.QuillController _initQuill(String raw) {
    if (raw.isEmpty) return quill.QuillController.basic();
    try {
      final list = jsonDecode(raw) as List;
      return quill.QuillController(
        document: quill.Document.fromJson(list),
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      return quill.QuillController.basic();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _plainTextCtrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  static String _deltaToPlainText(String raw) {
    if (raw.isEmpty) return '';
    try {
      final list = jsonDecode(raw) as List;
      final buffer = StringBuffer();
      for (final op in list) {
        if (op is Map && op['insert'] is String) {
          buffer.write(op['insert'] as String);
        }
      }
      final text = buffer.toString();
      return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
    } catch (_) {
      return raw;
    }
  }

  static String _plainTextToDelta(String text) {
    final normalized = text.replaceAll('\r\n', '\n').trimRight();
    if (normalized.isEmpty) return '';
    return jsonEncode([
      {'insert': '$normalized\n'}
    ]);
  }

  String _getDelta() {
    if (kIsWeb) return _plainTextToDelta(_plainTextCtrl.text);
    return jsonEncode(_ctrl.document.toDelta().toJson());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF111827),
        title: Text(tr('Thông số kỹ thuật chi tiết'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _getDelta()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: Text(tr('Xong')),
              ),
            ),
          ),
        ],
      ),
      body: kIsWeb ? _buildWebPlainTextEditor() : _buildQuillEditor(),
    );
  }

  Widget _buildWebPlainTextEditor() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFEEF4FF),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(tr('Trình duyệt web đang dùng chế độ nhập văn bản ổn định để tránh lỗi màn hình xám.'),
            style: TextStyle(
                fontSize: 12,
                color: Color(0xFF1E40AF),
                fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _plainTextCtrl,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Color(0xFF1F2937),
                    ),
                    decoration: InputDecoration(
                      hintText: tr('Nhập thông số kỹ thuật đầy đủ...'),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuillEditor() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: quill.QuillSimpleToolbar(
            controller: _ctrl,
            config: const quill.QuillSimpleToolbarConfig(
              multiRowsDisplay: true,
              showDividers: true,
              showFontFamily: false,
              showFontSize: false,
              showBoldButton: true,
              showItalicButton: true,
              showUnderLineButton: true,
              showStrikeThrough: false,
              showColorButton: true,
              showBackgroundColorButton: false,
              showClearFormat: true,
              showAlignmentButtons: true,
              showLeftAlignment: true,
              showCenterAlignment: true,
              showRightAlignment: true,
              showJustifyAlignment: false,
              showHeaderStyle: true,
              showListNumbers: true,
              showListBullets: true,
              showListCheck: false,
              showCodeBlock: false,
              showQuote: false,
              showIndent: true,
              showLink: true,
              showUndo: true,
              showRedo: true,
              showDirection: false,
              showSearchButton: false,
              showSubscript: false,
              showSuperscript: false,
              showSmallButton: false,
              showInlineCode: false,
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 420),
                    padding: const EdgeInsets.all(2),
                    child: quill.QuillEditor(
                      controller: _ctrl,
                      scrollController: _scrollCtrl,
                      focusNode: _focusNode,
                      config: const quill.QuillEditorConfig(
                        placeholder: 'Nhập thông số kỹ thuật đầy đủ...',
                        padding: EdgeInsets.all(16),
                        autoFocus: false,
                        expands: false,
                        scrollable: false,
                        customStyles: quill.DefaultStyles(
                          paragraph: quill.DefaultTextBlockStyle(
                            TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: Color(0xFF1F2937),
                            ),
                            quill.HorizontalSpacing(0, 0),
                            quill.VerticalSpacing(4, 4),
                            quill.VerticalSpacing(0, 0),
                            null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
