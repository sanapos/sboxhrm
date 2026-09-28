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

/// Chi nhánh đang thao tác của phiên làm việc: bán hàng, nhập / xuất kho, thu chi đều gắn chi nhánh này.
/// Lưu lựa chọn trên máy; server luôn kiểm quyền lại.
class BranchSession extends ChangeNotifier {
  BranchSession._();
  static final BranchSession instance = BranchSession._();

  static const _prefKey = 'branch_session_current';

  bool usesBranches = false;
  bool canSeeAll = true;
  String? headquarterId;
  String? currentId;
  List<BranchOption> branches = const [];
  bool _loaded = false;

  bool get loaded => _loaded;

  /// Có nên hiện bộ chọn chi nhánh (dùng chi nhánh và có ≥ 2 chi nhánh được phép).
  bool get showSwitcher => usesBranches && branches.length > 1;

  BranchOption? get current {
    for (final b in branches) {
      if (b.id == currentId) return b;
    }
    return null;
  }

  String nameOf(String? id) {
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
      final valid = branches.map((b) => b.id).toSet();
      final serverCurrent = d['currentBranchId']?.toString();
      currentId = (saved != null && valid.contains(saved))
          ? saved
          : (serverCurrent != null && valid.contains(serverCurrent) ? serverCurrent : (branches.isNotEmpty ? branches.first.id : null));
      ApiService.currentBranchId = currentId;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> select(String id) async {
    if (id == currentId) return;
    currentId = id;
    ApiService.currentBranchId = id;
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
