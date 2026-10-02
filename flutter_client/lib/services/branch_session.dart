import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Một chi nhánh người dùng được thao tác.
class BranchOption {
  const BranchOption({
    required this.id,
    required this.code,
    required this.name,
    required this.isHeadquarter,
    required this.isActive,
  });

  final String id;
  final String code;
  final String name;
  final bool isHeadquarter;
  final bool isActive;

  factory BranchOption.fromJson(Map m) => BranchOption(
        id: m['id']?.toString() ?? '',
        code: m['code']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        isHeadquarter: m['isHeadquarter'] == true,
        isActive: m['isActive'] != false,
      );
}

/// Chi nhánh đang làm việc của phiên: vừa là chi nhánh XEM dữ liệu (mọi màn hình lọc theo nó,
/// server tự lọc qua header X-Branch-Id) vừa là chi nhánh THAO TÁC (bán hàng, kho, thu chi gắn vào nó).
/// [allId] = "Tất cả chi nhánh": xem gộp; khi ghi dùng trụ sở / chi nhánh mặc định ([writeBranchId]).
/// Lưu lựa chọn trên máy; server luôn kiểm quyền lại.
class BranchSession extends ChangeNotifier {
  BranchSession._();
  static final BranchSession instance = BranchSession._();

  static const _prefKey = 'branch_session_current';

  /// Giá trị đặc biệt: đang xem tất cả chi nhánh được phép.
  static const allId = '__all__';

  bool usesBranches = false;
  bool canSeeAll = true;
  String? headquarterId;
  String? currentId;
  List<BranchOption> branches = const [];
  bool _loaded = false;

  bool get loaded => _loaded;

  /// Có nên hiện bộ chọn chi nhánh (dùng chi nhánh và có ≥ 2 chi nhánh được phép).
  bool get showSwitcher => usesBranches && branches.length > 1;

  /// Đang xem tất cả chi nhánh.
  bool get isAll => usesBranches && currentId == allId;

  /// Chi nhánh lọc dữ liệu XEM — null = không lọc (chưa dùng chi nhánh / đang xem tất cả).
  String? get viewBranchId => usesBranches && !isAll ? currentId : null;

  /// Chi nhánh ghi chứng từ — khi đang xem tất cả thì dùng trụ sở (hoặc chi nhánh đầu tiên).
  String? get writeBranchId {
    if (!usesBranches) return null;
    if (!isAll) return currentId;
    if (headquarterId != null && branches.any((b) => b.id == headquarterId)) return headquarterId;
    return branches.isNotEmpty ? branches.first.id : null;
  }

  /// Tên hiển thị của lựa chọn hiện tại ("Tất cả chi nhánh" hoặc tên chi nhánh).
  String get currentLabel => isAll ? 'Tất cả chi nhánh' : (current?.name ?? 'Chọn chi nhánh');

  BranchOption? get current {
    for (final b in branches) {
      if (b.id == currentId) return b;
    }
    return null;
  }

  String nameOf(String? id) {
    if (id == allId) return 'Tất cả chi nhánh';
    for (final b in branches) {
      if (b.id == id) return b.name;
    }
    return '—';
  }

  /// Tải ngữ cảnh chi nhánh sau khi đăng nhập / đổi cửa hàng.
  Future<void> load() async {
    final r = await ApiService().getBranchContext();
    final d = r['data'];
    if (r['isSuccess'] != true || d is! Map) {
      _loaded = true;
      notifyListeners();
      return;
    }
    usesBranches = d['usesBranches'] == true;
    canSeeAll = d['canSeeAllBranches'] != false;
    headquarterId = d['headquarterBranchId']?.toString();
    branches = [
      for (final b in (d['branches'] as List? ?? const []))
        if (b is Map) BranchOption.fromJson(b),
    ];
    if (!usesBranches) {
      currentId = null;
      ApiService.currentBranchId = null;
    } else {
      String? saved;
      try {
        saved = (await SharedPreferences.getInstance()).getString(_prefKey);
      } catch (_) {}
      currentId = resolveInitial(
        saved: saved,
        serverCurrent: d['currentBranchId']?.toString(),
        branchIds: branches.map((b) => b.id).toList(),
        canSeeAll: canSeeAll,
      );
      ApiService.currentBranchId = _header(currentId);
    }
    _loaded = true;
    notifyListeners();
  }

  /// Mặc định khi mở app: lựa chọn đã lưu (còn hợp lệ) → người xem toàn cửa hàng: tất cả chi nhánh →
  /// chi nhánh của mình (server trả) → chi nhánh đầu tiên.
  @visibleForTesting
  static String? resolveInitial({
    required String? saved,
    required String? serverCurrent,
    required List<String> branchIds,
    required bool canSeeAll,
  }) {
    final multi = branchIds.length > 1;
    if (saved == allId && multi) return allId;
    if (saved != null && branchIds.contains(saved)) return saved;
    if (canSeeAll && multi) return allId;
    if (serverCurrent != null && branchIds.contains(serverCurrent)) return serverCurrent;
    return branchIds.isNotEmpty ? branchIds.first : null;
  }

  static String? _header(String? id) => id == allId ? 'all' : id;

  Future<void> select(String id) async {
    if (id == currentId) return;
    currentId = id;
    ApiService.currentBranchId = _header(id);
    try {
      await (await SharedPreferences.getInstance()).setString(_prefKey, id);
    } catch (_) {}
    notifyListeners();
  }

  void clear() {
    usesBranches = false;
    branches = const [];
    currentId = null;
    headquarterId = null;
    ApiService.currentBranchId = null;
    _loaded = false;
    notifyListeners();
  }
}
