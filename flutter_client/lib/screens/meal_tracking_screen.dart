import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../models/meal.dart';
import '../utils/responsive_helper.dart';
import '../utils/branch_filter_helper.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/hrm_collapsible_overview.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/page_top_actions.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class MealTrackingScreen extends StatefulWidget {
  const MealTrackingScreen({super.key});
  @override
  State<MealTrackingScreen> createState() => _MealTrackingScreenState();
}

class _MealTrackingScreenState extends State<MealTrackingScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabCtl;

  // Dashboard
  MealSummary? _mealSummary;
  DateTime _selectedDate = DateTime.now();

  // Sessions
  List<MealSession> _sessions = [];

  // Records
  List<MealRecord> _records = [];
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalRecords = 0;
  String _recordSearch = '';
  String _summarySearch = '';
  String _debtSearch = '';
  String? _filterSessionId;

  // Summary
  List<EmployeeMealSummary> _employeeSummaries = [];
  DateTime _summaryFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _summaryTo = DateTime.now();
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];

  // Menu
  List<MealMenu> _weeklyMenus = [];
  DateTime _menuWeekStart = _getMonday(DateTime.now());
  final GlobalKey _menuRepaintKey = GlobalKey();

  // Master dish list
  List<MealDish> _masterDishes = [];

  List<dynamic> _employees = [];

  // Debt
  List<MealDebtSummary> _debtSummaries = [];
  List<MealDebt> _debtHistory = [];
  String _debtPeriod = DateFormat('yyyy-MM').format(DateTime.now());
  bool _isLoadingDebt = false;

  // Common
  bool _isLoading = true;
  bool _showOverviewPanel = true;

  static DateTime _getMonday(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  static const _dayNames = [
    'Thứ 2',
    'Thứ 3',
    'Thứ 4',
    'Thứ 5',
    'Thứ 6',
    'Thứ 7',
    'CN',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 5, vsync: this);
    _tabCtl.addListener(() {
      if (!_tabCtl.indexIsChanging) {
        setState(() {});
        _loadCurrentTab();
      }
    });
    _loadSessions().then((_) {
      _loadMasterDishes();
      _loadEmployeeList();
      _loadCurrentTab();
    });
  }

  @override
  void dispose() {
    _tabCtl.dispose();
    super.dispose();
  }

  void _loadCurrentTab() {
    switch (_tabCtl.index) {
      case 0:
        _loadEstimate();
        break;
      case 1:
        _loadRecords();
        break;
      case 2:
        _loadEmployeeSummary();
        break;
      case 3:
        _loadWeeklyMenu();
        break;
      case 4:
        _loadDebtSummary();
        break;
    }
  }

  Future<void> _loadSessions() async {
    try {
      final res = await _apiService.getMealSessions();
      if (res['isSuccess'] == true) {
        final list = res['data'] as List? ?? [];
        _sessions = list
            .map((e) => MealSession.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Load sessions error: $e');
    }
  }

  Future<void> _loadMasterDishes() async {
    try {
      final res = await _apiService.getMealDishes();
      if (res['isSuccess'] == true) {
        final list = res['data'] as List? ?? [];
        _masterDishes = list
            .map((e) => MealDish.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Load dishes error: $e');
    }
  }

  Future<void> _loadEstimate() async {
    setState(() => _isLoading = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final res = await _apiService.getMealEstimate(date: dateStr);
      if (res['isSuccess'] == true && res['data'] != null) {
        _mealSummary =
            MealSummary.fromJson(res['data'] as Map<String, dynamic>);
      }
      // Also load today's menu for inline display
      final weekStart = _getMonday(_selectedDate);
      final menuRes = await _apiService.getWeeklyMealMenu(
        weekStartDate: DateFormat('yyyy-MM-dd').format(weekStart),
      );
      if (menuRes['isSuccess'] == true && menuRes['data'] != null) {
        final list = menuRes['data'] as List? ?? [];
        _weeklyMenus = list
            .map((e) => MealMenu.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Load estimate error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final res = await _apiService.getMealRecords(
        date: dateStr,
        mealSessionId: _filterSessionId,
        page: _currentPage,
      );
      if (res['isSuccess'] == true && res['data'] != null) {
        final data = res['data'] as Map<String, dynamic>;
        final items = data['items'] as List? ?? [];
        _records = items
            .map((e) => MealRecord.fromJson(e as Map<String, dynamic>))
            .toList();
        _totalPages = data['totalPages'] ?? 1;
        _totalRecords = data['totalCount'] ?? _records.length;
      }
    } catch (e) {
      debugPrint('Load records error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadEmployeeSummary() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getEmployeeMealSummary(
        fromDate: DateFormat('yyyy-MM-dd').format(_summaryFrom),
        toDate: DateFormat('yyyy-MM-dd').format(_summaryTo),
      );
      if (res['isSuccess'] == true && res['data'] != null) {
        final list = res['data'] as List? ?? [];
        _employeeSummaries = list
            .map((e) => EmployeeMealSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Load employee summary error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadWeeklyMenu() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getWeeklyMealMenu(
        weekStartDate: DateFormat('yyyy-MM-dd').format(_menuWeekStart),
      );
      if (res['isSuccess'] == true && res['data'] != null) {
        final list = res['data'] as List? ?? [];
        _weeklyMenus = list
            .map((e) => MealMenu.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Load weekly menu error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadDebtSummary() async {
    setState(() => _isLoadingDebt = true);
    try {
      final res = await _apiService.getMealDebtSummary(period: _debtPeriod);
      if (res['isSuccess'] == true && res['data'] != null) {
        final list = res['data'] as List? ?? [];
        _debtSummaries = list
            .map((e) => MealDebtSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Load debt summary error: $e');
    }
    if (mounted) setState(() => _isLoadingDebt = false);
  }

  Future<void> _loadDebtHistory(String employeeUserId) async {
    setState(() => _isLoadingDebt = true);
    try {
      final res = await _apiService.getMealDebtHistory(
        employeeUserId: employeeUserId,
        period: _debtPeriod,
      );
      if (res['isSuccess'] == true && res['data'] != null) {
        final list = res['data'] as List? ?? [];
        _debtHistory = list
            .map((e) => MealDebt.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Load debt history error: $e');
    }
    if (mounted) setState(() => _isLoadingDebt = false);
  }

  Future<void> _loadEmployeeList() async {
    try {
      _employees = await _apiService.getEmployeesForSelect(pageSize: 500);
    } catch (e) {
      debugPrint('Load employees error: $e');
    }
    try {
      final br = await _apiService.getBranchesForSelect();
      final bd = br['data'];
      if (bd is List && mounted) {
        setState(() => _branches =
            bd.map((b) => Map<String, dynamic>.from(b as Map)).toList());
      }
    } catch (_) {}
  }

  Future<void> _doBatchCharge() async {
    try {
      final res = await _apiService.batchChargeMeals(_debtPeriod);
      if (res['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(
          title: 'Tính tiền cơm',
          message: tr('Đã tính tiền cơm tháng $_debtPeriod thành công'),
        );
        _loadDebtSummary();
      } else {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message'] ?? 'Tính tiền thất bại',
        );
      }
    } catch (e) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: tr('Lỗi: $e'));
    }
  }

  void _showRecordPaymentDialog(MealDebtSummary debt) {
    final amountCtl = TextEditingController();
    final noteCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Thu tiền - ${debt.employeeName}')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Công nợ hiện tại: ${_formatCurrency(debt.balance)}'),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Số tiền thu *'),
                border: OutlineInputBorder(),
                prefixText: tr('₫ '),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtl,
              decoration: InputDecoration(
                labelText: tr('Ghi chú'),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtl.text.trim());
              if (amount == null || amount <= 0) return;
              Navigator.pop(ctx);
              try {
                final res = await _apiService.createMealDebt({
                  'employeeUserId': debt.employeeUserId,
                  'type': 1,
                  'amount': amount,
                  'date': DateTime.now().toIso8601String(),
                  'period': _debtPeriod,
                  'note': noteCtl.text.trim(),
                });
                if (res['isSuccess'] == true) {
                  NotificationOverlayManager().showSuccess(
                      title: 'Thu tiền',
                      message: tr('Đã ghi nhận thu ${_formatCurrency(amount)}'));
                  _loadDebtSummary();
                } else {
                  NotificationOverlayManager().showError(
                      title: 'Lỗi', message: res['message'] ?? 'Thất bại');
                }
              } catch (e) {
                NotificationOverlayManager()
                    .showError(title: 'Lỗi', message: tr('Lỗi: $e'));
              }
            },
            child: Text(tr('Thu tiền')),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double amount) {
    final fmt = NumberFormat('#,###', 'vi');
    return '${fmt.format(amount)}đ';
  }

  // ==================== SESSION MANAGEMENT ====================

  void _showCreateSessionDialog() {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    final priceCtl = TextEditingController();
    TimeOfDay startTime = const TimeOfDay(hour: 11, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 13, minute: 0);
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          Future<void> onSave() async {
            if (nameCtl.text.trim().isEmpty) return;
            final data = {
              'name': nameCtl.text.trim(),
              'description': descCtl.text.trim(),
              'startTime':
                  '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:00',
              'endTime':
                  '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00',
              'pricePerMeal': double.tryParse(priceCtl.text.trim()) ?? 0,
              'shiftTemplateIds': <String>[],
            };
            final res = await _apiService.createMealSession(data);
            if (ctx.mounted) Navigator.pop(ctx);
            if (res['isSuccess'] == true) {
              NotificationOverlayManager()
                  .showSuccess(title: 'Thành công', message: tr('Đã tạo buổi ăn'));
              _loadSessions();
            } else {
              NotificationOverlayManager().showError(
                  title: 'Lỗi', message: res['message'] ?? 'Lỗi tạo buổi ăn');
            }
          }

          final formBody = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(labelText: tr('Tên buổi ăn *')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtl,
                decoration: InputDecoration(labelText: tr('Mô tả')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Giá mỗi suất (đ)'),
                  prefixText: tr('₫ '),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(tr('Giờ bắt đầu')),
                trailing: Text(tr(startTime.format(ctx))),
                onTap: () async {
                  final t = await showTimePicker(
                      context: ctx, initialTime: startTime);
                  if (t != null) setDlgState(() => startTime = t);
                },
              ),
              ListTile(
                title: Text(tr('Giờ kết thúc')),
                trailing: Text(tr(endTime.format(ctx))),
                onTap: () async {
                  final t =
                      await showTimePicker(context: ctx, initialTime: endTime);
                  if (t != null) setDlgState(() => endTime = t);
                },
              ),
            ],
          );

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(tr('Thêm buổi ăn')),
                  leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton(
                          onPressed: onSave, child: Text(tr('Lưu'))),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16), child: formBody),
              ),
            );
          }

          return ScrollableAlertDialog(
            title: Text(tr('Thêm buổi ăn')),
            content: SingleChildScrollView(child: formBody),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Hủy'))),
              FilledButton(onPressed: onSave, child: Text(tr('Lưu'))),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteSessionDialog(MealSession session) {
    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Xóa buổi ăn')),
        content: Text(tr('Bạn có chắc muốn xóa "${session.name}"?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final res = await _apiService.deleteMealSession(session.id);
              if (ctx.mounted) Navigator.pop(ctx);
              if (res['isSuccess'] == true) {
                NotificationOverlayManager().showSuccess(
                    title: 'Thành công', message: tr('Đã xóa buổi ăn'));
                _loadSessions();
              } else {
                NotificationOverlayManager().showError(
                    title: 'Lỗi', message: res['message'] ?? 'Lỗi xóa buổi ăn');
              }
            },
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
  }

  // ==================== MENU MANAGEMENT ====================

  void _showCreateMenuDialog() {
    final noteCtl = TextEditingController();
    String? selectedSessionId =
        _sessions.isNotEmpty ? _sessions.first.id : null;
    DateTime menuDate = DateTime.now();
    final Set<String> selectedDishIds = {};
    final isMobile = Responsive.isMobile(context);
    String? filterCategory;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          Future<void> onSave() async {
            if (selectedSessionId == null) return;
            if (selectedDishIds.isEmpty) {
              NotificationOverlayManager().showError(
                  title: 'Lỗi', message: tr('Vui lòng chọn ít nhất 1 món'));
              return;
            }
            final items = selectedDishIds.toList().asMap().entries.map((entry) {
              final dish = _masterDishes.firstWhere((d) => d.id == entry.value);
              return {
                'dishName': dish.name,
                'category': dish.category ?? '',
                'description': '',
                'sortOrder': entry.key,
              };
            }).toList();
            final data = {
              'date': menuDate.toIso8601String(),
              'mealSessionId': selectedSessionId,
              'note': noteCtl.text.trim(),
              'items': items,
            };
            final res = await _apiService.createMealMenu(data);
            if (ctx.mounted) Navigator.pop(ctx);
            if (res['isSuccess'] == true) {
              NotificationOverlayManager()
                  .showSuccess(title: 'Thành công', message: tr('Đã tạo thực đơn'));
              _loadWeeklyMenu();
            } else {
              NotificationOverlayManager().showError(
                  title: 'Lỗi', message: res['message'] ?? 'Lỗi tạo thực đơn');
            }
          }

          // Group dishes by category
          final grouped = <String, List<MealDish>>{};
          for (final d in _masterDishes) {
            final cat = d.category?.isNotEmpty == true ? d.category! : 'Khác';
            grouped.putIfAbsent(cat, () => []).add(d);
          }
          final categories = _getDistinctCategories();

          // Filtered groups
          final filteredGrouped = filterCategory != null
              ? {filterCategory!: grouped[filterCategory] ?? []}
              : grouped;

          // Selected dishes list
          final selectedDishes = _masterDishes
              .where((d) => selectedDishIds.contains(d.id))
              .toList();

          final formBody = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedSessionId,
                decoration: InputDecoration(
                    labelText: tr('Buổi ăn *'), border: OutlineInputBorder()),
                items: _sessions
                    .map((s) =>
                        DropdownMenuItem(value: s.id, child: Text(tr(s.name))))
                    .toList(),
                onChanged: (v) => setDlgState(() => selectedSessionId = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Ngày')),
                trailing: Text(tr(DateFormat('dd/MM/yyyy').format(menuDate))),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: menuDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                  );
                  if (d != null) setDlgState(() => menuDate = d);
                },
              ),
              TextField(
                controller: noteCtl,
                decoration: InputDecoration(
                    labelText: tr('Ghi chú'), border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              // Selected menu preview
              if (selectedDishes.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.restaurant_menu,
                              size: 16, color: Color(0xFF16A34A)),
                          const SizedBox(width: 6),
                          Text(tr('Thực đơn (${selectedDishes.length} món)'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF16A34A))),
                          const Spacer(),
                          if (selectedDishes.isNotEmpty)
                            GestureDetector(
                              onTap: () =>
                                  setDlgState(() => selectedDishIds.clear()),
                              child: Text(tr('Bỏ hết'),
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.red)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: selectedDishes
                            .map((d) => Chip(
                                  label: Text(tr(d.name),
                                      style: const TextStyle(fontSize: 11)),
                                  deleteIcon: const Icon(Icons.close, size: 14),
                                  onDeleted: () => setDlgState(
                                      () => selectedDishIds.remove(d.id)),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: const Color(0xFFDCFCE7),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Category filter
              Text(tr('Chọn món (${selectedDishIds.length} đã chọn)'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              if (categories.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    FilterChip(
                      label:
                          Text(tr('Tất cả'), style: TextStyle(fontSize: 11)),
                      selected: filterCategory == null,
                      onSelected: (_) =>
                          setDlgState(() => filterCategory = null),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    ...categories.map((c) {
                      final count = grouped[c]?.length ?? 0;
                      return FilterChip(
                        label: Text(tr('$c ($count)'),
                            style: const TextStyle(fontSize: 11)),
                        selected: filterCategory == c,
                        onSelected: (_) => setDlgState(() =>
                            filterCategory = filterCategory == c ? null : c),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }),
                  ],
                ),
              const SizedBox(height: 8),
              if (_masterDishes.isEmpty)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(tr('Chưa có món ăn. Vui lòng thêm món trong "Quản lý danh sách món".'),
                      style: TextStyle(color: Colors.grey)),
                ),
              ...filteredGrouped.entries.map((catEntry) {
                final cat = catEntry.key;
                final dishes = catEntry.value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Row(
                        children: [
                          Text(tr(cat),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: HrmPageChrome.chip,
                                  fontSize: 13)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              final allSelected = dishes
                                  .every((d) => selectedDishIds.contains(d.id));
                              setDlgState(() {
                                if (allSelected) {
                                  for (final d in dishes) {
                                    selectedDishIds.remove(d.id);
                                  }
                                } else {
                                  for (final d in dishes) {
                                    selectedDishIds.add(d.id);
                                  }
                                }
                              });
                            },
                            child: Text(
                              tr(dishes.every(
                                      (d) => selectedDishIds.contains(d.id))
                                  ? 'Bỏ chọn'
                                  : 'Chọn hết'),
                              style: const TextStyle(
                                  fontSize: 12, color: HrmPageChrome.chip),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...dishes.map((dish) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr(dish.name),
                              style: const TextStyle(fontSize: 14)),
                          value: selectedDishIds.contains(dish.id),
                          onChanged: (v) {
                            setDlgState(() {
                              if (v == true) {
                                selectedDishIds.add(dish.id);
                              } else {
                                selectedDishIds.remove(dish.id);
                              }
                            });
                          },
                        )),
                  ],
                );
              }),
            ],
          );

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(tr('Tạo thực đơn')),
                  leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton(
                          onPressed: onSave, child: Text(tr('Lưu'))),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16), child: formBody),
              ),
            );
          }

          return ScrollableAlertDialog(
            title: Text(tr('Tạo thực đơn')),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(child: formBody),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Hủy'))),
              FilledButton(onPressed: onSave, child: Text(tr('Lưu'))),
            ],
          );
        },
      ),
    );
  }

  // ==================== EDIT/DELETE MENU ====================

  void _showEditMenuDialog(MealMenu menu) {
    final noteCtl = TextEditingController(text: tr(menu.note ?? ''));
    final Set<String> selectedDishIds = {};
    // Pre-select dishes that match master list by name
    for (final item in menu.items) {
      final match =
          _masterDishes.where((d) => d.name == item.dishName).firstOrNull;
      if (match != null) selectedDishIds.add(match.id);
    }
    final isMobile = Responsive.isMobile(context);
    String? filterCategory;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          Future<void> onSave() async {
            if (selectedDishIds.isEmpty) {
              NotificationOverlayManager().showError(
                  title: 'Lỗi', message: tr('Vui lòng chọn ít nhất 1 món'));
              return;
            }
            final items = selectedDishIds.toList().asMap().entries.map((entry) {
              final dish = _masterDishes.firstWhere((d) => d.id == entry.value);
              return {
                'dishName': dish.name,
                'category': dish.category ?? '',
                'description': '',
                'sortOrder': entry.key,
              };
            }).toList();
            final data = {
              'note': noteCtl.text.trim(),
              'items': items,
            };
            final res = await _apiService.updateMealMenu(menu.id, data);
            if (ctx.mounted) Navigator.pop(ctx);
            if (res['isSuccess'] == true) {
              NotificationOverlayManager().showSuccess(
                  title: 'Thành công', message: tr('Đã cập nhật thực đơn'));
              _loadWeeklyMenu();
            } else {
              NotificationOverlayManager().showError(
                  title: 'Lỗi', message: res['message'] ?? 'Lỗi cập nhật');
            }
          }

          final grouped = <String, List<MealDish>>{};
          for (final d in _masterDishes) {
            final cat = d.category?.isNotEmpty == true ? d.category! : 'Khác';
            grouped.putIfAbsent(cat, () => []).add(d);
          }
          final categories = _getDistinctCategories();
          final filteredGrouped = filterCategory != null
              ? {filterCategory!: grouped[filterCategory] ?? []}
              : grouped;
          final selectedDishes = _masterDishes
              .where((d) => selectedDishIds.contains(d.id))
              .toList();

          final formBody = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                      tr('${menu.mealSessionName ?? ''} - ${DateFormat('dd/MM/yyyy').format(menu.date)}'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E40AF)),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtl,
                decoration: InputDecoration(
                    labelText: tr('Ghi chú'), border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              if (selectedDishes.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.restaurant_menu,
                            size: 16, color: Color(0xFF16A34A)),
                        const SizedBox(width: 6),
                        Text(tr('Thực đơn (${selectedDishes.length} món)'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF16A34A))),
                        const Spacer(),
                        GestureDetector(
                          onTap: () =>
                              setDlgState(() => selectedDishIds.clear()),
                          child: Text(tr('Bỏ hết'),
                              style:
                                  TextStyle(fontSize: 12, color: Colors.red)),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: selectedDishes
                            .map((d) => Chip(
                                  label: Text(tr(d.name),
                                      style: const TextStyle(fontSize: 11)),
                                  deleteIcon: const Icon(Icons.close, size: 14),
                                  onDeleted: () => setDlgState(
                                      () => selectedDishIds.remove(d.id)),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: const Color(0xFFDCFCE7),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(tr('Chọn món (${selectedDishIds.length} đã chọn)'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              if (categories.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    FilterChip(
                      label:
                          Text(tr('Tất cả'), style: TextStyle(fontSize: 11)),
                      selected: filterCategory == null,
                      onSelected: (_) =>
                          setDlgState(() => filterCategory = null),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    ...categories.map((c) {
                      final count = grouped[c]?.length ?? 0;
                      return FilterChip(
                        label: Text(tr('$c ($count)'),
                            style: const TextStyle(fontSize: 11)),
                        selected: filterCategory == c,
                        onSelected: (_) => setDlgState(() =>
                            filterCategory = filterCategory == c ? null : c),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }),
                  ],
                ),
              const SizedBox(height: 8),
              ...filteredGrouped.entries.map((catEntry) {
                final cat = catEntry.key;
                final dishes = catEntry.value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Row(children: [
                        Text(tr(cat),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: HrmPageChrome.chip,
                                fontSize: 13)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            final allSelected = dishes
                                .every((d) => selectedDishIds.contains(d.id));
                            setDlgState(() {
                              if (allSelected) {
                                for (final d in dishes) {
                                  selectedDishIds.remove(d.id);
                                }
                              } else {
                                for (final d in dishes) {
                                  selectedDishIds.add(d.id);
                                }
                              }
                            });
                          },
                          child: Text(
                            tr(dishes.every((d) => selectedDishIds.contains(d.id))
                                ? 'Bỏ chọn'
                                : 'Chọn hết'),
                            style: const TextStyle(
                                fontSize: 12, color: HrmPageChrome.chip),
                          ),
                        ),
                      ]),
                    ),
                    ...dishes.map((dish) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr(dish.name),
                              style: const TextStyle(fontSize: 14)),
                          value: selectedDishIds.contains(dish.id),
                          onChanged: (v) {
                            setDlgState(() {
                              if (v == true) {
                                selectedDishIds.add(dish.id);
                              } else {
                                selectedDishIds.remove(dish.id);
                              }
                            });
                          },
                        )),
                  ],
                );
              }),
            ],
          );

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(tr('Sửa thực đơn')),
                  leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton(
                          onPressed: onSave, child: Text(tr('Lưu'))),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16), child: formBody),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: Text(tr('Sửa thực đơn')),
            content: SizedBox(
                width: 400, child: SingleChildScrollView(child: formBody)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Hủy'))),
              FilledButton(onPressed: onSave, child: Text(tr('Lưu'))),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteMenu(MealMenu menu) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Xoá thực đơn')),
        content: Text(tr('${tr('Bạn có chắc muốn xoá thực đơn ')}${menu.mealSessionName ?? ''} ngày ${DateFormat('dd/MM/yyyy').format(menu.date)}?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xoá')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await _apiService.deleteMealMenu(menu.id);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager()
          .showSuccess(title: 'Thành công', message: tr('Đã xoá thực đơn'));
      _loadWeeklyMenu();
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message'] ?? 'Lỗi xoá thực đơn');
    }
  }

  // ==================== EXPORT MENU ====================

  Future<void> _exportMenuAsExcel() async {
    try {
      final excelLib = Excel.createExcel();
      final weekEnd = _menuWeekStart.add(const Duration(days: 6));
      final sheetName = 'Menu ${DateFormat('dd-MM').format(_menuWeekStart)}';
      final sheet = excelLib[sheetName];
      // Remove default sheet
      if (excelLib.sheets.containsKey('Sheet1')) {
        excelLib.delete('Sheet1');
      }

      // Header
      sheet.appendRow([
        TextCellValue(
            'THỰC ĐƠN TUẦN ${DateFormat('dd/MM').format(_menuWeekStart)} - ${DateFormat('dd/MM/yyyy').format(weekEnd)}'),
      ]);
      sheet.appendRow([]);
      sheet.appendRow([
        TextCellValue('Ngày'),
        TextCellValue('Thứ'),
        TextCellValue('Buổi ăn'),
        TextCellValue('Món ăn'),
        TextCellValue('Nhóm'),
        TextCellValue('Ghi chú'),
      ]);

      for (int i = 0; i < 7; i++) {
        final dayDate = _menuWeekStart.add(Duration(days: i));
        final dayMenus = _weeklyMenus
            .where((m) =>
                m.date.year == dayDate.year &&
                m.date.month == dayDate.month &&
                m.date.day == dayDate.day)
            .toList();
        if (dayMenus.isEmpty) {
          sheet.appendRow([
            TextCellValue(DateFormat('dd/MM/yyyy').format(dayDate)),
            TextCellValue(_dayNames[i]),
            TextCellValue(''),
            TextCellValue('Chưa có thực đơn'),
            TextCellValue(''),
            TextCellValue(''),
          ]);
        } else {
          for (final menu in dayMenus) {
            for (final item in menu.items) {
              sheet.appendRow([
                TextCellValue(DateFormat('dd/MM/yyyy').format(dayDate)),
                TextCellValue(_dayNames[i]),
                TextCellValue(menu.mealSessionName ?? ''),
                TextCellValue(item.dishName),
                TextCellValue(item.category ?? ''),
                TextCellValue(menu.note ?? ''),
              ]);
            }
          }
        }
      }

      final bytes = excelLib.encode();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/menu_${DateFormat('dd-MM-yyyy').format(_menuWeekStart)}.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(filePath)],
          text: tr('Thực đơn tuần ${DateFormat('dd/MM').format(_menuWeekStart)}'));
    } catch (e) {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: tr('Không thể xuất Excel: $e'));
    }
  }

  Future<void> _exportMenuAsPng() async {
    try {
      final boundary = _menuRepaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: tr('Không thể chụp ảnh menu'));
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/menu_${DateFormat('dd-MM-yyyy').format(_menuWeekStart)}.png';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(filePath)],
          text: tr('Thực đơn tuần ${DateFormat('dd/MM').format(_menuWeekStart)}'));
    } catch (e) {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: tr('Không thể xuất PNG: $e'));
    }
  }

  // ==================== DISH MANAGEMENT ====================

  List<String> _getDistinctCategories() {
    final cats = <String>{};
    for (final d in _masterDishes) {
      if (d.category != null && d.category!.isNotEmpty) {
        cats.add(d.category!);
      }
    }
    final sorted = cats.toList()..sort();
    return sorted;
  }

  void _showDishManagementDialog() {
    final isMobile = Responsive.isMobile(context);
    String? filterCategory;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          // Group by category
          final grouped = <String, List<MealDish>>{};
          for (final d in _masterDishes) {
            final cat = d.category?.isNotEmpty == true ? d.category! : 'Khác';
            grouped.putIfAbsent(cat, () => []).add(d);
          }
          final categories = _getDistinctCategories();

          // Filter if a category is selected
          final filteredGrouped = filterCategory != null
              ? {filterCategory!: grouped[filterCategory] ?? []}
              : grouped;

          Widget buildContent() {
            final perm = Provider.of<PermissionProvider>(ctx, listen: false);
            final canCreateMeal = perm.canCreate('Meal');
            final canEditMeal = perm.canEdit('Meal');
            final canDeleteMeal = perm.canDelete('Meal');
            return Column(
              children: [
                // Action buttons
                if (canCreateMeal)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () =>
                                _showAddDishDialog(ctx, setDlgState),
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(tr('Thêm món')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showCategoryManagementDialog(
                                ctx, setDlgState),
                            icon: const Icon(Icons.category, size: 18),
                            label: Text(tr('Nhóm món')),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Category filter chips
                if (categories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        FilterChip(
                          label: Text(tr('Tất cả'),
                              style: TextStyle(fontSize: 11)),
                          selected: filterCategory == null,
                          onSelected: (_) =>
                              setDlgState(() => filterCategory = null),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        ...categories.map((c) {
                          final count = grouped[c]?.length ?? 0;
                          return FilterChip(
                            label: Text(tr('$c ($count)'),
                                style: const TextStyle(fontSize: 11)),
                            selected: filterCategory == c,
                            onSelected: (_) => setDlgState(() =>
                                filterCategory =
                                    filterCategory == c ? null : c),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          );
                        }),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: _masterDishes.isEmpty
                      ? Center(
                          child: Text(tr('Chưa có món ăn nào'),
                              style: TextStyle(color: Colors.grey)))
                      : ListView(
                          children: filteredGrouped.entries.map((catEntry) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  color: const Color(0xFFF0F9FF),
                                  child: Row(
                                    children: [
                                      Text(tr(catEntry.key),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: HrmPageChrome.chip)),
                                      const SizedBox(width: 8),
                                      Text(tr('(${catEntry.value.length})'),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                ...catEntry.value.map((dish) => ListTile(
                                      title: Text(tr(dish.name)),
                                      trailing: (canEditMeal || canDeleteMeal)
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (canEditMeal)
                                                  IconButton(
                                                    icon: const Icon(Icons.edit,
                                                        size: 20,
                                                        color: Color(
                                                            0xFF3B82F6)),
                                                    onPressed: () =>
                                                        _showEditDishDialog(
                                                            ctx,
                                                            setDlgState,
                                                            dish),
                                                  ),
                                                if (canDeleteMeal)
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.delete,
                                                        size: 20,
                                                        color: Colors.red),
                                                    onPressed: () async {
                                                      final res =
                                                          await _apiService
                                                              .deleteMealDish(
                                                                  dish.id);
                                                      if (res['isSuccess'] ==
                                                          true) {
                                                        await _loadMasterDishes();
                                                        if (ctx.mounted) {
                                                          setDlgState(() {});
                                                        }
                                                      }
                                                    },
                                                  ),
                                              ],
                                            )
                                          : null,
                                    )),
                              ],
                            );
                          }).toList(),
                        ),
                ),
              ],
            );
          }

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(tr('Quản lý danh sách món')),
                  leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ),
                body: buildContent(),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: Text(tr('Quản lý danh sách món')),
            content: SizedBox(width: 450, height: 500, child: buildContent()),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Đóng')))
            ],
          );
        },
      ),
    );
  }

  void _showCategoryManagementDialog(
      BuildContext parentCtx, StateSetter parentSetState) {
    showDialog(
      context: parentCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final categories = _getDistinctCategories();
          return ScrollableAlertDialog(
            title: Text(tr('Nhóm món hiện có')),
            content: SizedBox(
              width: 350,
              height: 350,
              child: categories.isEmpty
                  ? Center(
                      child: Text(tr('Chưa có nhóm nào.\nThêm món với nhóm mới để tạo.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: categories.length,
                      itemBuilder: (_, i) {
                        final cat = categories[i];
                        final dishCount = _masterDishes
                            .where((d) =>
                                d.category?.toLowerCase() == cat.toLowerCase())
                            .length;
                        return ListTile(
                          leading: const Icon(Icons.folder_outlined,
                              color: HrmPageChrome.chip),
                          title: Text(tr(cat)),
                          subtitle: Text(tr('$dishCount món'),
                              style: const TextStyle(fontSize: 12)),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Đóng'))),
            ],
          );
        },
      ),
    );
  }

  void _showAddDishDialog(BuildContext parentCtx, StateSetter parentSetState) {
    final nameCtl = TextEditingController();
    final newCatCtl = TextEditingController();
    String? selectedCategory;
    bool addingNewCat = false;
    final categories = _getDistinctCategories();
    showDialog(
      context: parentCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => ScrollableAlertDialog(
          title: Text(tr('Thêm món mới')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(
                    labelText: tr('Tên món *'), border: OutlineInputBorder()),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              if (!addingNewCat)
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: InputDecoration(
                    labelText: tr('Nhóm món *'),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    ...categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(tr(c)))),
                    DropdownMenuItem(
                        value: '__new__',
                        child: Text(tr('+ Thêm nhóm mới...'),
                            style: TextStyle(
                                color: HrmPageChrome.chip,
                                fontWeight: FontWeight.w500))),
                  ],
                  onChanged: (v) {
                    if (v == '__new__') {
                      setDlgState(() {
                        addingNewCat = true;
                        selectedCategory = null;
                      });
                    } else {
                      setDlgState(() => selectedCategory = v);
                    }
                  },
                  hint: Text(tr('Chọn nhóm')),
                ),
              if (addingNewCat)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newCatCtl,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: tr('Tên nhóm mới *'),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setDlgState(() {
                        addingNewCat = false;
                      }),
                    ),
                  ],
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton(
              onPressed: () async {
                if (nameCtl.text.trim().isEmpty) return;
                final category =
                    addingNewCat ? newCatCtl.text.trim() : selectedCategory;
                if (category == null || category.isEmpty) {
                  NotificationOverlayManager().showError(
                      title: 'Lỗi', message: tr('Vui lòng chọn hoặc tạo nhóm món'));
                  return;
                }
                final res = await _apiService.createMealDish({
                  'name': nameCtl.text.trim(),
                  'category': category,
                  'sortOrder': 0,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (res['isSuccess'] == true) {
                  await _loadMasterDishes();
                  if (parentCtx.mounted) parentSetState(() {});
                } else {
                  NotificationOverlayManager().showError(
                      title: 'Lỗi', message: res['message'] ?? 'Thất bại');
                }
              },
              child: Text(tr('Thêm')),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDishDialog(
      BuildContext parentCtx, StateSetter parentSetState, MealDish dish) {
    final nameCtl = TextEditingController(text: tr(dish.name));
    String? selectedCategory = dish.category;
    final categories = _getDistinctCategories();
    // Ensure current category is in the list
    if (selectedCategory != null &&
        selectedCategory.isNotEmpty &&
        !categories.contains(selectedCategory)) {
      categories.add(selectedCategory);
      categories.sort();
    }
    showDialog(
      context: parentCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => ScrollableAlertDialog(
          title: Text(tr('Sửa món')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(
                    labelText: tr('Tên món *'), border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                decoration: InputDecoration(
                  labelText: tr('Nhóm món'),
                  border: OutlineInputBorder(),
                ),
                items: categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(tr(c))))
                    .toList(),
                onChanged: (v) => setDlgState(() => selectedCategory = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton(
              onPressed: () async {
                if (nameCtl.text.trim().isEmpty) return;
                final res = await _apiService.updateMealDish(dish.id, {
                  'name': nameCtl.text.trim(),
                  'category': selectedCategory ?? '',
                  'sortOrder': dish.sortOrder,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (res['isSuccess'] == true) {
                  await _loadMasterDishes();
                  if (parentCtx.mounted) parentSetState(() {});
                } else {
                  NotificationOverlayManager().showError(
                      title: 'Lỗi', message: res['message'] ?? 'Thất bại');
                }
              },
              child: Text(tr('Lưu')),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== SESSION COLOR HELPER ====================

  Color _sessionColor(String sessionId) {
    const colors = [
      HrmPageChrome.chipMid,
      Color(0xFF3B82F6),
      HrmPageChrome.chipLight,
      HrmPageChrome.chipSoft,
      Color(0xFFEF4444),
      HrmPageChrome.chipSoft,
    ];
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    return colors[(idx < 0 ? 0 : idx) % colors.length];
  }

  // ==================== DATE PICKERS ====================

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (d != null) {
      setState(() => _selectedDate = d);
      _loadCurrentTab();
    }
  }

  Future<void> _pickSummaryRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _summaryFrom, end: _summaryTo),
    );
    if (range != null) {
      setState(() {
        _summaryFrom = range.start;
        _summaryTo = range.end;
      });
      _loadEmployeeSummary();
    }
  }

  // ==================== BUILD ====================

  List<Widget> _buildTopActions() {
    final canCreate =
        Provider.of<PermissionProvider>(context, listen: false).canCreate('Meal');
    final tab = _tabCtl.index;

    return [
      if (tab == 0 || tab == 1)
        HrmTopBarAction(
          icon: Icons.calendar_today,
          label: 'Chọn ngày',
          onPressed: _pickDate,
        ),
      HrmTopBarAction(
        icon: Icons.restaurant_menu,
        label: 'Quản lý buổi ăn',
        onPressed: _showSessionsDialog,
      ),
      if (canCreate)
        HrmTopBarAction(
          icon: Icons.menu_book_outlined,
          label: 'Quản lý danh sách món',
          onPressed: _showDishManagementDialog,
        ),
      if (canCreate)
        HrmTopBarAction(
          icon: Icons.add_chart_outlined,
          label: 'Tạo thực đơn',
          onPressed: _showCreateMenuDialog,
        ),
      if (_weeklyMenus.isNotEmpty) ...[
        HrmTopBarAction(
          icon: Icons.image_outlined,
          label: 'Xuất ảnh PNG',
          onPressed: _exportMenuAsPng,
        ),
        HrmTopBarAction(
          icon: Icons.file_download_outlined,
          label: 'Xuất Excel',
          onPressed: _exportMenuAsExcel,
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return RegisterPageTopActions(
      actions: _buildTopActions(),
      child: Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabCtl,
              isScrollable: isMobile,
              tabs: [
                Tab(icon: Icon(Icons.restaurant), text: tr('Tổng quan')),
                Tab(icon: Icon(Icons.list_alt), text: tr('Lịch sử')),
                Tab(icon: Icon(Icons.people), text: tr('Tổng hợp')),
                Tab(icon: Icon(Icons.menu_book), text: tr('Thực đơn')),
                Tab(icon: Icon(Icons.account_balance_wallet), text: tr('Công nợ')),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtl,
              children: [
                _buildDashboardTab(),
                _buildRecordsTab(),
                _buildSummaryTab(),
                _buildMenuTab(),
                _buildDebtTab(),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildMealOverviewSection({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: HrmCollapsibleOverview(
        expanded: _showOverviewPanel,
        onToggle: () =>
            setState(() => _showOverviewPanel = !_showOverviewPanel),
        child: child,
      ),
    );
  }

  // ==================== TAB 1: DASHBOARD ====================

  Widget _buildDashboardTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_mealSummary == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(tr('${tr('Chưa có dữ liệu cho ngày ')}${DateFormat('dd/MM/yyyy').format(_selectedDate)}'),
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadEstimate,
              child: Text(tr('Tải lại')),
            ),
          ],
        ),
      );
    }
    final summary = _mealSummary!;
    return RefreshIndicator(
      onRefresh: _loadEstimate,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
        children: [
          _buildMealOverviewSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: tr('Ngày trước'),
                          onPressed: () {
                            setState(() => _selectedDate =
                                _selectedDate.subtract(const Duration(days: 1)));
                            _loadCurrentTab();
                          },
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.calendar_today,
                                      size: 16, color: HrmPageChrome.chip),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      tr(DateFormat('EEEE, dd/MM/yyyy', 'vi')
                                          .format(summary.date)),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(tr('Ước tính: ${summary.totalEstimated} | Thực tế: ${summary.totalActual}'),
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: tr('Ngày sau'),
                          onPressed: () {
                            setState(() => _selectedDate =
                                _selectedDate.add(const Duration(days: 1)));
                            _loadCurrentTab();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        'Ước tính',
                        summary.totalEstimated.toString(),
                        Icons.people,
                        const Color(0xFF3B82F6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryCard(
                        'Thực ăn',
                        summary.totalActual.toString(),
                        Icons.restaurant,
                        HrmPageChrome.chipMid,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryCard(
                        'Còn lại',
                        (summary.totalEstimated - summary.totalActual)
                            .toString(),
                        Icons.hourglass_bottom,
                        HrmPageChrome.chipLight,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          // Today's menu section
          _buildTodayMenuSection(),
          const SizedBox(height: 24),
          Text(tr('Chi tiết theo buổi'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...summary.sessions.map(_buildSessionCard),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(tr(value),
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            Text(tr(label), style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayMenuSection() {
    final todayMenus = _weeklyMenus
        .where((m) =>
            m.date.year == _selectedDate.year &&
            m.date.month == _selectedDate.month &&
            m.date.day == _selectedDate.day)
        .toList();

    if (todayMenus.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.menu_book, size: 36, color: Colors.grey[300]),
              const SizedBox(width: 16),
              Expanded(
                child: Text(tr('Chưa có thực đơn cho ngày này'),
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
              ),
            ],
          ),
        ),
      );
    }

    // Group items by session
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HrmPageChrome.chip, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: HrmPageChrome.chip,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.restaurant_menu,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(tr('${tr('Thực đơn ')}${DateFormat('dd/MM/yyyy').format(_selectedDate)}'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ],
            ),
          ),
          ...todayMenus.map((menu) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                HrmPageChrome.chip.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tr(menu.mealSessionName ?? 'Buổi ăn'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: HrmPageChrome.chip,
                                fontSize: 13),
                          ),
                        ),
                        if (menu.note != null && menu.note!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(tr(menu.note!),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontStyle: FontStyle.italic),
                                  overflow: TextOverflow.ellipsis)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...menu.items.map((item) => Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                    color: HrmPageChrome.chipMid,
                                    shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(tr(item.dishName),
                                      style: const TextStyle(fontSize: 14))),
                              if (item.category != null &&
                                  item.category!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: HrmPageChrome.chipMid
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(tr(item.category!),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: HrmPageChrome.chipMid,
                                          fontWeight: FontWeight.w500)),
                                ),
                            ],
                          ),
                        )),
                    if (todayMenus.last != menu) const Divider(height: 8),
                  ],
                ),
              )),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSessionCard(MealEstimate est) {
    final percent = est.estimatedCount > 0
        ? (est.actualCount / est.estimatedCount).clamp(0.0, 1.0)
        : 0.0;
    // Find today's menu for this session
    final todayMenus = _weeklyMenus
        .where((m) =>
            m.mealSessionId == est.mealSessionId &&
            m.date.year == _selectedDate.year &&
            m.date.month == _selectedDate.month &&
            m.date.day == _selectedDate.day)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr(est.mealSessionName),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  tr('${est.startTime ?? ''} - ${est.endTime ?? ''}'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            if (est.pricePerMeal > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('Giá: ${_formatCurrency(est.pricePerMeal)}/suất'),
                    style: const TextStyle(
                        color: HrmPageChrome.chipLight, fontSize: 13)),
              ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(percent < 0.7
                    ? HrmPageChrome.chipMid
                    : HrmPageChrome.chipLight),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _miniStat('Đăng ký', est.registeredCount.toString(),
                    HrmPageChrome.chipSoft),
                const SizedBox(width: 12),
                _miniStat('Ước tính', est.estimatedCount.toString(),
                    const Color(0xFF3B82F6)),
                const SizedBox(width: 12),
                _miniStat('Thực tế', est.actualCount.toString(),
                    HrmPageChrome.chipMid),
                const SizedBox(width: 12),
                _miniStat(
                    'Còn', est.remaining.toString(), HrmPageChrome.chipLight),
              ],
            ),
            // Today's menu inline
            if (todayMenus.isNotEmpty) ...[
              const Divider(height: 20),
              Text(tr('🍽️ Thực đơn hôm nay'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: HrmPageChrome.chip)),
              const SizedBox(height: 4),
              ...todayMenus.expand((menu) => menu.items.map((item) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.circle,
                            size: 5, color: HrmPageChrome.chipMid),
                        const SizedBox(width: 6),
                        Text(tr(item.dishName),
                            style: const TextStyle(fontSize: 13)),
                        if (item.category != null && item.category!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(tr('(${item.category})'),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ),
                      ],
                    ),
                  ))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(tr(value),
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 15)),
          Text(tr(label), style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  // ==================== TAB 2: RECORDS ====================

  Widget _buildRecordsTab() {
    final canManage = Provider.of<PermissionProvider>(context, listen: false)
        .canCreate('Meal');
    return Column(
      children: [
        _buildMealOverviewSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: InputDecoration(
                          labelText: tr('Ngày'),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                      child: InkWell(
                        onTap: _pickDate,
                        child: Text(
                            tr(DateFormat('dd/MM/yyyy').format(_selectedDate))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _filterSessionId,
                      decoration: InputDecoration(
                          labelText: tr('Buổi ăn'),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                      items: [
                        DropdownMenuItem(
                            value: null, child: Text(tr('Tất cả'))),
                        ..._sessions.map((s) => DropdownMenuItem(
                            value: s.id, child: Text(tr(s.name)))),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _filterSessionId = v;
                          _currentPage = 1;
                        });
                        _loadRecords();
                      },
                    ),
                  ),
                  if (canManage) ...[
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.add),
                      tooltip: tr('Thêm chấm cơm'),
                      onPressed: _showAddRecordDialog,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: tr('Tìm theo tên nhân viên...'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  suffixIcon: _recordSearch.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() => _recordSearch = ''),
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _recordSearch = v),
              ),
            ],
          ),
        ),
        // Record count
        if (!_isLoading && _records.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr(_totalPages > 1
                    ? '$_totalRecords bản ghi • Trang $_currentPage/$_totalPages'
                    : '${_records.length} bản ghi'),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
        // Records list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _records.isEmpty
                  ? Center(
                      child: Text(tr('Chưa có dữ liệu chấm cơm'),
                          style: TextStyle(color: Colors.grey)))
                  : Builder(builder: (_) {
                      final filtered = _recordSearch.isEmpty
                          ? _records
                          : _records
                              .where((r) => r.employeeName
                                  .toLowerCase()
                                  .contains(_recordSearch.toLowerCase()))
                              .toList();
                      if (filtered.isEmpty) {
                        return Center(
                            child: Text(tr('Không tìm thấy'),
                                style: TextStyle(color: Colors.grey)));
                      }
                      return ListView.builder(
                        itemCount: filtered.length,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemBuilder: (_, i) {
                          final r = filtered[i];
                          final canManage = Provider.of<PermissionProvider>(
                                  context,
                                  listen: false)
                              .canCreate('Meal');
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _sessionColor(r.mealSessionId),
                                child: Text(
                                  tr(r.employeeName.isNotEmpty
                                      ? r.employeeName[0].toUpperCase()
                                      : '?'),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(tr(r.employeeName)),
                              subtitle: Text(
                                tr('${r.mealSessionName ?? ''} | ${DateFormat('HH:mm').format(r.mealTime)}'),
                              ),
                              trailing: canManage
                                  ? PopupMenuButton<String>(
                                      icon: Icon(Icons.more_vert,
                                          color: Colors.grey[600], size: 20),
                                      onSelected: (v) {
                                        if (v == 'edit') {
                                          _showEditRecordDialog(r);
                                        }
                                        if (v == 'delete') _deleteRecord(r);
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                            value: 'edit', child: Text(tr('Sửa'))),
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text(tr('Xóa'),
                                                style: TextStyle(
                                                    color: Colors.red))),
                                      ],
                                    )
                                  : Text(
                                      tr(r.deviceName ?? r.pin ?? ''),
                                      style:
                                          const TextStyle(color: Colors.grey),
                                    ),
                            ),
                          );
                        },
                      );
                    }),
        ),
        // Pagination
        if (_totalPages > 1)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _loadRecords();
                        }
                      : null,
                ),
                Text(tr('Trang $_currentPage / $_totalPages')),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentPage < _totalPages
                      ? () {
                          setState(() => _currentPage++);
                          _loadRecords();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ==================== TAB 4: SUMMARY ====================

  Widget _buildSummaryTab() {
    return Column(
      children: [
        _buildMealOverviewSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickSummaryRange,
                      child: InputDecorator(
                        decoration: InputDecoration(
                            labelText: tr('Khoảng thời gian'),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8)),
                        child: Text(
                          tr('${DateFormat('dd/MM/yyyy').format(_summaryFrom)} - ${DateFormat('dd/MM/yyyy').format(_summaryTo)}'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.search),
                    label: Text(tr('Xem')),
                    onPressed: _loadEmployeeSummary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: tr('Tìm theo tên / mã nhân viên...'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  suffixIcon: _summarySearch.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() => _summarySearch = ''),
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _summarySearch = v),
              ),
              if (BranchFilterHelper.showBranchFilter(_branches)) ...[
                const SizedBox(height: 6),
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.account_tree_outlined,
                        size: 16, color: Color(0xFF6B7280)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedBranchId,
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF111827)),
                          icon: const Icon(Icons.keyboard_arrow_down,
                              size: 18, color: Color(0xFF9CA3AF)),
                          items: [
                            DropdownMenuItem<String?>(
                                value: null,
                                child: Text(tr('Tất cả chi nhánh'),
                                    style: TextStyle(fontSize: 13))),
                            ..._branches.map((b) => DropdownMenuItem<String?>(
                                value: b['id']?.toString(),
                                child: Text(tr(b['name']?.toString() ?? ''),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)))),
                          ],
                          onChanged: (v) =>
                              setState(() => _selectedBranchId = v),
                        ),
                      ),
                    ),
                    if (_selectedBranchId != null)
                      InkWell(
                        onTap: () => setState(() => _selectedBranchId = null),
                        child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close,
                                size: 14, color: Color(0xFF9CA3AF))),
                      ),
                  ]),
                ),
              ],
            ],
          ),
        ),
        // Summary list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _employeeSummaries.isEmpty
                  ? Center(
                      child: Text(tr('Chưa có dữ liệu'),
                          style: TextStyle(color: Colors.grey)))
                  : Builder(
                      builder: (_) {
                        final q = _summarySearch.toLowerCase();
                        // Filter by branch
                        Set<String>? branchEmpIds;
                        if (_selectedBranchId != null) {
                          branchEmpIds = _employees
                              .whereType<Map>()
                              .where((e) =>
                                  e['branchId']?.toString() ==
                                  _selectedBranchId)
                              .map((e) => e['id']?.toString() ?? '')
                              .toSet();
                        }
                        var filtered = branchEmpIds != null
                            ? _employeeSummaries
                                .where((s) =>
                                    branchEmpIds!.contains(s.employeeUserId))
                                .toList()
                            : _employeeSummaries;
                        if (q.isNotEmpty) {
                          filtered = filtered
                              .where((s) =>
                                  s.employeeName.toLowerCase().contains(q) ||
                                  (s.employeeCode ?? '')
                                      .toLowerCase()
                                      .contains(q))
                              .toList();
                        }
                        if (filtered.isEmpty) {
                          return Center(
                              child: Text(tr('Không tìm thấy'),
                                  style: TextStyle(color: Colors.grey)));
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            final paidRatio = s.totalCost > 0
                                ? (s.totalPaid / s.totalCost).clamp(0.0, 1.0)
                                : 1.0;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showEmployeeDetail(s),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor:
                                            HrmPageChrome.chip,
                                        child: Text(
                                          tr(s.employeeName.isNotEmpty
                                              ? s.employeeName[0].toUpperCase()
                                              : '?'),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(tr(s.employeeName),
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14)),
                                            Text(
                                              tr('${s.employeeCode ?? ''} | ${s.totalMeals} suất | ${_formatCurrency(s.totalCost)}'),
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12),
                                            ),
                                            const SizedBox(height: 4),
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: paidRatio,
                                                minHeight: 5,
                                                backgroundColor: Colors.red
                                                    .withValues(alpha: 0.15),
                                                valueColor:
                                                    const AlwaysStoppedAnimation(
                                                        HrmPageChrome.chipMid),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(tr('Đã trả ${_formatCurrency(s.totalPaid)}'),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            tr(_formatCurrency(s.balance)),
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: s.balance > 0
                                                    ? Colors.red
                                                    : HrmPageChrome.chipMid),
                                          ),
                                          Text(
                                            tr(s.balance > 0
                                                ? 'Còn nợ'
                                                : 'Đã trả đủ'),
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
        ),
        // Total
        if (_employeeSummaries.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFF0F9FF),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('${_employeeSummaries.length} NV'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(tr('Suất: ${_employeeSummaries.fold<int>(0, (sum, e) => sum + e.totalMeals)}'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: HrmPageChrome.chip),
                ),
                Text(tr('Nợ: ${_formatCurrency(_employeeSummaries.fold<double>(0, (sum, e) => sum + e.balance))}'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showEmployeeDetail(EmployeeMealSummary emp) {
    final isMobile = Responsive.isMobile(context);

    Widget buildList() {
      if (emp.details.isEmpty) {
        return Center(child: Text(tr('Không có chi tiết')));
      }
      return ListView.builder(
        shrinkWrap: !isMobile,
        physics: isMobile ? null : const NeverScrollableScrollPhysics(),
        itemCount: emp.details.length,
        itemBuilder: (_, i) {
          final d = emp.details[i];
          return ListTile(
            leading: const Icon(Icons.restaurant, color: HrmPageChrome.chipMid),
            title: Text(tr(d.mealSessionName)),
            subtitle: Text(tr(DateFormat('dd/MM/yyyy').format(d.date))),
            trailing: Text(tr(DateFormat('HH:mm').format(d.mealTime))),
          );
        },
      );
    }

    showDialog(
      context: context,
      builder: (ctx) {
        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(tr(emp.employeeName)),
                leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx)),
              ),
              body: buildList(),
            ),
          );
        }

        return ScrollableAlertDialog(
          title: Text(tr(emp.employeeName)),
          content: SizedBox(
            width: 400,
            height: 400,
            child: buildList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
          ],
        );
      },
    );
  }

  // ==================== TAB 4: MENU ====================

  Widget _buildMenuTab() {
    final canManage = Provider.of<PermissionProvider>(context, listen: false)
        .canCreate('Meal');
    final weekEnd = _menuWeekStart.add(const Duration(days: 6));
    bool isToday(d) =>
        d.year == DateTime.now().year &&
        d.month == DateTime.now().month &&
        d.day == DateTime.now().day;

    return Column(
      children: [
        // Week navigation + export bar
        Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      setState(() => _menuWeekStart =
                          _menuWeekStart.subtract(const Duration(days: 7)));
                      _loadWeeklyMenu();
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: Text(tr('${tr('Tuần ')}${DateFormat('dd/MM').format(_menuWeekStart)} - ${DateFormat('dd/MM/yyyy').format(weekEnd)}'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      setState(() => _menuWeekStart =
                          _menuWeekStart.add(const Duration(days: 7)));
                      _loadWeeklyMenu();
                    },
                  ),
                ],
              ),
              if (_weeklyMenus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.image, size: 16),
                        label: Text(tr('Xuất ảnh')),
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        onPressed: _exportMenuAsPng,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.table_chart, size: 16),
                        label: Text(tr('Xuất Excel')),
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        onPressed: _exportMenuAsExcel,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _weeklyMenus.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.restaurant_menu,
                              size: 72, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(tr('Chưa có thực đơn cho tuần này'),
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 15)),
                          if (canManage) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              icon: const Icon(Icons.add),
                              label: Text(tr('Tạo thực đơn')),
                              onPressed: _showCreateMenuDialog,
                            ),
                          ],
                        ],
                      ),
                    )
                  : RepaintBoundary(
                      key: _menuRepaintKey,
                      child: Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                          itemCount: 7,
                          itemBuilder: (_, dayIndex) {
                            final dayDate =
                                _menuWeekStart.add(Duration(days: dayIndex));
                            final dayMenus = _weeklyMenus
                                .where((m) =>
                                    m.date.year == dayDate.year &&
                                    m.date.month == dayDate.month &&
                                    m.date.day == dayDate.day)
                                .toList();
                            final today = isToday(dayDate);

                            if (dayMenus.isEmpty) {
                              return Opacity(
                                opacity: 0.5,
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  child: ListTile(
                                    dense: true,
                                    leading: _buildDayBadge(dayDate, today),
                                    title: Text(tr(_dayNames[dayIndex]),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500)),
                                    subtitle: Text(tr('Chưa có thực đơn'),
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                              );
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: today ? 3 : 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: today
                                    ? const BorderSide(
                                        color: HrmPageChrome.chip, width: 1.5)
                                    : BorderSide.none,
                              ),
                              child: Theme(
                                data: Theme.of(context)
                                    .copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  initiallyExpanded: today,
                                  tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  leading: _buildDayBadge(dayDate, today),
                                  title: Row(
                                    children: [
                                      Text(tr(_dayNames[dayIndex]),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: HrmPageChrome.chip
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(tr('${dayMenus.length} buổi'),
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: HrmPageChrome.chip,
                                                fontWeight: FontWeight.w500)),
                                      ),
                                    ],
                                  ),
                                  children: dayMenus
                                      .map((menu) => _buildMenuSessionCard(
                                          menu, canManage))
                                      .toList(),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildDayBadge(DateTime date, bool isToday) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isToday ? HrmPageChrome.chip : Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          tr('${date.day}'),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: isToday ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuSessionCard(MealMenu menu, bool canManage) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session header with actions
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 6),
              decoration: BoxDecoration(
                color: HrmPageChrome.chip.withValues(alpha: 0.06),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.restaurant,
                      size: 18, color: HrmPageChrome.chip),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(menu.mealSessionName ?? 'Buổi ăn'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: HrmPageChrome.chip,
                          fontSize: 14),
                    ),
                  ),
                  if (canManage) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: tr('Sửa thực đơn'),
                      onPressed: () => _showEditMenuDialog(menu),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Colors.red),
                      visualDensity: VisualDensity.compact,
                      tooltip: tr('Xoá thực đơn'),
                      onPressed: () => _deleteMenu(menu),
                    ),
                  ],
                ],
              ),
            ),
            if (menu.note != null && menu.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Text(tr(menu.note!),
                    style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[600],
                        fontSize: 12)),
              ),
            // Dish list
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                children: menu.items.asMap().entries.map((entry) {
                  final item = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: HrmPageChrome.chipMid, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(tr(item.dishName),
                                style: const TextStyle(fontSize: 13.5))),
                        if (item.category != null && item.category!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: HrmPageChrome.chipMid
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(tr(item.category!),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: HrmPageChrome.chipMid,
                                    fontWeight: FontWeight.w500)),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TAB 5: DEBT ====================

  Widget _buildDebtTab() {
    final canManage = Provider.of<PermissionProvider>(context, listen: false)
        .canCreate('Meal');
    return Column(
      children: [
        // Period selector
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  final parts = _debtPeriod.split('-');
                  var y = int.parse(parts[0]);
                  var m = int.parse(parts[1]) - 1;
                  if (m < 1) {
                    m = 12;
                    y--;
                  }
                  setState(
                      () => _debtPeriod = '$y-${m.toString().padLeft(2, '0')}');
                  _loadDebtSummary();
                },
              ),
              Expanded(
                child: Text(tr('Tháng $_debtPeriod'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  final parts = _debtPeriod.split('-');
                  var y = int.parse(parts[0]);
                  var m = int.parse(parts[1]) + 1;
                  if (m > 12) {
                    m = 1;
                    y++;
                  }
                  setState(
                      () => _debtPeriod = '$y-${m.toString().padLeft(2, '0')}');
                  _loadDebtSummary();
                },
              ),
            ],
          ),
        ),
        // Batch charge button
        if (canManage)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => ScrollableAlertDialog(
                          title: Text(tr('Tính tiền cơm')),
                          content: Text(tr('Tự động tính tiền cơm cho tất cả nhân viên tháng $_debtPeriod dựa trên số suất ăn thực tế?')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(tr('Hủy'))),
                            FilledButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _doBatchCharge();
                              },
                              child: Text(tr('Xác nhận')),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.calculate),
                    label: Text(tr('Tính tiền cơm tháng')),
                    style: FilledButton.styleFrom(
                        backgroundColor: HrmPageChrome.chipLight),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadDebtSummary,
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: tr('Tìm theo tên / mã nhân viên...'),
              prefixIcon: const Icon(Icons.search, size: 20),
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
              suffixIcon: _debtSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _debtSearch = ''),
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _debtSearch = v),
          ),
        ),
        // Debt list
        Expanded(
          child: _isLoadingDebt
              ? const Center(child: CircularProgressIndicator())
              : _debtSummaries.isEmpty
                  ? Center(
                      child: Text(tr('Chưa có dữ liệu công nợ'),
                          style: TextStyle(color: Colors.grey)))
                  : Builder(
                      builder: (_) {
                        final q = _debtSearch.toLowerCase();
                        final filtered = q.isEmpty
                            ? _debtSummaries
                            : _debtSummaries
                                .where((d) =>
                                    d.employeeName.toLowerCase().contains(q) ||
                                    (d.employeeCode ?? '')
                                        .toLowerCase()
                                        .contains(q))
                                .toList();
                        if (filtered.isEmpty) {
                          return Center(
                              child: Text(tr('Không tìm thấy'),
                                  style: TextStyle(color: Colors.grey)));
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final d = filtered[i];
                            final paidRatio = d.totalCharged > 0
                                ? (d.totalPaid / d.totalCharged).clamp(0.0, 1.0)
                                : 1.0;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: d.balance > 0
                                          ? const Color(0xFFEF4444)
                                          : HrmPageChrome.chipMid,
                                      child: Text(
                                        tr(d.employeeName.isNotEmpty
                                            ? d.employeeName[0].toUpperCase()
                                            : '?'),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(tr(d.employeeName),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14)),
                                          Text(
                                            tr('${d.employeeCode ?? ''} | ${d.totalMeals} suất'),
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12),
                                          ),
                                          const SizedBox(height: 4),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: paidRatio,
                                              minHeight: 5,
                                              backgroundColor: Colors.red
                                                  .withValues(alpha: 0.15),
                                              valueColor:
                                                  const AlwaysStoppedAnimation(
                                                      HrmPageChrome.chipMid),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(tr('Đã trả ${_formatCurrency(d.totalPaid)} / ${_formatCurrency(d.totalCharged)}'),
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          tr(_formatCurrency(d.balance)),
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: d.balance > 0
                                                  ? Colors.red
                                                  : HrmPageChrome.chipMid),
                                        ),
                                        Text(
                                          tr(d.balance > 0
                                              ? 'Còn nợ'
                                              : 'Đã trả đủ'),
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey[600]),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (canManage && d.balance > 0) ...[
                                              InkWell(
                                                onTap: () =>
                                                    _showRecordPaymentDialog(d),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: Tooltip(
                                                  message: tr('Thu tiền'),
                                                  child: Padding(
                                                    padding: EdgeInsets.all(4),
                                                    child: Icon(Icons.payment,
                                                        color:
                                                            HrmPageChrome.chipMid,
                                                        size: 22),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            InkWell(
                                              onTap: () =>
                                                  _showDebtHistoryDialog(d),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Tooltip(
                                                message: tr('Lịch sử'),
                                                child: Padding(
                                                  padding: EdgeInsets.all(4),
                                                  child: Icon(Icons.history,
                                                      color: Color(0xFF3B82F6),
                                                      size: 22),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
        ),
        // Total bar
        if (_debtSummaries.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFFEF3C7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('${_debtSummaries.length} NV'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(tr('Tổng nợ: ${_formatCurrency(_debtSummaries.fold<double>(0, (sum, e) => sum + e.balance))}'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showDebtHistoryDialog(MealDebtSummary debt) async {
    await _loadDebtHistory(debt.employeeUserId);
    if (!mounted) return;
    final isMobile = Responsive.isMobile(context);

    Widget buildList() {
      if (_debtHistory.isEmpty) {
        return Center(child: Text(tr('Chưa có giao dịch')));
      }
      return ListView.builder(
        shrinkWrap: !isMobile,
        physics: isMobile ? null : const NeverScrollableScrollPhysics(),
        itemCount: _debtHistory.length,
        itemBuilder: (_, i) {
          final d = _debtHistory[i];
          final isPayment = d.type == 1;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  isPayment ? HrmPageChrome.chipMid : const Color(0xFFEF4444),
              child: Icon(isPayment ? Icons.arrow_downward : Icons.arrow_upward,
                  color: Colors.white, size: 18),
            ),
            title: Text(tr('${isPayment ? "Thu tiền" : "Tính cơm"}: ${_formatCurrency(d.amount)}'),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isPayment
                      ? HrmPageChrome.chipMid
                      : const Color(0xFFEF4444)),
            ),
            subtitle: Text(
              tr('${DateFormat('dd/MM/yyyy').format(d.date)}${d.note != null && d.note!.isNotEmpty ? ' - ${d.note}' : ''}'),
            ),
            trailing: Text(tr(d.recordedByName ?? ''),
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          );
        },
      );
    }

    showDialog(
      context: context,
      builder: (ctx) {
        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(tr('Công nợ - ${debt.employeeName}')),
                leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx)),
              ),
              body: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: const Color(0xFFFEF3C7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(children: [
                          Text(tr(_formatCurrency(debt.totalCharged)),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(tr('Tiền cơm'),
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                        ]),
                        Column(children: [
                          Text(tr(_formatCurrency(debt.totalPaid)),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: HrmPageChrome.chipMid)),
                          Text(tr('Đã trả'),
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                        ]),
                        Column(children: [
                          Text(tr(_formatCurrency(debt.balance)),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red)),
                          Text(tr('Còn nợ'),
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                        ]),
                      ],
                    ),
                  ),
                  Expanded(child: buildList()),
                ],
              ),
            ),
          );
        }
        return ScrollableAlertDialog(
          title: Text(tr('Công nợ - ${debt.employeeName}')),
          content: SizedBox(width: 400, height: 400, child: buildList()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
          ],
        );
      },
    );
  }

  // ==================== RECORD MANAGEMENT DIALOGS ====================

  void _showAddRecordDialog() {
    String? selectedEmployeeId;
    String? selectedSessionId =
        _sessions.isNotEmpty ? _sessions.first.id : null;
    TimeOfDay mealTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => ScrollableAlertDialog(
          title: Text(tr('Thêm chấm cơm thủ công')),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Employee dropdown
                Autocomplete<Map<String, dynamic>>(
                  optionsBuilder: (textEditingValue) {
                    final list = _employees.cast<Map<String, dynamic>>();
                    if (textEditingValue.text.isEmpty) return list.take(20);
                    final q = textEditingValue.text.toLowerCase();
                    return list.where((e) {
                      final name =
                          (e['fullName'] ?? '').toString().toLowerCase();
                      final code =
                          (e['employeeCode'] ?? '').toString().toLowerCase();
                      return name.contains(q) || code.contains(q);
                    }).take(20);
                  },
                  displayStringForOption: (e) =>
                      '${e['fullName']} (${e['employeeCode'] ?? ''})',
                  fieldViewBuilder: (ctx, ctl, fn, onSubmit) => TextField(
                    controller: ctl,
                    focusNode: fn,
                    decoration: InputDecoration(
                        labelText: tr('Nhân viên *'), border: OutlineInputBorder()),
                  ),
                  onSelected: (e) {
                    selectedEmployeeId = e['userId']?.toString();
                  },
                ),
                const SizedBox(height: 12),
                // Session dropdown
                DropdownButtonFormField<String>(
                  initialValue: selectedSessionId,
                  decoration: InputDecoration(
                      labelText: tr('Buổi ăn *'), border: OutlineInputBorder()),
                  items: _sessions
                      .map((s) =>
                          DropdownMenuItem(value: s.id, child: Text(tr(s.name))))
                      .toList(),
                  onChanged: (v) => setDlgState(() => selectedSessionId = v),
                ),
                const SizedBox(height: 12),
                // Time
                InkWell(
                  onTap: () async {
                    final t = await showTimePicker(
                        context: ctx, initialTime: mealTime);
                    if (t != null) setDlgState(() => mealTime = t);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                        labelText: tr('Giờ ăn'), border: OutlineInputBorder()),
                    child: Text(
                        tr('${mealTime.hour.toString().padLeft(2, '0')}:${mealTime.minute.toString().padLeft(2, '0')}')),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton(
              onPressed: () async {
                if (selectedEmployeeId == null || selectedSessionId == null) {
                  NotificationOverlayManager().showError(
                      title: 'Lỗi',
                      message: tr('Vui lòng chọn nhân viên và buổi ăn'));
                  return;
                }
                Navigator.pop(ctx);
                final mealDateTime = DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    mealTime.hour,
                    mealTime.minute);
                final res = await _apiService.createMealRecord({
                  'employeeUserId': selectedEmployeeId,
                  'mealSessionId': selectedSessionId,
                  'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
                  'mealTime': mealDateTime.toIso8601String(),
                });
                if (res['isSuccess'] == true) {
                  NotificationOverlayManager().showSuccess(
                      title: 'Thành công', message: tr('Đã thêm chấm cơm'));
                  _loadRecords();
                } else {
                  NotificationOverlayManager().showError(
                      title: 'Lỗi', message: res['message'] ?? 'Thêm thất bại');
                }
              },
              child: Text(tr('Thêm')),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditRecordDialog(MealRecord record) {
    String? selectedSessionId = record.mealSessionId;
    TimeOfDay mealTime =
        TimeOfDay(hour: record.mealTime.hour, minute: record.mealTime.minute);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => ScrollableAlertDialog(
          title: Text(tr('Sửa chấm cơm - ${record.employeeName}')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedSessionId,
                decoration: InputDecoration(
                    labelText: tr('Buổi ăn'), border: OutlineInputBorder()),
                items: _sessions
                    .map((s) =>
                        DropdownMenuItem(value: s.id, child: Text(tr(s.name))))
                    .toList(),
                onChanged: (v) => setDlgState(() => selectedSessionId = v),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final t =
                      await showTimePicker(context: ctx, initialTime: mealTime);
                  if (t != null) setDlgState(() => mealTime = t);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: tr('Giờ ăn'), border: OutlineInputBorder()),
                  child: Text(
                      tr('${mealTime.hour.toString().padLeft(2, '0')}:${mealTime.minute.toString().padLeft(2, '0')}')),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final mealDateTime = DateTime(
                    record.date.year,
                    record.date.month,
                    record.date.day,
                    mealTime.hour,
                    mealTime.minute);
                final res = await _apiService.updateMealRecord(record.id, {
                  'mealSessionId': selectedSessionId,
                  'mealTime': mealDateTime.toIso8601String(),
                });
                if (res['isSuccess'] == true) {
                  NotificationOverlayManager()
                      .showSuccess(title: 'Thành công', message: tr('Đã cập nhật'));
                  _loadRecords();
                } else {
                  NotificationOverlayManager().showError(
                      title: 'Lỗi',
                      message: res['message'] ?? 'Cập nhật thất bại');
                }
              },
              child: Text(tr('Lưu')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteRecord(MealRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Xác nhận xóa')),
        content: Text(tr('Xóa chấm cơm của ${record.employeeName}?')),
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
    if (confirm != true) return;
    final res = await _apiService.deleteMealRecord(record.id);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager()
          .showSuccess(title: 'Đã xóa', message: tr('Xóa bản ghi thành công'));
      _loadRecords();
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message'] ?? 'Xóa thất bại');
    }
  }

  // ==================== SESSION DIALOG ====================

  void _showSessionsDialog() {
    final isMobile = Responsive.isMobile(context);

    Widget buildList() {
      if (_sessions.isEmpty) {
        return Center(child: Text(tr('Chưa có buổi ăn nào')));
      }
      return ListView.builder(
        shrinkWrap: !isMobile,
        physics: isMobile ? null : const NeverScrollableScrollPhysics(),
        itemCount: _sessions.length,
        itemBuilder: (_, i) {
          final s = _sessions[i];
          return ListTile(
            title: Text(tr(s.name)),
            subtitle: Text(
                tr('${s.startTime ?? ''} - ${s.endTime ?? ''}${s.pricePerMeal > 0 ? ' | ${_formatCurrency(s.pricePerMeal)}/suất' : ''}')),
            trailing: Provider.of<PermissionProvider>(context, listen: false)
                    .canDelete('Meal')
                ? IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      Navigator.pop(context);
                      _showDeleteSessionDialog(s);
                    },
                  )
                : null,
          );
        },
      );
    }

    showDialog(
      context: context,
      builder: (ctx) {
        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(tr('Quản lý buổi ăn')),
                leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx)),
                actions: [
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canCreate('Meal'))
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showCreateSessionDialog();
                      },
                    ),
                ],
              ),
              body: buildList(),
            ),
          );
        }

        return ScrollableAlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('Quản lý buổi ăn')),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showCreateSessionDialog();
                },
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            height: 400,
            child: buildList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
          ],
        );
      },
    );
  }
}
