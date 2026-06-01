import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'hrm_page_chrome.dart';

/// Chú thích quy trình đổi ca — hiển thị trên các màn liên quan.
class ShiftSwapFlowHelpBanner extends StatelessWidget {
  final bool compact;
  final VoidCallback? onTapDetail;

  const ShiftSwapFlowHelpBanner({
    super.key,
    this.compact = false,
    this.onTapDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTapDetail,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 10 : 14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline,
                  size: compact ? 18 : 22, color: HrmPageChrome.primaryNavy),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quy trình đổi ca (3 bước)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 12 : 13,
                        color: HrmPageChrome.primaryNavy,
                      ),
                    ),
                    SizedBox(height: compact ? 4 : 6),
                    Text(
                      compact
                          ? '① Gửi YC → ② Đồng nghiệp đồng ý → ③ QL duyệt. Bấm vào từng dòng để xem chi tiết.'
                          : '① Bạn gửi yêu cầu đổi ca với đồng nghiệp.\n'
                              '② Đồng nghiệp chấp nhận hoặc từ chối trên tab「Cần phản hồi」.\n'
                              '③ Quản lý duyệt trên tab「Chờ duyệt」— sau đó lịch làm việc được cập nhật tự động.\n'
                              'Bấm vào từng yêu cầu để xem đầy đủ thông tin.',
                      style: TextStyle(
                        fontSize: compact ? 11 : 12,
                        height: 1.35,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
              if (onTapDetail != null)
                Icon(Icons.chevron_right,
                    size: 20, color: HrmPageChrome.primaryNavy.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> parseShiftSwapList(dynamic data) {
  if (data == null) return [];
  if (data is List) {
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  if (data is Map && data['items'] != null) {
    return (data['items'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
  return [];
}

String shiftSwapStatusText(dynamic status) {
  final s = status?.toString() ?? '';
  switch (s) {
    case '0':
    case 'Pending':
      return 'Chờ đồng nghiệp';
    case '1':
    case 'TargetAccepted':
      return 'Chờ QL duyệt';
    case '2':
    case 'Approved':
      return 'Đã duyệt';
    case '3':
    case 'RejectedByTarget':
      return 'Đồng nghiệp từ chối';
    case '4':
    case 'RejectedByManager':
      return 'QL từ chối';
    case '5':
    case 'Cancelled':
      return 'Đã hủy';
    default:
      return s.isEmpty ? 'Không rõ' : s;
  }
}

Color shiftSwapStatusColor(dynamic status) {
  final s = status?.toString() ?? '';
  switch (s) {
    case '2':
    case 'Approved':
      return const Color(0xFF16A34A);
    case '3':
    case '4':
    case 'RejectedByTarget':
    case 'RejectedByManager':
      return const Color(0xFFEF4444);
    case '1':
    case 'TargetAccepted':
      return const Color(0xFF8B5CF6);
    default:
      return const Color(0xFFF59E0B);
  }
}

String formatSwapDate(dynamic date) {
  if (date == null) return '—';
  try {
    return DateFormat('dd/MM/yyyy').format(DateTime.parse(date.toString()));
  } catch (_) {
    return date.toString();
  }
}

void showShiftSwapDetailSheet(BuildContext context, Map<String, dynamic> swap) {
  final status = swap['status'];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.swap_horiz, color: HrmPageChrome.primaryNavy),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Chi tiết yêu cầu đổi ca',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: shiftSwapStatusColor(status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(shiftSwapStatusText(status),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: shiftSwapStatusColor(status))),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow('Người gửi', swap['requesterName']?.toString() ?? '—'),
            _detailRow('Ca / ngày gửi',
                '${swap['requesterShiftName'] ?? ''} · ${formatSwapDate(swap['requesterDate'])}'),
            const Divider(height: 20),
            _detailRow('Đồng nghiệp', swap['targetName']?.toString() ?? '—'),
            _detailRow('Ca / ngày nhận',
                '${swap['targetShiftName'] ?? ''} · ${formatSwapDate(swap['targetDate'])}'),
            if ((swap['reason'] ?? '').toString().isNotEmpty)
              _detailRow('Lý do', swap['reason'].toString()),
            if ((swap['rejectionReason'] ?? '').toString().isNotEmpty)
              _detailRow('Lý do từ chối', swap['rejectionReason'].toString(),
                  valueColor: const Color(0xFFEF4444)),
            if ((swap['note'] ?? '').toString().isNotEmpty)
              _detailRow('Ghi chú QL', swap['note'].toString()),
            const SizedBox(height: 8),
            Text(
              'Tạo lúc: ${formatSwapDate(swap['createdAt'])}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _detailRow(String label, String value, {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8))),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? const Color(0xFF1E293B))),
      ],
    ),
  );
}
