/// Verify gán cửa hàng / license cho đại lý.
class AgentMutationResult {
  const AgentMutationResult({
    required this.ok,
    this.errorMessage,
    this.agentId,
    this.assigned,
  });

  final bool ok;
  final String? errorMessage;
  final String? agentId;
  final bool? assigned;

  /// Gán cửa hàng cho đại lý — `data.assigned == true` và `agentId` khớp.
  static AgentMutationResult parseStoreAssignment(
    Map<String, dynamic> res, {
    required String? expectedAgentId,
  }) {
    if (res['isSuccess'] != true) {
      return AgentMutationResult(
        ok: false,
        errorMessage: res['message']?.toString() ?? 'Không cập nhật được đại lý',
      );
    }
    final raw = res['data'];
    if (raw is! Map) {
      // Backward compat: API cũ trả bool true
      if (raw == true) {
        return AgentMutationResult(ok: true, agentId: expectedAgentId, assigned: true);
      }
      return const AgentMutationResult(
        ok: false,
        errorMessage:
            'Server không trả về dữ liệu xác nhận — vui lòng tải lại danh sách',
      );
    }
    final data = Map<String, dynamic>.from(raw);
    final assigned = data['assigned'];
    final agentId = data['agentId']?.toString();

    if (expectedAgentId == null || expectedAgentId.isEmpty) {
      // Gỡ đại lý
      if (assigned == false && (agentId == null || agentId.isEmpty)) {
        return const AgentMutationResult(ok: true, assigned: false);
      }
      return const AgentMutationResult(
        ok: false,
        errorMessage:
            'Server báo thành công nhưng cửa hàng vẫn còn đại lý — vui lòng tải lại',
      );
    }

    if (assigned == true && agentId == expectedAgentId) {
      return AgentMutationResult(ok: true, agentId: agentId, assigned: true);
    }
    return const AgentMutationResult(
      ok: false,
      errorMessage:
          'Server báo thành công nhưng cửa hàng chưa gán được đại lý — vui lòng tải lại',
    );
  }

  /// Cấp license — verify `assignedCount > 0` hoặc `data.agentId` khớp (single assign).
  static AgentMutationResult parseLicenseAssign(
    Map<String, dynamic> res, {
    String? expectedAgentId,
    int minAssignedCount = 1,
  }) {
    if (res['isSuccess'] != true) {
      return AgentMutationResult(
        ok: false,
        errorMessage: res['message']?.toString() ?? 'Không gán được license',
      );
    }
    final raw = res['data'];
    if (raw is! Map) {
      return const AgentMutationResult(
        ok: false,
        errorMessage: 'Server không trả về dữ liệu license — vui lòng tải lại',
      );
    }
    final data = Map<String, dynamic>.from(raw);
    final assignedCount = (data['assignedCount'] as num?)?.toInt();
    if (assignedCount != null) {
      if (assignedCount >= minAssignedCount) {
        return AgentMutationResult(ok: true, agentId: expectedAgentId, assigned: true);
      }
      return const AgentMutationResult(
        ok: false,
        errorMessage: 'Không có license nào được gán cho đại lý',
      );
    }
    final agentId = data['agentId']?.toString();
    if (expectedAgentId != null && agentId == expectedAgentId) {
      return AgentMutationResult(ok: true, agentId: agentId, assigned: true);
    }
    return const AgentMutationResult(
      ok: false,
      errorMessage:
          'Server báo thành công nhưng license chưa gán được — vui lòng tải lại',
    );
  }
}
