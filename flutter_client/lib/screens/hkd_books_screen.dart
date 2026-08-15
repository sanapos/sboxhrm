import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart' as file_saver;
import '../utils/pos_kiot_time_range.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/page_top_actions.dart';
import '../widgets/pos/pos_kiot_time_filter.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Sổ sách kế toán hộ kinh doanh (TT 152/2025) — S1a/S2a/S2b/S2c/S2d/S2e.
class HkdBooksScreen extends StatefulWidget {
  const HkdBooksScreen({super.key});

  @override
  State<HkdBooksScreen> createState() => _HkdBooksScreenState();
}

class _HkdBooksScreenState extends State<HkdBooksScreen> {
  final _api = ApiService();
  final _taxCodeCtrl = TextEditingController();
  final _businessNameCtrl = TextEditingController();
  final _industryCtrl = TextEditingController();
  final _vatCtrl = TextEditingController(text: '0');
  final _pitCtrl = TextEditingController(text: '0');

  PosKiotTimeFilterState _time = PosKiotTimeFilterState.thisMonth();
  int _taxGroup = 2;
  bool _loading = true;
  bool _saving = false;
  bool _exporting = false;
  List<String> _recommendedBooks = const ['S2a-HKD', 'S2e-HKD'];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _taxCodeCtrl.dispose();
    _businessNameCtrl.dispose();
    _industryCtrl.dispose();
    _vatCtrl.dispose();
    _pitCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getHkdSettings();
      if (!mounted) return;
      setState(() {
        _taxGroup = (data['taxGroup'] as num?)?.toInt() ?? 2;
        _taxCodeCtrl.text = data['taxCode']?.toString() ?? '';
        _businessNameCtrl.text = data['businessName']?.toString() ?? '';
        _industryCtrl.text = data['industry']?.toString() ?? '';
        _vatCtrl.text = _fmtNum(data['vatPercent']);
        _pitCtrl.text = _fmtNum(data['pitPercent']);
        final books = data['recommendedBooks'];
        if (books is List) {
          _recommendedBooks = books.map((e) => e.toString()).toList();
        }
      });
    } catch (e) {
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: '$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '0';
    if (v is num) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return v.toString();
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      final data = await _api.saveHkdSettings({
        'taxGroup': _taxGroup,
        'taxCode': _taxCodeCtrl.text.trim(),
        'businessName': _businessNameCtrl.text.trim(),
        'industry': _industryCtrl.text.trim(),
        'vatPercent': double.tryParse(_vatCtrl.text.replaceAll(',', '.')) ?? 0,
        'pitPercent': double.tryParse(_pitCtrl.text.replaceAll(',', '.')) ?? 0,
      });
      if (!mounted) return;
      final books = data['recommendedBooks'];
      setState(() {
        if (books is List) {
          _recommendedBooks = books.map((e) => e.toString()).toList();
        }
      });
      appNotification.showSuccess(
        title: 'Đã lưu',
        message: tr('Đã cập nhật hồ sơ hộ kinh doanh'),
      );
    } catch (e) {
      appNotification.showError(title: 'Lỗi lưu', message: '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportRevenue(String book) async {
    setState(() => _exporting = true);
    try {
      final res = await _api.exportHkdRevenueBookExcel(
        book: book,
        from: _time.from,
        to: _time.to,
      );
      if (res['isSuccess'] == true && res['data'] != null) {
        final bytes = Uint8List.fromList(List<int>.from(res['data']));
        final name =
            'SoDoanhThu_${book}-HKD_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
        await file_saver.saveFileBytes(
          bytes,
          name,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        appNotification.showSuccess(
          title: 'Đã xuất',
          message: tr('Đã tải $name'),
        );
      } else {
        appNotification.showError(
          title: 'Xuất thất bại',
          message: '${res['message'] ?? 'Không xuất được Excel'}',
        );
      }
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất', message: '$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCash() async {
    setState(() => _exporting = true);
    try {
      final res = await _api.exportHkdCashBookExcel(
        from: _time.from,
        to: _time.to,
      );
      if (res['isSuccess'] == true && res['data'] != null) {
        final bytes = Uint8List.fromList(List<int>.from(res['data']));
        final name =
            'SoChiTietTien_S2e-HKD_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
        await file_saver.saveFileBytes(
          bytes,
          name,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        appNotification.showSuccess(
          title: 'Đã xuất',
          message: tr('Đã tải $name'),
        );
      } else {
        appNotification.showError(
          title: 'Xuất thất bại',
          message: '${res['message'] ?? 'Không xuất được Excel'}',
        );
      }
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất', message: '$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportIncomeExpense() async {
    setState(() => _exporting = true);
    try {
      final res = await _api.exportHkdIncomeExpenseBookExcel(
        from: _time.from,
        to: _time.to,
      );
      if (res['isSuccess'] == true && res['data'] != null) {
        final bytes = Uint8List.fromList(List<int>.from(res['data']));
        final name =
            'SoDoanhThuChiPhi_S2c-HKD_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
        await file_saver.saveFileBytes(
          bytes,
          name,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        appNotification.showSuccess(
          title: 'Đã xuất',
          message: tr('Đã tải $name'),
        );
      } else {
        appNotification.showError(
          title: 'Xuất thất bại',
          message: '${res['message'] ?? 'Không xuất được Excel'}',
        );
      }
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất', message: '$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportInventory() async {
    setState(() => _exporting = true);
    try {
      final res = await _api.exportHkdInventoryBookExcel(
        from: _time.from,
        to: _time.to,
      );
      if (res['isSuccess'] == true && res['data'] != null) {
        final bytes = Uint8List.fromList(List<int>.from(res['data']));
        final name =
            'SoChiTietHangHoa_S2d-HKD_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
        await file_saver.saveFileBytes(
          bytes,
          name,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        appNotification.showSuccess(
          title: 'Đã xuất',
          message: tr('Đã tải $name'),
        );
      } else {
        appNotification.showError(
          title: 'Xuất thất bại',
          message: '${res['message'] ?? 'Không xuất được Excel'}',
        );
      }
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất', message: '$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String get _groupHint {
    switch (_taxGroup) {
      case 1:
        return 'Nhóm 1: không chịu GTGT/TNCN → xuất S1a-HKD';
      case 3:
        return 'Nhóm 3: GTGT % doanh thu + TNCN theo thu nhập → xuất S2b, S2c, S2d, S2e';
      default:
        return 'Nhóm 2: GTGT + TNCN theo % doanh thu → xuất S2a + S2e';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canExport = perm.canExport('HkdBooks') ||
        perm.canExport('PosSalesReport') ||
        perm.canExport('CashReport');
    final canEdit = perm.canEdit('HkdBooks');

    return RegisterPageTopActions(
      actions: [
        if (canEdit)
          HrmTopBarAction(
            icon: Icons.save_outlined,
            label: 'Lưu hồ sơ',
            primary: true,
            showLabel: true,
            onPressed: _saving || _loading ? null : _saveSettings,
          ),
      ],
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: _loading
            ? const LoadingWidget()
            : ListView(
                padding: EdgeInsets.all(isMobile ? 12 : 20),
                children: [
                  Text(
                    tr('Sổ sách kế toán hộ kinh doanh'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF18181B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('Theo Thông tư 152/2025/TT-BTC. Xuất Excel từ dữ liệu bán hàng & thu chi của cửa hàng.'),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF71717A)),
                  ),
                  const SizedBox(height: 16),
                  _buildProfileCard(canEdit),
                  const SizedBox(height: 16),
                  _buildPeriodCard(),
                  const SizedBox(height: 16),
                  _buildExportCard(canExport),
                  if (_exporting) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildProfileCard(bool canEdit) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Hồ sơ hộ kinh doanh'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Text(tr('Nhóm thuế'), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _taxGroup,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                DropdownMenuItem(value: 1, child: Text(tr('Nhóm 1 — miễn GTGT/TNCN (S1a)'))),
                DropdownMenuItem(value: 2, child: Text(tr('Nhóm 2 — % trên doanh thu (S2a)'))),
                DropdownMenuItem(value: 3, child: Text(tr('Nhóm 3 — TNCN theo thu nhập (S2b/S2c/S2d/S2e)'))),
              ],
              onChanged: canEdit
                  ? (v) {
                      if (v == null) return;
                      setState(() {
                        _taxGroup = v;
                        _recommendedBooks = switch (v) {
                          1 => ['S1a-HKD'],
                          3 => ['S2b-HKD', 'S2c-HKD', 'S2d-HKD', 'S2e-HKD'],
                          _ => ['S2a-HKD', 'S2e-HKD'],
                        };
                      });
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            Text(tr(_groupHint),
                style: const TextStyle(fontSize: 12, color: Color(0xFF52525B))),
            const SizedBox(height: 12),
            TextField(
              controller: _taxCodeCtrl,
              enabled: canEdit,
              decoration: InputDecoration(
                labelText: tr('Mã số thuế (MST)'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _businessNameCtrl,
              enabled: canEdit,
              decoration: InputDecoration(
                labelText: tr('Tên hộ kinh doanh'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _industryCtrl,
              enabled: canEdit,
              decoration: InputDecoration(
                labelText: tr('Ngành nghề (ghi trên sổ doanh thu)'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_taxGroup == 2 || _taxGroup == 3) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _vatCtrl,
                      enabled: canEdit,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: tr(_taxGroup == 3
                            ? 'Tỷ lệ % GTGT (S2b)'
                            : 'Tỷ lệ % GTGT'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _pitCtrl,
                      enabled: canEdit,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: tr(_taxGroup == 3
                            ? 'Tỷ lệ % TNCN (trên thu nhập)'
                            : 'Tỷ lệ % TNCN'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Text(tr('Sổ khuyến nghị:'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
                ..._recommendedBooks.map(
                  (b) => Chip(
                    label: Text(b, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Kỳ dữ liệu xuất sổ'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 12),
            PosKiotTimeFilter(
              state: _time,
              onChanged: (v) => setState(() => _time = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportCard(bool canExport) {
    final showS1a = _taxGroup == 1;
    final showS2a = _taxGroup == 2;
    final showGroup3 = _taxGroup == 3;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Xuất Excel theo mẫu TT152'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              tr(showGroup3
                  ? 'S2b từ đơn bán; S2c từ bán hàng + phiếu chi + phiếu nhập; S2d từ thẻ kho; S2e từ sổ thu chi.'
                  : 'Dữ liệu lấy từ đơn bán hoàn thành (S1a/S2a) và sổ thu chi đã hoàn tất (S2e).'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
            ),
            const SizedBox(height: 14),
            if (showS1a)
              _exportTile(
                title: 'S1a-HKD — Sổ doanh thu',
                subtitle: 'Nhóm 1: ngày · diễn giải · số tiền',
                enabled: canExport && !_exporting,
                onTap: () => _exportRevenue('S1a'),
              ),
            if (showS2a)
              _exportTile(
                title: 'S2a-HKD — Sổ doanh thu theo %',
                subtitle: 'Số CT · ngày · diễn giải · doanh thu · thuế ước tính',
                enabled: canExport && !_exporting,
                onTap: () => _exportRevenue('S2a'),
              ),
            if (showGroup3) ...[
              _exportTile(
                title: 'S2b-HKD — Sổ doanh thu (GTGT %)',
                subtitle: 'Doanh thu theo ngành · ước tính thuế GTGT',
                enabled: canExport && !_exporting,
                onTap: () => _exportRevenue('S2b'),
              ),
              _exportTile(
                title: 'S2c-HKD — Doanh thu & chi phí',
                subtitle: 'Bán hàng − phiếu chi − nhập hàng → thu nhập tính thuế',
                enabled: canExport && !_exporting,
                onTap: _exportIncomeExpense,
              ),
              _exportTile(
                title: 'S2d-HKD — Chi tiết hàng hóa',
                subtitle: 'Nhập · xuất · tồn theo thẻ kho từng SKU',
                enabled: canExport && !_exporting,
                onTap: _exportInventory,
              ),
            ],
            _exportTile(
              title: 'S2e-HKD — Sổ chi tiết tiền',
              subtitle: 'Thu / chi tiền mặt & chuyển khoản',
              enabled: canExport && !_exporting,
              onTap: _exportCash,
            ),
          ],
        ),
      ),
    );
  }

  Widget _exportTile({
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
        child: const Icon(Icons.table_view_outlined,
            color: HrmPageChrome.primaryNavy, size: 20),
      ),
      title: Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(tr(subtitle), style: const TextStyle(fontSize: 12)),
      trailing: FilledButton.icon(
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          backgroundColor: HrmPageChrome.primaryNavy,
        ),
        icon: const Icon(Icons.download, size: 16),
        label: Text(tr('Xuất')),
      ),
    );
  }
}
