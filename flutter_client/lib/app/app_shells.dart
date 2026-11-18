import 'package:flutter/widgets.dart';

/// Khung màn chính của từng bản app, gắn từ điểm vào.
///
/// `lib/main.dart` gắn đủ ba khung (HRM, BOSS, Nhân Viên); `lib/main_pos.dart` (SBOX Bán Hàng) **không gắn gì**,
/// nên `main_layout.dart` — tệp 6.000 dòng kéo theo toàn bộ chấm công, lương, nhân sự — không nằm trong gói.
/// Apple từ chối bản POS theo điều 2.5.19 vì quét thấy chính nhóm mã đó.
abstract final class AppShells {
  /// Khung SBOX HRM (`MainLayout`).
  static Widget Function()? hrm;

  /// Khung SBOX BOSS.
  static Widget Function()? boss;

  /// Khung SBOX Nhân Viên.
  static Widget Function()? staff;

  /// Trang hướng dẫn sử dụng trên web (sboxhrm.com/guide) — chứa hàng trăm câu nhắc chấm công / lương,
  /// bản SBOX Bán Hàng trên iOS không có trang này.
  static Widget Function()? landingGuide;

  /// Màn quản trị hệ thống (nạp trễ) — null ở bản SBOX Bán Hàng.
  static Widget Function(bool agentMode)? systemAdmin;
}
