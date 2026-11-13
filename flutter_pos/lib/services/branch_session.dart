/// Chi nhánh đang xem — bản rút gọn cho SBOX POS Android 6.
///
/// Bản Android 7 (flutter_client) đổi chi nhánh qua [ApiService.currentBranchId]; flutter_pos chưa có
/// bộ chọn chi nhánh nên luôn coi như một chi nhánh (ẩn phần «tồn theo chi nhánh», «Thêm chi nhánh»).
class BranchOption {
  const BranchOption({required this.id, required this.name});
  final String id;
  final String name;
}

class BranchSession {
  BranchSession._();
  static final BranchSession instance = BranchSession._();

  static const allId = '__all__';

  bool usesBranches = false;
  bool canSeeAll = true;
  String? headquarterId;
  String? currentId;
  List<BranchOption> branches = const [];

  bool get loaded => false;
  bool get showSwitcher => false;
  bool get isAll => false;
  String? get viewBranchId => null;
  String? get writeBranchId => null;
  String get currentLabel => 'Chi nhánh';
  BranchOption? get current => null;
}
