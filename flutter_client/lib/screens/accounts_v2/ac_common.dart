import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../utils/permission_role_options.dart';
import '../../widgets/sbox/sbox_ui.dart';

/// Tài khoản đăng nhập (từ GET /api/accounts).
class Account {
  Account(this.m);
  final Map<String, dynamic> m;

  String get id => '${m['id'] ?? ''}';
  String get userName => '${m['userName'] ?? ''}';
  String get email => '${m['email'] ?? ''}';
  String get firstName => '${m['firstName'] ?? ''}';
  String get lastName => '${m['lastName'] ?? ''}';
  String get fullName {
    final f = '${m['fullName'] ?? '$lastName $firstName'}'.trim();
    return f.isEmpty ? (userName.isNotEmpty ? userName : email) : f;
  }

  String? get phone {
    final p = m['phoneNumber']?.toString().trim();
    return p == null || p.isEmpty ? null : p;
  }

  String get role {
    final r = m['roles'];
    if (r is List && r.isNotEmpty) return '${r.first}';
    return '${m['role'] ?? 'Employee'}';
  }

  bool get isActive => m['isActive'] != false;
  bool get isOwner => m['isOwner'] == true;
  String? get employeeId {
    final e = m['employeeId']?.toString();
    return e == null || e.isEmpty ? null : e;
  }

  bool get hrMissing => m['isEmployeeMissing'] == true;
  bool get hrResigned => m['isEmployeeResigned'] == true;
  bool get hrIssue => m['isEmployeeMissingOrResigned'] == true || hrMissing || hrResigned;
  String? get hrIssueLabel => hrMissing
      ? 'Không còn hồ sơ nhân viên'
      : hrResigned
          ? 'Nhân viên đã nghỉ việc'
          : hrIssue
              ? 'Hồ sơ nhân viên có vấn đề'
              : null;

  DateTime? get lastLoginAt => DateTime.tryParse('${m['lastLoginAt'] ?? ''}');
  DateTime? get createdAt => DateTime.tryParse('${m['createdAt'] ?? ''}');

  /// Chữ cái đầu để làm avatar.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[parts.length - 2].characters.first + parts.last.characters.first).toUpperCase();
  }
}

/// Quy tắc vai trò (GET /api/accounts/role-policy) — khớp AccountRolePolicy ở server.
class RolePolicy {
  RolePolicy({
    required this.isOwner,
    required this.myRole,
    required this.assignable,
    required this.ranks,
    this.myUserId,
  });

  /// Khi không gọi được API: chỉ cho phép theo cấp mặc định (server vẫn kiểm lại).
  factory RolePolicy.fallback(String myRole, {String? myUserId}) => RolePolicy(
        isOwner: false,
        myRole: myRole,
        assignable: const [],
        ranks: defaultRanks,
        myUserId: myUserId,
      );

  factory RolePolicy.fromJson(Map<String, dynamic> d, {String? myUserId}) {
    final ranks = <String, int>{...defaultRanks};
    final r = d['ranks'];
    if (r is Map) {
      r.forEach((k, v) {
        if (v is num) ranks['$k'] = v.toInt();
      });
    }
    return RolePolicy(
      isOwner: d['isOwner'] == true,
      myRole: '${d['myRole'] ?? ''}',
      assignable: [for (final x in (d['assignableRoles'] as List? ?? const [])) '$x'],
      ranks: ranks,
      myUserId: myUserId,
    );
  }

  static const defaultRanks = {
    'SuperAdmin': 100, 'Agent': 90, 'Admin': 80, 'Director': 70, 'Manager': 60,
    'DepartmentHead': 50, 'Accountant': 50, 'Cashier': 30, 'Employee': 20, 'Waiter': 20, 'User': 10,
  };

  final bool isOwner;
  final String myRole;
  final List<String> assignable;
  final Map<String, int> ranks;
  final String? myUserId;

