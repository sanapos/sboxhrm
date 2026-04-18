import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/meal.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

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
  String? _filterSessionId;

  // Summary
  List<EmployeeMealSummary> _employeeSummaries = [];
  DateTime _summaryFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _summaryTo = DateTime.now();

  // Menu
  List<MealMenu> _weeklyMenus = [];
  DateTime _menuWeekStart = _getMonday(DateTime.now());

  // Master dish list
  List<MealDish> _masterDishes = [];

  // Debt
  List<MealDebtSummary> _debtSummaries = [];
  List<MealDebt> _debtHistory = [];
  String _debtPeriod = DateFormat('yyyy-MM').format(DateTime.now());
  bool _isLoadingDebt = false;

  // Common
  bool _isLoading = true;

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
      if (!_tabCtl.indexIsChanging) _loadCurrentTab();
    });
    _loadSessions().then((_) {
      _loadMasterDishes();
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
        _sessions =
            list.map((e) => MealSession.fromJson(e as Map<String, dynamic>)).toList();
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
        _masterDishes = list.map((e) => MealDish.fromJson(e as Map<String, dynamic>)).toList();
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
        _weeklyMenus = list.map((e) => MealMenu.fromJson(e as Map<String, dynamic>)).toList();
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
            .map((e) =>
                EmployeeMealSummary.fromJson(e as Map<String, dynamic>))
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
        _debtSummaries = list.map((e) => MealDebtSummary.fromJson(e as Map<String, dynamic>)).toList();
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
        _debtHistory = list.map((e) => MealDebt.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('Load debt history error: $e');
    }
    if (mounted) setState(() => _isLoadingDebt = false);
  }

  Future<void> _doBatchCharge() async {
    try {
      final res = await _apiService.batchChargeMeals(_debtPeriod);
      if (res['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(
          title: 'Tính tiền cơm',
          message: 'Đã tính tiền cơm tháng $_debtPeriod thành công',
        );
        _loadDebtSummary();
      } else {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message'] ?? 'Tính tiền thất bại',
        );
      }
    } catch (e) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
    }
  }

  void _showRecordPaymentDialog(MealDebtSummary debt) {
    final amountCtl = TextEditingController();
    final noteCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Thu tiền - ${debt.employeeName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Công nợ hiện tại: ${_formatCurrency(debt.balance)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền thu *',
                border: OutlineInputBorder(),
                prefixText: '₫ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtl,
              decoration: const InputDecoration(
                labelText: 'Ghi chú',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
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
                    title: 'Thu tiền', message: 'Đã ghi nhận thu ${_formatCurrency(amount)}');
                  _loadDebtSummary();
                } else {
                  NotificationOverlayManager().showError(
                    title: 'Lỗi', message: res['message'] ?? 'Thất bại');
                }
              } catch (e) {
                NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
              }
            },
            child: const Text('Thu tiền'),
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
                  .showSuccess(title: 'Thành công', message: 'Đã tạo buổi ăn');
              _loadSessions();
            } else {
              NotificationOverlayManager()
                  .showError(title: 'Lỗi', message: res['message'] ?? 'Lỗi tạo buổi ăn');
            }
          }

          final formBody = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtl,
                decoration:
                    const InputDecoration(labelText: 'Tên buổi ăn *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtl,
                decoration: const InputDecoration(labelText: 'Mô tả'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Giá mỗi suất (đ)',
                  prefixText: '₫ ',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: const Text('Giờ bắt đầu'),
                trailing: Text(startTime.format(ctx)),
                onTap: () async {
                  final t = await showTimePicker(
                      context: ctx, initialTime: startTime);
                  if (t != null) setDlgState(() => startTime = t);
                },
              ),
              ListTile(
                title: const Text('Giờ kết thúc'),
                trailing: Text(endTime.format(ctx)),
                onTap: () async {
                  final t = await showTimePicker(
                      context: ctx, initialTime: endTime);
                  if (t != null) setDlgState(() => endTime = t);
                },
              ),
            ],
          );

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Thêm buổi ăn'),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton(onPressed: onSave, child: const Text('Lưu')),
                    ),
                  ],
                ),
                body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formBody),
              ),
            );
          }

          return AlertDialog(
            title: const Text('Thêm buổi ăn'),
            content: SingleChildScrollView(child: formBody),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy')),
              FilledButton(onPressed: onSave, child: const Text('Lưu')),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteSessionDialog(MealSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa buổi ăn'),
        content: Text('Bạn có chắc muốn xóa "${session.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final res = await _apiService.deleteMealSession(session.id);
              if (ctx.mounted) Navigator.pop(ctx);
              if (res['isSuccess'] == true) {
                NotificationOverlayManager()
                    .showSuccess(title: 'Thành công', message: 'Đã xóa buổi ăn');
                _loadSessions();
              } else {
                NotificationOverlayManager()
                    .showError(title: 'Lỗi', message: res['message'] ?? 'Lỗi xóa buổi ăn');
              }
            },
            child: const Text('Xóa'),
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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          Future<void> onSave() async {
            if (selectedSessionId == null) return;
            if (selectedDishIds.isEmpty) {
              NotificationOverlayManager().showError(title: 'Lỗi', message: 'Vui lòng chọn ít nhất 1 món');
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
              NotificationOverlayManager().showSuccess(
                  title: 'Thành công', message: 'Đã tạo thực đơn');
              _loadWeeklyMenu();
            } else {
              NotificationOverlayManager().showError(
                  title: 'Lỗi',
                  message: res['message'] ?? 'Lỗi tạo thực đơn');
            }
          }

          // Group dishes by category
          final grouped = <String, List<MealDish>>{};
          for (final d in _masterDishes) {
            final cat = d.category?.isNotEmpty == true ? d.category! : 'Khác';
            grouped.putIfAbsent(cat, () => []).add(d);
          }

          final formBody = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: selectedSessionId,
                decoration: const InputDecoration(labelText: 'Buổi ăn *', border: OutlineInputBorder()),
                items: _sessions.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                onChanged: (v) => setDlgState(() => selectedSessionId = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ngày'),
                trailing: Text(DateFormat('dd/MM/yyyy').format(menuDate)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx, initialDate: menuDate,
                    firstDate: DateTime(2024), lastDate: DateTime(2030),
                  );
                  if (d != null) setDlgState(() => menuDate = d);
                },
              ),
              TextField(
                controller: noteCtl,
                decoration: const InputDecoration(labelText: 'Ghi chú', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Text('Chọn món (${selectedDishIds.length} đã chọn)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              if (_masterDishes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Chưa có món ăn. Vui lòng thêm món trong "Quản lý danh sách món".',
                      style: TextStyle(color: Colors.grey)),
                ),
              ...grouped.entries.map((catEntry) {
                final cat = catEntry.key;
                final dishes = catEntry.value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(cat, style: const TextStyle(
                          fontWeight: FontWeight.w600, color: Color(0xFF0284C7), fontSize: 13)),
                    ),
                    ...dishes.map((dish) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(dish.name, style: const TextStyle(fontSize: 14)),
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
                  title: const Text('Tạo thực đơn'),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton(onPressed: onSave, child: const Text('Lưu')),
                    ),
                  ],
                ),
                body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formBody),
              ),
            );
          }

          return AlertDialog(
            title: const Text('Tạo thực đơn'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(child: formBody),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              FilledButton(onPressed: onSave, child: const Text('Lưu')),
            ],
          );
        },
      ),
    );
  }

  // ==================== DISH MANAGEMENT ====================

  void _showDishManagementDialog() {
    final isMobile = Responsive.isMobile(context);

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

          Widget buildContent() {
            return Column(
              children: [
                // Add button
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: () => _showAddDishDialog(ctx, setDlgState),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm món mới'),
                  ),
                ),
                Expanded(
                  child: _masterDishes.isEmpty
                      ? const Center(child: Text('Chưa có món ăn nào', style: TextStyle(color: Colors.grey)))
                      : ListView(
                          children: grouped.entries.map((catEntry) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  color: const Color(0xFFF0F9FF),
                                  child: Text(catEntry.key,
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                                ),
                                ...catEntry.value.map((dish) => ListTile(
                                  title: Text(dish.name),
                                  subtitle: dish.category != null ? Text(dish.category!, style: const TextStyle(fontSize: 12)) : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 20, color: Color(0xFF3B82F6)),
                                        onPressed: () => _showEditDishDialog(ctx, setDlgState, dish),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                        onPressed: () async {
                                          final res = await _apiService.deleteMealDish(dish.id);
                                          if (res['isSuccess'] == true) {
                                            await _loadMasterDishes();
                                            if (ctx.mounted) setDlgState(() {});
                                          }
                                        },
                                      ),
                                    ],
                                  ),
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
                  title: const Text('Quản lý danh sách món'),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ),
                body: buildContent(),
              ),
            );
          }
          return AlertDialog(
            title: const Text('Quản lý danh sách món'),
            content: SizedBox(width: 450, height: 500, child: buildContent()),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
          );
        },
      ),
    );
  }

  void _showAddDishDialog(BuildContext parentCtx, StateSetter parentSetState) {
    final nameCtl = TextEditingController();
    final categoryCtl = TextEditingController();
    showDialog(
      context: parentCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm món mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Tên món *', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: categoryCtl,
              decoration: const InputDecoration(
                labelText: 'Nhóm (Cơm, Canh, Món mặn, ...)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              if (nameCtl.text.trim().isEmpty) return;
              final res = await _apiService.createMealDish({
                'name': nameCtl.text.trim(),
                'category': categoryCtl.text.trim(),
                'sortOrder': 0,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              if (res['isSuccess'] == true) {
                await _loadMasterDishes();
                if (parentCtx.mounted) parentSetState(() {});
              } else {
                NotificationOverlayManager().showError(title: 'Lỗi', message: res['message'] ?? 'Thất bại');
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _showEditDishDialog(BuildContext parentCtx, StateSetter parentSetState, MealDish dish) {
    final nameCtl = TextEditingController(text: dish.name);
    final categoryCtl = TextEditingController(text: dish.category ?? '');
    showDialog(
      context: parentCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa món'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Tên món *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: categoryCtl,
              decoration: const InputDecoration(labelText: 'Nhóm', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              if (nameCtl.text.trim().isEmpty) return;
              final res = await _apiService.updateMealDish(dish.id, {
                'name': nameCtl.text.trim(),
                'category': categoryCtl.text.trim(),
                'sortOrder': dish.sortOrder,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              if (res['isSuccess'] == true) {
                await _loadMasterDishes();
                if (parentCtx.mounted) parentSetState(() {});
              } else {
                NotificationOverlayManager().showError(title: 'Lỗi', message: res['message'] ?? 'Thất bại');
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
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
      initialDateRange:
          DateTimeRange(start: _summaryFrom, end: _summaryTo),
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

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chấm cơm'),
        bottom: TabBar(
          controller: _tabCtl,
          isScrollable: isMobile,
          tabs: const [
            Tab(icon: Icon(Icons.restaurant), text: 'Tổng quan'),
            Tab(icon: Icon(Icons.list_alt), text: 'Lịch sử'),
            Tab(icon: Icon(Icons.people), text: 'Tổng hợp'),
            Tab(icon: Icon(Icons.menu_book), text: 'Thực đơn'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'Công nợ'),
          ],
        ),
        actions: [
          if (_tabCtl.index == 0 || _tabCtl.index == 1)
            IconButton(
              icon: const Icon(Icons.calendar_today),
              tooltip: 'Chọn ngày',
              onPressed: _pickDate,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'sessions') _showSessionsDialog();
              if (v == 'dishes') _showDishManagementDialog();
              if (v == 'createMenu') _showCreateMenuDialog();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'sessions', child: Text('Quản lý buổi ăn')),
              if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Meal'))
              const PopupMenuItem(
                  value: 'dishes', child: Text('Quản lý danh sách món')),
              if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Meal'))
              const PopupMenuItem(
                  value: 'createMenu', child: Text('Tạo thực đơn')),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabCtl,
        children: [
          _buildDashboardTab(),
          _buildRecordsTab(),
          _buildSummaryTab(),
          _buildMenuTab(),
          _buildDebtTab(),
        ],
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
            Text(
              'Chưa có dữ liệu cho ngày ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadEstimate,
              child: const Text('Tải lại'),
            ),
          ],
        ),
      );
    }
    final summary = _mealSummary!;
    return RefreshIndicator(
      onRefresh: _loadEstimate,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Date header
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today, color: Color(0xFF0284C7)),
              title: Text(
                DateFormat('EEEE, dd/MM/yyyy', 'vi').format(summary.date),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                  'Ước tính: ${summary.totalEstimated} | Thực tế: ${summary.totalActual}'),
            ),
          ),
          const SizedBox(height: 16),
          // Overall summary cards
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
                  const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryCard(
                  'Còn lại',
                  (summary.totalEstimated - summary.totalActual).toString(),
                  Icons.hourglass_bottom,
                  const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Chi tiết theo buổi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...summary.sessions.map(_buildSessionCard),
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
            Text(value,
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(MealEstimate est) {
    final percent = est.estimatedCount > 0
        ? (est.actualCount / est.estimatedCount).clamp(0.0, 1.0)
        : 0.0;
    // Find today's menu for this session
    final todayMenus = _weeklyMenus.where((m) =>
        m.mealSessionId == est.mealSessionId &&
        m.date.year == _selectedDate.year &&
        m.date.month == _selectedDate.month &&
        m.date.day == _selectedDate.day).toList();

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
                Text(est.mealSessionName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  '${est.startTime ?? ''} - ${est.endTime ?? ''}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            if (est.pricePerMeal > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Giá: ${_formatCurrency(est.pricePerMeal)}/suất',
                    style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13)),
              ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(
                    percent < 0.7 ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _miniStat('Đăng ký', est.registeredCount.toString(), const Color(0xFF8B5CF6)),
                const SizedBox(width: 12),
                _miniStat('Ước tính', est.estimatedCount.toString(), const Color(0xFF3B82F6)),
                const SizedBox(width: 12),
                _miniStat('Thực tế', est.actualCount.toString(), const Color(0xFF10B981)),
                const SizedBox(width: 12),
                _miniStat('Còn', est.remaining.toString(), const Color(0xFFF59E0B)),
              ],
            ),
            // Today's menu inline
            if (todayMenus.isNotEmpty) ...[
              const Divider(height: 20),
              const Text('🍽️ Thực đơn hôm nay',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0284C7))),
              const SizedBox(height: 4),
              ...todayMenus.expand((menu) => menu.items.map((item) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 5, color: Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Text(item.dishName, style: const TextStyle(fontSize: 13)),
                        if (item.category != null && item.category!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text('(${item.category})',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  // ==================== TAB 2: RECORDS ====================

  Widget _buildRecordsTab() {
    return Column(
      children: [
        // Filters
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Ngày', border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  child: InkWell(
                    onTap: _pickDate,
                    child: Text(
                        DateFormat('dd/MM/yyyy').format(_selectedDate)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _filterSessionId,
                  decoration: const InputDecoration(
                      labelText: 'Buổi ăn', border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tất cả')),
                    ..._sessions.map((s) =>
                        DropdownMenuItem(value: s.id, child: Text(s.name))),
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
            ],
          ),
        ),
        // Records list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _records.isEmpty
                  ? const Center(
                      child: Text('Chưa có dữ liệu chấm cơm',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _records.length,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemBuilder: (_, i) {
                        final r = _records[i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF10B981),
                              child: Text(
                                r.employeeName.isNotEmpty
                                    ? r.employeeName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(r.employeeName),
                            subtitle: Text(
                              '${r.mealSessionName ?? ''} | ${DateFormat('HH:mm').format(r.mealTime)}',
                            ),
                            trailing: Text(
                              r.deviceName ?? r.pin ?? '',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        );
                      },
                    ),
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
                Text('Trang $_currentPage / $_totalPages'),
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

  // ==================== TAB 3: SUMMARY ====================

  Widget _buildSummaryTab() {
    return Column(
      children: [
        // Date range filter
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickSummaryRange,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Khoảng thời gian',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    child: Text(
                      '${DateFormat('dd/MM/yyyy').format(_summaryFrom)} - ${DateFormat('dd/MM/yyyy').format(_summaryTo)}',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Xem'),
                onPressed: _loadEmployeeSummary,
              ),
            ],
          ),
        ),
        // Summary table
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _employeeSummaries.isEmpty
                  ? const Center(
                      child: Text('Chưa có dữ liệu',
                          style: TextStyle(color: Colors.grey)))
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('STT')),
                            DataColumn(label: Text('Mã NV')),
                            DataColumn(label: Text('Họ tên')),
                            DataColumn(label: Text('Tổng suất'), numeric: true),
                            DataColumn(label: Text('Tiền cơm'), numeric: true),
                            DataColumn(label: Text('Đã trả'), numeric: true),
                            DataColumn(label: Text('Còn nợ'), numeric: true),
                          ],
                          rows: _employeeSummaries
                              .asMap()
                              .entries
                              .map((entry) {
                            final i = entry.key;
                            final s = entry.value;
                            return DataRow(
                              cells: [
                                DataCell(Text('${i + 1}')),
                                DataCell(Text(s.employeeCode ?? '')),
                                DataCell(Text(s.employeeName)),
                                DataCell(Text(s.totalMeals.toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold))),
                                DataCell(Text(_formatCurrency(s.totalCost))),
                                DataCell(Text(_formatCurrency(s.totalPaid),
                                    style: const TextStyle(color: Color(0xFF10B981)))),
                                DataCell(Text(_formatCurrency(s.balance),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: s.balance > 0 ? Colors.red : const Color(0xFF10B981)))),
                              ],
                              onSelectChanged: (_) =>
                                  _showEmployeeDetail(s),
                            );
                          }).toList(),
                        ),
                      ),
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
                Text('${_employeeSummaries.length} NV',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  'Suất: ${_employeeSummaries.fold<int>(0, (sum, e) => sum + e.totalMeals)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                ),
                Text(
                  'Nợ: ${_formatCurrency(_employeeSummaries.fold<double>(0, (sum, e) => sum + e.balance))}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
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
        return const Center(child: Text('Không có chi tiết'));
      }
      return ListView.builder(
        shrinkWrap: !isMobile,
        physics: isMobile ? null : const NeverScrollableScrollPhysics(),
        itemCount: emp.details.length,
        itemBuilder: (_, i) {
          final d = emp.details[i];
          return ListTile(
            leading: const Icon(Icons.restaurant,
                color: Color(0xFF10B981)),
            title: Text(d.mealSessionName),
            subtitle: Text(
                DateFormat('dd/MM/yyyy').format(d.date)),
            trailing: Text(
                DateFormat('HH:mm').format(d.mealTime)),
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
                title: Text(emp.employeeName),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ),
              body: buildList(),
            ),
          );
        }

        return AlertDialog(
          title: Text(emp.employeeName),
          content: SizedBox(
            width: 400,
            height: 400,
            child: buildList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng')),
          ],
        );
      },
    );
  }

  // ==================== TAB 4: MENU ====================

  Widget _buildMenuTab() {
    return Column(
      children: [
        // Week navigation
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() => _menuWeekStart =
                      _menuWeekStart.subtract(const Duration(days: 7)));
                  _loadWeeklyMenu();
                },
              ),
              Text(
                'Tuần ${DateFormat('dd/MM').format(_menuWeekStart)} - ${DateFormat('dd/MM/yyyy').format(_menuWeekStart.add(const Duration(days: 6)))}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _weeklyMenus.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.menu_book,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('Chưa có thực đơn cho tuần này',
                              style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Tạo thực đơn'),
                            onPressed: _showCreateMenuDialog,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: 7,
                      itemBuilder: (_, dayIndex) {
                        final dayDate = _menuWeekStart
                            .add(Duration(days: dayIndex));
                        final dayMenus = _weeklyMenus
                            .where((m) =>
                                m.date.year == dayDate.year &&
                                m.date.month == dayDate.month &&
                                m.date.day == dayDate.day)
                            .toList();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: dayDate.day ==
                                          DateTime.now().day &&
                                      dayDate.month ==
                                          DateTime.now().month
                                  ? const Color(0xFF0284C7)
                                  : Colors.grey[300],
                              child: Text(
                                '${dayDate.day}',
                                style: TextStyle(
                                  color: dayDate.day ==
                                              DateTime.now().day &&
                                          dayDate.month ==
                                              DateTime.now().month
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                            ),
                            title: Text(
                              _dayNames[dayIndex],
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              dayMenus.isEmpty
                                  ? 'Chưa có thực đơn'
                                  : '${dayMenus.length} buổi',
                            ),
                            children: dayMenus.isEmpty
                                ? [
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(
                                          'Chưa có thực đơn cho ngày này',
                                          style: TextStyle(
                                              color: Colors.grey)),
                                    )
                                  ]
                                : dayMenus
                                    .map((menu) => Padding(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 8),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                menu.mealSessionName ??
                                                    'Buổi ăn',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color:
                                                        Color(0xFF0284C7)),
                                              ),
                                              if (menu.note != null &&
                                                  menu.note!.isNotEmpty)
                                                Text(menu.note!,
                                                    style: const TextStyle(
                                                        fontStyle: FontStyle
                                                            .italic,
                                                        color:
                                                            Colors.grey)),
                                              const SizedBox(height: 4),
                                              ...menu.items.map(
                                                (item) => Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 8,
                                                          bottom: 2),
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                          Icons
                                                              .circle,
                                                          size: 6,
                                                          color: Color(
                                                              0xFF10B981)),
                                                      const SizedBox(
                                                          width: 8),
                                                      Expanded(
                                                        child: Text(
                                                            item.dishName),
                                                      ),
                                                      if (item.category !=
                                                              null &&
                                                          item.category!
                                                              .isNotEmpty)
                                                        Container(
                                                          padding: const EdgeInsets
                                                              .symmetric(
                                                              horizontal: 6,
                                                              vertical: 2),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                    0xFF10B981)
                                                                .withValues(
                                                                    alpha: 0.1),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                          child: Text(
                                                            item.category!,
                                                            style: const TextStyle(
                                                                fontSize:
                                                                    12,
                                                                color: Color(
                                                                    0xFF10B981)),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const Divider(),
                                            ],
                                          ),
                                        ))
                                    .toList(),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ==================== TAB 5: DEBT ====================

  Widget _buildDebtTab() {
    final canManage = Provider.of<PermissionProvider>(context, listen: false).canCreate('Meal');
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
                  if (m < 1) { m = 12; y--; }
                  setState(() => _debtPeriod = '$y-${m.toString().padLeft(2, '0')}');
                  _loadDebtSummary();
                },
              ),
              Expanded(
                child: Text(
                  'Tháng $_debtPeriod',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  final parts = _debtPeriod.split('-');
                  var y = int.parse(parts[0]);
                  var m = int.parse(parts[1]) + 1;
                  if (m > 12) { m = 1; y++; }
                  setState(() => _debtPeriod = '$y-${m.toString().padLeft(2, '0')}');
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
                        builder: (ctx) => AlertDialog(
                          title: const Text('Tính tiền cơm'),
                          content: Text('Tự động tính tiền cơm cho tất cả nhân viên tháng $_debtPeriod dựa trên số suất ăn thực tế?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                            FilledButton(
                              onPressed: () { Navigator.pop(ctx); _doBatchCharge(); },
                              child: const Text('Xác nhận'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.calculate),
                    label: const Text('Tính tiền cơm tháng'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
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
        // Debt summary table
        Expanded(
          child: _isLoadingDebt
              ? const Center(child: CircularProgressIndicator())
              : _debtSummaries.isEmpty
                  ? const Center(child: Text('Chưa có dữ liệu công nợ', style: TextStyle(color: Colors.grey)))
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('STT')),
                            DataColumn(label: Text('Mã NV')),
                            DataColumn(label: Text('Họ tên')),
                            DataColumn(label: Text('Số suất'), numeric: true),
                            DataColumn(label: Text('Tiền cơm'), numeric: true),
                            DataColumn(label: Text('Đã trả'), numeric: true),
                            DataColumn(label: Text('Còn nợ'), numeric: true),
                            DataColumn(label: Text('')),
                          ],
                          rows: _debtSummaries.asMap().entries.map((entry) {
                            final i = entry.key;
                            final d = entry.value;
                            return DataRow(
                              cells: [
                                DataCell(Text('${i + 1}')),
                                DataCell(Text(d.employeeCode ?? '')),
                                DataCell(Text(d.employeeName)),
                                DataCell(Text(d.totalMeals.toString())),
                                DataCell(Text(_formatCurrency(d.totalCharged))),
                                DataCell(Text(_formatCurrency(d.totalPaid),
                                    style: const TextStyle(color: Color(0xFF10B981)))),
                                DataCell(Text(_formatCurrency(d.balance),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: d.balance > 0 ? Colors.red : const Color(0xFF10B981)))),
                                DataCell(Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (canManage && d.balance > 0)
                                      IconButton(
                                        icon: const Icon(Icons.payment, color: Color(0xFF10B981), size: 20),
                                        tooltip: 'Thu tiền',
                                        onPressed: () => _showRecordPaymentDialog(d),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.history, color: Color(0xFF3B82F6), size: 20),
                                      tooltip: 'Lịch sử',
                                      onPressed: () => _showDebtHistoryDialog(d),
                                    ),
                                  ],
                                )),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
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
                Text('${_debtSummaries.length} NV',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  'Tổng nợ: ${_formatCurrency(_debtSummaries.fold<double>(0, (sum, e) => sum + e.balance))}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
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
        return const Center(child: Text('Chưa có giao dịch'));
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
              backgroundColor: isPayment ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              child: Icon(isPayment ? Icons.arrow_downward : Icons.arrow_upward,
                  color: Colors.white, size: 18),
            ),
            title: Text(
              '${isPayment ? "Thu tiền" : "Tính cơm"}: ${_formatCurrency(d.amount)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isPayment ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
            ),
            subtitle: Text(
              '${DateFormat('dd/MM/yyyy').format(d.date)}${d.note != null && d.note!.isNotEmpty ? ' - ${d.note}' : ''}',
            ),
            trailing: Text(d.recordedByName ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
                title: Text('Công nợ - ${debt.employeeName}'),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
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
                          Text(_formatCurrency(debt.totalCharged), style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Text('Tiền cơm', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ]),
                        Column(children: [
                          Text(_formatCurrency(debt.totalPaid), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                          const Text('Đã trả', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ]),
                        Column(children: [
                          Text(_formatCurrency(debt.balance), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                          const Text('Còn nợ', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
        return AlertDialog(
          title: Text('Công nợ - ${debt.employeeName}'),
          content: SizedBox(width: 400, height: 400, child: buildList()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        );
      },
    );
  }

  // ==================== SESSION DIALOG ====================

  void _showSessionsDialog() {
    final isMobile = Responsive.isMobile(context);

    Widget buildList() {
      if (_sessions.isEmpty) {
        return const Center(child: Text('Chưa có buổi ăn nào'));
      }
      return ListView.builder(
        shrinkWrap: !isMobile,
        physics: isMobile ? null : const NeverScrollableScrollPhysics(),
        itemCount: _sessions.length,
        itemBuilder: (_, i) {
          final s = _sessions[i];
          return ListTile(
            title: Text(s.name),
            subtitle: Text(
                '${s.startTime ?? ''} - ${s.endTime ?? ''}${s.pricePerMeal > 0 ? ' | ${_formatCurrency(s.pricePerMeal)}/suất' : ''}'),
            trailing: Provider.of<PermissionProvider>(context, listen: false).canDelete('Meal') ? IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                Navigator.pop(context);
                _showDeleteSessionDialog(s);
              },
            ) : null,
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
                title: const Text('Quản lý buổi ăn'),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                actions: [
                  if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Meal'))
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

        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Quản lý buổi ăn'),
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng')),
          ],
        );
      },
    );
  }
}
