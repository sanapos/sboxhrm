import 'pos_doc_status.dart';

/// Kết quả mutation phiếu POS — verify `data.status` khớp kỳ vọng.
class PosDocMutationResult {
  const PosDocMutationResult({
    required this.ok,
    required this.status,
    this.data,
    this.errorMessage,
  });

  final bool ok;
  final String status;
  final Map<String, dynamic>? data;
  final String? errorMessage;

  static PosDocMutationResult parse(
    Map<String, dynamic> res, {
    required String expectedStatus,
    String statusFallback = 'Draft',
    String completedLabel = 'Hoàn thành',
  }) {
    if (res['isSuccess'] != true) {
      return PosDocMutationResult(
        ok: false,
        status: '',
        errorMessage: res['message']?.toString() ?? 'Thao tác thất bại',
      );
    }
    final raw = res['data'];
    if (raw is! Map) {
      return PosDocMutationResult(
        ok: false,
        status: '',
        errorMessage: 'Server không trả về dữ liệu phiếu — vui lòng tải lại',
      );
    }
    final data = Map<String, dynamic>.from(raw);
    final status =
        normalizePosDocStatus(data['status'], fallback: statusFallback);
    if (status != expectedStatus) {
      return PosDocMutationResult(
        ok: false,
        status: status,
        data: data,
        errorMessage:
            'Phiếu vẫn ở trạng thái ${posDocStatusLabel(status, completedLabel: completedLabel)} — chưa cập nhật được trên server',
      );
    }
    return PosDocMutationResult(ok: true, status: status, data: data);
  }

  String successMessage(
    String docNo, {
    String? stockNote,
    String completedLabel = 'Hoàn thành',
  }) {
    final label = posDocStatusLabel(status, completedLabel: completedLabel);
    if (stockNote != null && stockNote.isNotEmpty) {
      return '$docNo · $label · $stockNote';
    }
    return '$docNo · Trạng thái: $label';
  }

  /// Verify soft-delete response (`data.deleted == true`).
  static PosDocDeleteResult parseDelete(Map<String, dynamic> res) {
    if (res['isSuccess'] != true) {
      return PosDocDeleteResult(
        ok: false,
        errorMessage: res['message']?.toString() ?? 'Không xóa được',
      );
    }
    final raw = res['data'];
    if (raw is Map) {
      final data = Map<String, dynamic>.from(raw);
      final deleted = data['deleted'] ?? data['Deleted'];
      if (deleted == true) {
        return const PosDocDeleteResult(ok: true);
      }
    }
    return const PosDocDeleteResult(
      ok: false,
      errorMessage:
          'Server báo thành công nhưng phiếu chưa bị xóa — vui lòng tải lại',
    );
  }
}

class PosDocDeleteResult {
  const PosDocDeleteResult({required this.ok, this.errorMessage});

  final bool ok;
  final String? errorMessage;
}