  int rankOf(String role) {
    for (final e in ranks.entries) {
      if (e.key.toLowerCase() == role.toLowerCase()) return e.value;
    }
    return 0;
  }

  bool get isSuper => myRole.toLowerCase() == 'superadmin';
  bool canAssign(String role) => assignable.any((r) => r.toLowerCase() == role.toLowerCase());

  /// null = được khóa / đặt lại mật khẩu / đổi vai trò / xóa tài khoản này.
  String? denyManage(Account a) {
    if (a.id == myUserId) return 'Đây là tài khoản của bạn — đổi mật khẩu trong Hồ sơ cá nhân.';
    if (isSuper) return null;
    if (a.isOwner) return 'Tài khoản chủ cửa hàng chỉ chủ cửa hàng tự sửa.';
    if (a.role.toLowerCase() == 'superadmin' || a.role.toLowerCase() == 'agent') return 'Tài khoản quản trị nền tảng.';
    if (isOwner) return null;
    return rankOf(a.role) < rankOf(myRole) ? null : 'Chỉ quản lý được tài khoản có vai trò thấp hơn vai trò của bạn.';
  }
}

/// Tên + màu vai trò.
String roleLabel(String role, [List<PermissionRoleOption> options = const []]) {
  for (final r in options) {
    if (r.name.toLowerCase() == role.toLowerCase()) return r.displayName;
  }
  return PermissionRoleOptions.displayNameOf(role);
}

SboxTone roleTone(String role) => switch (role) {
      'Admin' || 'Director' => SboxTone.violet,
      'Manager' || 'DepartmentHead' || 'Accountant' => SboxTone.brand,
      'Cashier' || 'Waiter' => SboxTone.warning,
      _ => SboxTone.neutral,
    };

/// Mô tả ngắn từng vai trò — giúp chọn đúng khi tạo tài khoản.
String roleHint(String role) => switch (role) {
      'Admin' => 'Toàn quyền như chủ cửa hàng',
      'Director' => 'Điều hành: duyệt, báo cáo, thiết lập',
      'Manager' => 'Quản lý ca, nhân viên, bán hàng',
      'DepartmentHead' => 'Duyệt đơn cho nhân viên phòng mình',
      'Accountant' => 'Lương, thu chi, công nợ, hóa đơn',
      'Cashier' => 'Bán hàng, thu tiền, chốt ca',
      'Waiter' => 'Gọi món, tạm tính — không thu tiền',
      'Employee' => 'Chấm công, xem lương, gửi đơn của mình',
      'User' => 'Chỉ xem trang chủ, thông báo',
      _ => '',
    };

/// Vai trò được giới hạn khu vực bán hàng (Thu ngân / Order / Nhân viên).
const posAreaRoles = {'Cashier', 'Waiter', 'Employee', 'User'};

String agoText(DateTime? d) {
  if (d == null) return 'Chưa đăng nhập';
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inMinutes < 1) return 'Vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays < 30) return '${diff.inDays} ngày trước';
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

/// Mật khẩu ngẫu nhiên dễ đọc (không có 0/O, 1/l).
String randomPassword([int len = 10]) {
  const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = Random.secure();
  return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
}

class AcAvatar extends StatelessWidget {
  const AcAvatar(this.a, {super.key, this.size = 40});
  final Account a;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = a.isActive ? roleTone(a.role) : SboxTone.neutral;
    final (bg, fg) = switch (tone) {
      SboxTone.violet => (SboxColors.violetSoft, SboxColors.violetText),
      SboxTone.brand => (SboxColors.brand50, SboxColors.brand700),
      SboxTone.warning => (SboxColors.warningSoft, SboxColors.warningText),
      _ => (SboxColors.slate100, SboxColors.slate600),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(a.initials, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
  }
}

void acToast(BuildContext context, String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(m)),
      backgroundColor: error ? SboxColors.danger : null,
      behavior: SnackBarBehavior.floating,
    ));
