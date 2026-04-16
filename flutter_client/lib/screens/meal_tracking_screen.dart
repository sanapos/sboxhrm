import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/meal.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';

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

  // Registration
  List<MealRegistration> _myRegistrations = [];
  DateTime _regWeekStart = _getMonday(DateTime.now());
  bool _isLoadingReg = false;
  // ignore: unused_field
  RegistrationSummary? _regSummary;
  // ignore: unused_field
  bool _isManager = false;

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
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    _isManager = user?.role == 'Admin' || user?.role == 'Manager' || user?.role == 'Director';
    _tabCtl = TabController(length: 5, vsync: this);
    _tabCtl.addListener(() {
      if (!_tabCtl.indexIsChanging) _loadCurrentTab();
    });
    _loadSessions().then((_) => _loadCurrentTab());
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
        _loadRegistrations();
        break;
      case 3:
        _loadEmployeeSummary();
        break;
      case 4:
        _loadWeeklyMenu();
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

  Future<void> _loadEstimate() async {
    setState(() => _isLoading = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final res = await _apiService.getMealEstimate(date: dateStr);
      if (res['isSuccess'] == true && res['data'] != null) {
        _mealSummary =
            MealSummary.fromJson(res['data'] as Map<String, dynamic>);
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

  Future<void> _loadRegistrations() async {
    setState(() => _isLoadingReg = true);
    try {
      final from = _regWeekStart;
      final to = _regWeekStart.add(const Duration(days: 6));
      final res = await _apiService.getMyMealRegistrations(
        fromDate: from,
        toDate: to,
      );
      if (res['isSuccess'] == true && res['data'] != null) {
        final list = res['data'] as List? ?? [];
        _myRegistrations = list
            .map((e) => MealRegistration.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Load registrations error: $e');
    }
    if (mounted) setState(() => _isLoadingReg = false);
  }

  Future<void> _toggleRegistration(String mealSessionId, DateTime date, bool register) async {
    try {
      final res = await _apiService.registerMeal({
        'mealSessionId': mealSessionId,
        'date': DateFormat('yyyy-MM-dd').format(date),
        'isRegistered': register,
      });
      if (res['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(
          title: 'Đăng ký cơm',
          message: register ? 'Đã đăng ký cơm' : 'Đã hủy đăng ký',
        );
        _loadRegistrations();
      } else {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message'] ?? 'Thao tác thất bại',
        );
      }
    } catch (e) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
    }
  }

  Future<void> _batchRegisterWeek(bool register) async {
    if (_sessions.isEmpty) return;
    final registrations = <Map<String, dynamic>>[];
    for (int i = 0; i < 7; i++) {
      final day = _regWeekStart.add(Duration(days: i));
      if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) continue;
      for (final s in _sessions) {
        registrations.add({
          'mealSessionId': s.id,
          'date': DateFormat('yyyy-MM-dd').format(day),
          'isRegistered': register,
        });
      }
    }
    try {
      final res = await _apiService.batchRegisterMeal(registrations);
      if (res['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(
          title: 'Đăng ký cơm',
          message: register ? 'Đăng ký cả tuần thành công' : 'Hủy đăng ký cả tuần',
        );
        _loadRegistrations();
      } else {
        NotificationOverlayManager().showError(title: 'Lỗi', message: res['message'] ?? 'Thất bại');
      }
    } catch (e) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
    }
  }

  void _showQrCheckInDialog() {
    String? selectedSessionId;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Chấm cơm bằng QR'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.qr_code_scanner, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text('Chọn buổi ăn và xác nhận chấm cơm'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedSessionId,
                decoration: const InputDecoration(
                  labelText: 'Buổi ăn',
                  border: OutlineInputBorder(),
                ),
                items: _sessions
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text('${s.name} (${s.startTime} - ${s.endTime})'),
                        ))
                    .toList(),
                onChanged: (v) => setDlgState(() => selectedSessionId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            FilledButton.icon(
              onPressed: selectedSessionId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      try {
                        final res = await _apiService.qrMealCheckIn(
                          mealSessionId: selectedSessionId!,
                          qrCode: 'MOBILE_CHECKIN',
                        );
                        if (res['isSuccess'] == true) {
                          NotificationOverlayManager().showSuccess(
                              title: 'Chấm cơm', message: 'Chấm cơm thành công!');
                          _loadEstimate();
                        } else {
                          NotificationOverlayManager().showError(
                              title: 'Lỗi', message: res['message'] ?? 'Chấm cơm thất bại');
                        }
                      } catch (e) {
                        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
                      }
                    },
              icon: const Icon(Icons.check),
              label: const Text('Xác nhận chấm cơm'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== SESSION MANAGEMENT ====================

  void _showCreateSessionDialog() {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
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
    final List<Map<String, TextEditingController>> dishControllers = [
      {
        'name': TextEditingController(),
        'desc': TextEditingController(),
        'category': TextEditingController(),
      }
    ];
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          Future<void> onSave() async {
            if (selectedSessionId == null) return;
            final items = dishControllers
                .where((c) => c['name']!.text.trim().isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => {
                      'dishName': entry.value['name']!.text.trim(),
                      'description': entry.value['desc']!.text.trim(),
                      'category': entry.value['category']!.text.trim(),
                      'sortOrder': entry.key,
                    })
                .toList();
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

          final formBody = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedSessionId,
                decoration:
                    const InputDecoration(labelText: 'Buổi ăn *'),
                items: _sessions
                    .map((s) => DropdownMenuItem(
                        value: s.id, child: Text(s.name)))
                    .toList(),
                onChanged: (v) =>
                    setDlgState(() => selectedSessionId = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ngày'),
                trailing: Text(
                    DateFormat('dd/MM/yyyy').format(menuDate)),
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
                decoration: const InputDecoration(labelText: 'Ghi chú'),
              ),
              const SizedBox(height: 16),
              const Text('Món ăn',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...dishControllers.asMap().entries.map((entry) {
                final i = entry.key;
                final ctrls = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: ctrls['name'],
                                decoration: InputDecoration(
                                    labelText: 'Tên món ${i + 1} *'),
                              ),
                            ),
                            if (dishControllers.length > 1)
                              IconButton(
                                icon: const Icon(Icons.remove_circle,
                                    color: Colors.red),
                                onPressed: () => setDlgState(
                                    () => dishControllers.removeAt(i)),
                              ),
                          ],
                        ),
                        TextField(
                          controller: ctrls['desc'],
                          decoration:
                              const InputDecoration(labelText: 'Mô tả'),
                        ),
                        TextField(
                          controller: ctrls['category'],
                          decoration: const InputDecoration(
                              labelText: 'Loại (Cơm, Canh, ...)'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Thêm món'),
                onPressed: () => setDlgState(() =>
                    dishControllers.add({
                      'name': TextEditingController(),
                      'desc': TextEditingController(),
                      'category': TextEditingController(),
                    })),
              ),
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
            Tab(icon: Icon(Icons.how_to_reg), text: 'Đăng ký'),
            Tab(icon: Icon(Icons.people), text: 'Tổng hợp'),
            Tab(icon: Icon(Icons.menu_book), text: 'Thực đơn'),
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
              if (v == 'createMenu') _showCreateMenuDialog();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'sessions', child: Text('Quản lý buổi ăn')),
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
          _buildRegistrationTab(),
          _buildSummaryTab(),
          _buildMenuTab(),
        ],
      ),
      floatingActionButton: _tabCtl.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showQrCheckInDialog,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Chấm cơm'),
              backgroundColor: Colors.orange,
            )
          : null,
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Ước tính: ${est.estimatedCount}'),
                Text('Thực tế: ${est.actualCount}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Còn: ${est.remaining}',
                    style:
                        TextStyle(color: est.remaining > 0 ? const Color(0xFFF59E0B) : Colors.grey)),
              ],
            ),
          ],
        ),
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
                            DataColumn(label: Text('Tổng suất ăn'), numeric: true),
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
                Text('Tổng: ${_employeeSummaries.length} nhân viên',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  'Tổng suất ăn: ${_employeeSummaries.fold<int>(0, (sum, e) => sum + e.totalMeals)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0284C7)),
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

  // ==================== TAB 3: REGISTRATION ====================

  Widget _buildRegistrationTab() {
    final days = List.generate(7, (i) => _regWeekStart.add(Duration(days: i)));
    final dayFmt = DateFormat('EEE dd/MM', 'vi');

    return Column(
      children: [
        // Week navigation + batch actions
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() => _regWeekStart =
                      _regWeekStart.subtract(const Duration(days: 7)));
                  _loadRegistrations();
                },
              ),
              Expanded(
                child: Text(
                  '${DateFormat('dd/MM').format(_regWeekStart)} - ${DateFormat('dd/MM').format(_regWeekStart.add(const Duration(days: 6)))}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() => _regWeekStart =
                      _regWeekStart.add(const Duration(days: 7)));
                  _loadRegistrations();
                },
              ),
            ],
          ),
        ),
        // Batch buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _batchRegisterWeek(true),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Đăng ký cả tuần'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _batchRegisterWeek(false),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  label: const Text('Hủy cả tuần'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Registration grid
        Expanded(
          child: _isLoadingReg
              ? const Center(child: CircularProgressIndicator())
              : _sessions.isEmpty
                  ? const Center(child: Text('Chưa có buổi ăn nào'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: days.length,
                      itemBuilder: (context, dayIndex) {
                        final day = days[dayIndex];
                        final isWeekend = day.weekday == DateTime.saturday ||
                            day.weekday == DateTime.sunday;
                        final isToday = DateFormat('yyyy-MM-dd').format(day) ==
                            DateFormat('yyyy-MM-dd').format(DateTime.now());

                        return Card(
                          color: isWeekend
                              ? Colors.grey.shade100
                              : isToday
                                  ? Colors.orange.shade50
                                  : null,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isToday
                                          ? Icons.today
                                          : Icons.calendar_today,
                                      size: 18,
                                      color: isToday
                                          ? Colors.orange
                                          : Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      dayFmt.format(day),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isWeekend
                                            ? Colors.grey
                                            : isToday
                                                ? Colors.orange.shade800
                                                : null,
                                      ),
                                    ),
                                    if (isToday)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text('Hôm nay',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10)),
                                      ),
                                  ],
                                ),
                                if (!isWeekend) ...[
                                  const SizedBox(height: 8),
                                  ..._sessions.map((session) {
                                    final reg = _myRegistrations.where((r) =>
                                        r.mealSessionId == session.id &&
                                        r.date.year == day.year &&
                                        r.date.month == day.month &&
                                        r.date.day == day.day);
                                    final isRegistered = reg.isNotEmpty &&
                                        reg.first.isRegistered;

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${session.name} (${session.startTime} - ${session.endTime})',
                                              style:
                                                  const TextStyle(fontSize: 13),
                                            ),
                                          ),
                                          Switch(
                                            value: isRegistered,
                                            activeTrackColor: Colors.green.shade200,
                                            onChanged: (val) =>
                                                _toggleRegistration(
                                                    session.id, day, val),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
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
                '${s.startTime ?? ''} - ${s.endTime ?? ''}'),
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
