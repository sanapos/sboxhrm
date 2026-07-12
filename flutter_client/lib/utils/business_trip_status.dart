import 'package:flutter/material.dart';

/// Parse status từ API (int / string / enum name) — tránh cast cứng gây crash widget library.
/// Khớp `BusinessTripCaseStatus` backend:
/// Draft=0 … Closed=8, Cancelled=9.
int? parseTripStatus(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final asInt = int.tryParse(s);
  if (asInt != null) return asInt;
  switch (s.toLowerCase()) {
    case 'draft':
      return 0;
    case 'advancepending':
    case 'advance_pending':
      return 1;
    case 'advanceapproved':
    case 'advance_approved':
      return 2;
    case 'advancepaid':
    case 'advance_paid':
      return 3;
    case 'settlementdraft':
    case 'settlement_draft':
      return 4;
    case 'settlementpending':
    case 'settlement_pending':
      return 5;
    case 'settlementapproved':
    case 'settlement_approved':
      return 6;
    case 'settling':
      return 7;
    case 'closed':
      return 8;
    case 'cancelled':
    case 'canceled':
      return 9;
    default:
      return null;
  }
}

String tripStatusLabel(dynamic status) {
  const labels = [
    'Nháp',
    'Chờ duyệt ứng',
    'Ứng đã duyệt',
    'Đã chi ứng',
    'Nháp HT',
    'Chờ duyệt HT',
    'HT đã duyệt',
    'Quyết toán',
    'Đóng',
    'Hủy',
  ];
  final s = parseTripStatus(status);
  if (s == null || s < 0 || s >= labels.length) return '—';
  return labels[s];
}

/// Màu trạng thái hồ sơ CT — Hủy (9) luôn đỏ để dễ nhận biết.
Color tripStatusColor(dynamic status) {
  switch (parseTripStatus(status)) {
    case 1:
    case 5:
      return const Color(0xFFF59E0B);
    case 8:
      return const Color(0xFF16A34A);
    case 9:
      return const Color(0xFFDC2626);
    case 2:
    case 3:
      return const Color(0xFF0EA5E9);
    default:
      return const Color(0xFF0EA5E9);
  }
}
