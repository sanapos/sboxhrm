import 'package:flutter/material.dart';

/// Extension trợ giúp lấy TextStyle chuẩn từ theme
/// Sử dụng: context.titleStyle, context.bodyStyle, context.captionStyle...
extension AppTextStyles on BuildContext {
  TextTheme get _tt => Theme.of(this).textTheme;

  // === TIÊU ĐỀ TRANG (AppBar, Header lớn) ===
  /// 20px bold - Tiêu đề AppBar, header trang
  TextStyle get pageTitle => _tt.headlineLarge!;

  /// 18px w600 - Tiêu đề section
  TextStyle get sectionTitle => _tt.headlineMedium!;

  /// 16px w600 - Tiêu đề card, subsection
  TextStyle get cardTitle => _tt.headlineSmall!;

  // === TIÊU ĐỀ NHỎ (item, dialog, row) ===
  /// 18px w600 - Tiêu đề dialog
  TextStyle get dialogTitle => _tt.titleLarge!;

  /// 15px w600 - Tiêu đề item/row
  TextStyle get itemTitle => _tt.titleMedium!;

  /// 14px w600 - Tiêu đề nhỏ
  TextStyle get smallTitle => _tt.titleSmall!;

  // === NỘI DUNG (body) ===
  /// 15px regular - Nội dung chính, paragraph
  TextStyle get bodyLg => _tt.bodyLarge!;

  /// 14px regular - Nội dung thường, text field
  TextStyle get bodyMd => _tt.bodyMedium!;

  /// 13px regular - Nội dung phụ, mô tả
  TextStyle get bodySm => _tt.bodySmall!;

  // === LABEL, BADGE, CAPTION ===
  /// 14px w500 - Label nút, label form
  TextStyle get labelLg => _tt.labelLarge!;

  /// 12px w500 - Label nhỏ, badge, chip
  TextStyle get labelMd => _tt.labelMedium!;

  /// 11px w500 - Caption, timestamp, micro text
  TextStyle get labelSm => _tt.labelSmall!;

  // === SỐ LỚN (dashboard, KPI) ===
  /// 28px bold - Số thống kê lớn
  TextStyle get statLarge => _tt.displayLarge!;

  /// 24px bold - Số thống kê vừa
  TextStyle get statMedium => _tt.displayMedium!;

  /// 22px w600 - Số thống kê nhỏ
  TextStyle get statSmall => _tt.displaySmall!;
}
