import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart' as file_saver;
import '../utils/pos_kiot_time_range.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hkd_book_preview_panel.dart';
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
  String _selectedBook = 'S2a';
  bool _loading = true;
  bool _saving = false;
  bool _exporting = false;
  bool _previewLoading = false;
  String? _previewError;
  Map<String, dynamic>? _preview;
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
        _selectedBook = _defaultBook(_taxGroup);
      });
      await _loadPreview();
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

  String _defaultBook(int group) => switch (group) {
        1 => 'S1a',
        3 => 'S2b',
        _ => 'S2a',
      };

  List<({String id, String title, String subtitle})> get _visibleBooks {
    return [
      if (_taxGroup == 1)
        (
          id: 'S1a',
          title: 'S1a-HKD',
          subtitle: 'Sổ doanh thu',
        ),
      if (_taxGroup == 2)
        (
          id: 'S2a',
          title: 'S2a-HKD',
          subtitle: 'Doanh thu theo %',
        ),
      if (_taxGroup == 3) ...[
        (
          id: 'S2b',
          title: 'S2b-HKD',
          subtitle: 'Doanh thu · GTGT %',
        ),
        (
          id: 'S2c',
          title: 'S2c-HKD',
          subtitle: 'Doanh thu & chi phí',
        ),
        (
          id: 'S2d',
          title: 'S2d-HKD',
          subtitle: 'Chi tiết hàng hóa',
        ),
      ],
      (
        id: 'S2e',
        title: 'S2e-HKD',
        subtitle: 'Sổ chi tiết tiền',
      ),
    ];
  }

  Future<void> _loadPreview() async {
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      final res = await _api.getHkdBookPreview(
        book: _selectedBook,
        from: _time.from,
        to: _time.to,
      );
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] is Map) {
        setState(() {
          _preview = Map<String, dynamic>.from(res['data'] as Map);
          _previewLoading = false;
        });
      } else {
        setState(() {
          _preview = null;
          _previewLoading = false;
          _previewError = '${res['message'] ?? 'Không tải được sổ'}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _previewLoading = false;
        _previewError = '$e';
      });
    }
  }

  Future<void> _selectBook(String book) async {
    if (_selectedBook == book) {
      await _loadPreview();
      return;
    }
    setState(() => _selectedBook = book);
    await _loadPreview();
  }

  Future<void> _exportSelected() async {
    switch (_selectedBook) {
      case 'S2c':
        await _exportIncomeExpense();
        return;
      case 'S2d':
        await _exportInventory();
        return;
      case 'S2e':
        await _exportCash();
        return;
      default:
        await _exportRevenue(_selectedBook);
    }
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

  String get _groupShort => switch (_taxGroup) {
        1 => 'Dưới 1 tỷ/năm',
        3 => 'Trên 3 tỷ/năm',
        _ => 'Từ 1–3 tỷ/năm',
      };

  String get _groupHint {
    switch (_taxGroup) {
      case 1:
        return 'Dưới 1 tỷ/năm: miễn GTGT/TNCN theo tỷ lệ → xuất S1a-HKD';
      case 3:
        return 'Trên 3 tỷ/năm: GTGT % doanh thu + TNCN theo thu nhập → S2b, S2c, S2d, S2e';
      default:
        return 'Từ 1–3 tỷ/năm: GTGT + TNCN theo % doanh thu → xuất S2a + S2e';
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
            : SafeArea(
                top: !HrmPageChrome.usesMainLayoutAppBar,
                child: ListView(
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
                    tr('Theo Thông tư 152/2025/TT-BTC. Xem chi tiết trên màn hình; xuất Excel khi cần nộp cơ quan thuế.'),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF71717A)),
                  ),
                  const SizedBox(height: 16),
                  _buildPeriodCard(),
                  const SizedBox(height: 16),
                  _buildBookCard(canExport),
                  const SizedBox(height: 16),
                  _buildProfileCard(canEdit),
                  if (_exporting) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(
            tr('Hồ sơ hộ kinh doanh'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          subtitle: Text(
            tr(_groupShort),
            style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('Nhóm theo doanh thu năm'),
                  style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _taxGroup,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                DropdownMenuItem(value: 1, child: Text(tr('Dưới 1 tỷ — S1a (miễn GTGT/TNCN)'))),
                DropdownMenuItem(value: 2, child: Text(tr('Từ 1–3 tỷ — S2a (thuế % doanh thu)'))),
                DropdownMenuItem(value: 3, child: Text(tr('Trên 3 tỷ — S2b/S2c/S2d/S2e'))),
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
                        final ids = _visibleBooks.map((b) => b.id).toSet();
                        if (!ids.contains(_selectedBook)) {
                          _selectedBook = _defaultBook(v);
                        }
                      });
                      _loadPreview();
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
              tr('Kỳ dữ liệu'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 12),
            PosKiotTimeFilter(
              state: _time,
              onChanged: (v) {
                setState(() => _time = v);
                _loadPreview();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookCard(bool canExport) {
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
              tr('Sổ theo mẫu TT152'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Chọn sổ để xem bảng chi tiết ngay trên màn hình. Xuất Excel chỉ khi cần nộp.'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _visibleBooks.map((b) {
                final selected = _selectedBook == b.id;
                return FilterChip(
                  selected: selected,
                  label: Text(b.title),
                  tooltip: b.subtitle,
                  onSelected: (_) => _selectBook(b.id),
                  selectedColor: HrmPageChrome.primaryNavy.withValues(alpha: 0.12),
                  checkmarkColor: HrmPageChrome.primaryNavy,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            HkdBookPreviewPanel(
              preview: _preview,
              loading: _previewLoading,
              error: _previewError,
              accent: HrmPageChrome.primaryNavy,
              canExport: canExport,
              exporting: _exporting,
              onExport: _exportSelected,
              onRetry: _loadPreview,
            ),
          ],
        ),
      ),
    );
  }
}
