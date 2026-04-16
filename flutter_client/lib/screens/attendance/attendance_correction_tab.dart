import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/attendance.dart';
import '../../models/device.dart';
import '../../widgets/notification_overlay.dart';

/// Model nội bộ cho yêu cầu chỉnh sửa (có thêm trạng thái xử lý)
class CorrectionRequestInternal {
  final String id;
  final String employeeName;
  final String employeeCode;
  final String? pin; // PIN/mã chấm công gốc
  final String? attendanceId; // ID bản ghi attendance gốc
  final DateTime requestDate;
  final DateTime correctionDate;
  final String reason;
  final CorrectionStatus status;
  final String correctionType;
  final String requestedTime;
  final String? originalTime;
  final String? processedBy;
  final DateTime? processedDate;
  final String? rejectionReason;

  CorrectionRequestInternal({
    required this.id,
    required this.employeeName,
    required this.employeeCode,
    this.pin,
    this.attendanceId,
    required this.requestDate,
    required this.correctionDate,
    required this.reason,
    required this.status,
    required this.correctionType,
    required this.requestedTime,
    this.originalTime,
    this.processedBy,
    this.processedDate,
    this.rejectionReason,
  });

  CorrectionRequestInternal copyWith({
    String? id,
    String? employeeName,
    String? employeeCode,
    String? pin,
    String? attendanceId,
    DateTime? requestDate,
    DateTime? correctionDate,
    String? reason,
    CorrectionStatus? status,
    String? correctionType,
    String? requestedTime,
    String? originalTime,
    String? processedBy,
    DateTime? processedDate,
    String? rejectionReason,
  }) {
    return CorrectionRequestInternal(
      id: id ?? this.id,
      employeeName: employeeName ?? this.employeeName,
      employeeCode: employeeCode ?? this.employeeCode,
      pin: pin ?? this.pin,
      attendanceId: attendanceId ?? this.attendanceId,
      requestDate: requestDate ?? this.requestDate,
      correctionDate: correctionDate ?? this.correctionDate,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      correctionType: correctionType ?? this.correctionType,
      requestedTime: requestedTime ?? this.requestedTime,
      originalTime: originalTime ?? this.originalTime,
      processedBy: processedBy ?? this.processedBy,
      processedDate: processedDate ?? this.processedDate,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }
}

enum CorrectionStatus { pending, approved, rejected }

class AttendanceCorrectionTab extends StatefulWidget {
  final List<Attendance> attendances;
  final List<Device> devices;
  final List<CorrectionRequestInternal> pendingRequests;
  final List<CorrectionRequestInternal> processedRequests;
  final Function(List<CorrectionRequestInternal> pending,
      List<CorrectionRequestInternal> processed)? onRequestsChanged;

  const AttendanceCorrectionTab({
    super.key,
    required this.attendances,
    required this.devices,
    required this.pendingRequests,
    required this.processedRequests,
    this.onRequestsChanged,
  });

  @override
  State<AttendanceCorrectionTab> createState() =>
      AttendanceCorrectionTabState();
}

class AttendanceCorrectionTabState extends State<AttendanceCorrectionTab> {
  // Filters for processed requests
  String _filterEmployee = '';
  String _filterType = 'all'; // all, add, edit, delete
  String _filterStatus = 'all'; // all, approved, rejected
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  bool _showMobileFilters = false;

  // Tab visibility
  bool _showPending = true;
  bool _showProcessed = true;

  // Get filtered processed requests
  List<CorrectionRequestInternal> get _filteredProcessedRequests {
    return widget.processedRequests.where((request) {
      // Filter by employee name
      if (_filterEmployee.isNotEmpty &&
          !request.employeeName.toLowerCase().contains(_filterEmployee.toLowerCase())) {
        return false;
      }

      // Filter by type
      if (_filterType != 'all') {
        final type = request.correctionType.split(':').first;
        if (type != _filterType) return false;
      }

      // Filter by status
      if (_filterStatus != 'all') {
        if (_filterStatus == 'approved' && request.status != CorrectionStatus.approved) return false;
        if (_filterStatus == 'rejected' && request.status != CorrectionStatus.rejected) return false;
      }

      // Filter by date range
      if (_filterDateFrom != null && request.correctionDate.isBefore(_filterDateFrom!)) return false;
      if (_filterDateTo != null && request.correctionDate.isAfter(_filterDateTo!.add(const Duration(days: 1)))) return false;

      return true;
    }).toList();
  }

  // Get color for correction type
  Color _getCorrectionTypeColor(String type) {
    switch (type) {
      case 'add':
        return Colors.green;
      case 'edit':
        return Colors.blue;
      case 'delete':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Get icon for correction type
  IconData _getCorrectionTypeIcon(String type) {
    switch (type) {
      case 'add':
        return Icons.add_circle;
      case 'edit':
        return Icons.edit;
      case 'delete':
        return Icons.delete;
      default:
        return Icons.help;
    }
  }

  // Get label for correction type
  String _getCorrectionTypeLabel(String type) {
    switch (type) {
      case 'add':
        return 'Thêm';
      case 'edit':
        return 'Sửa';
      case 'delete':
        return 'Xóa';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingRequests = widget.pendingRequests;
    final processedRequests = widget.processedRequests;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with filters and add button - all in one row
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Builder(
                builder: (context) {
                  final isMobile = MediaQuery.of(context).size.width < 768;
                  final hasActiveFilters = _filterEmployee.isNotEmpty || _filterType != 'all' || _filterStatus != 'all' || _filterDateFrom != null;

                  final searchField = Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Tìm nhân viên...',
                          hintStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          prefixIcon: const Icon(Icons.search, size: 16),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey[600]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey[600]!),
                          ),
                        ),
                        style: const TextStyle(fontSize: 11),
                        onChanged: (value) => setState(() => _filterEmployee = value),
                      ),
                    ),
                  );

                  final typeFilter = SizedBox(
                    width: 100,
                    height: 32,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[600]!),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _filterType,
                          isDense: true,
                          isExpanded: true,
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                          dropdownColor: Theme.of(context).cardColor,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('Loại', style: TextStyle(fontSize: 11))),
                            DropdownMenuItem(value: 'add', child: Row(children: [Icon(Icons.add_circle, size: 12, color: Colors.green), SizedBox(width: 4), Text('Thêm', style: TextStyle(fontSize: 11))])),
                            DropdownMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 12, color: Colors.blue), SizedBox(width: 4), Text('Sửa', style: TextStyle(fontSize: 11))])),
                            DropdownMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 12, color: Colors.red), SizedBox(width: 4), Text('Xóa', style: TextStyle(fontSize: 11))])),
                          ],
                          onChanged: (value) => setState(() => _filterType = value ?? 'all'),
                        ),
                      ),
                    ),
                  );

                  final statusFilter = SizedBox(
                    width: 110,
                    height: 32,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[600]!),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _filterStatus,
                          isDense: true,
                          isExpanded: true,
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                          dropdownColor: Theme.of(context).cardColor,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('Trạng thái', style: TextStyle(fontSize: 11))),
                            DropdownMenuItem(value: 'approved', child: Row(children: [Icon(Icons.check_circle, size: 12, color: Colors.green), SizedBox(width: 4), Text('Duyệt', style: TextStyle(fontSize: 11))])),
                            DropdownMenuItem(value: 'rejected', child: Row(children: [Icon(Icons.cancel, size: 12, color: Colors.orange), SizedBox(width: 4), Text('Từ chối', style: TextStyle(fontSize: 11))])),
                          ],
                          onChanged: (value) => setState(() => _filterStatus = value ?? 'all'),
                        ),
                      ),
                    ),
                  );

                  final datePicker = InkWell(
                    onTap: () => _showDateRangeDialog(),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[600]!),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.date_range, size: 14, color: _filterDateFrom != null ? Colors.blue : Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            _filterDateFrom != null 
                              ? '${DateFormat('dd/MM').format(_filterDateFrom!)} - ${_filterDateTo != null ? DateFormat('dd/MM').format(_filterDateTo!) : '...'}'
                              : 'Ngày',
                            style: TextStyle(fontSize: 11, color: _filterDateFrom != null ? Colors.white : Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                  );

                  final clearButton = hasActiveFilters
                    ? IconButton(
                        onPressed: () {
                          setState(() {
                            _filterEmployee = '';
                            _filterType = 'all';
                            _filterStatus = 'all';
                            _filterDateFrom = null;
                            _filterDateTo = null;
                          });
                        },
                        icon: const Icon(Icons.clear, size: 16),
                        tooltip: 'Xóa lọc',
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(foregroundColor: Colors.orange),
                      )
                    : const SizedBox.shrink();

                  if (isMobile) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.edit_calendar, color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Yêu cầu chấm công',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ),
                            InkWell(
                              onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                height: 32,
                                width: 32,
                                decoration: BoxDecoration(
                                  color: _showMobileFilters ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: _showMobileFilters ? Theme.of(context).primaryColor.withValues(alpha: 0.3) : Colors.grey[600]!),
                                ),
                                child: Stack(
                                  children: [
                                    Center(child: Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, size: 16, color: _showMobileFilters ? Theme.of(context).primaryColor : Colors.grey.shade600)),
                                    if (hasActiveFilters)
                                      Positioned(top: 3, right: 3, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle))),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _showCreateRequestDialog,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Tạo', style: TextStyle(fontSize: 12)),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                minimumSize: Size.zero,
                              ),
                            ),
                          ],
                        ),
                        if (_showMobileFilters) ...[
                          const SizedBox(height: 8),
                          Row(children: [searchField]),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              typeFilter,
                              const SizedBox(width: 8),
                              statusFilter,
                              const SizedBox(width: 8),
                              datePicker,
                              clearButton,
                            ],
                          ),
                        ],
                      ],
                    );
                  }

                  return Row(
                    children: [
                      const Icon(Icons.edit_calendar, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Yêu cầu chấm công',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Row(
                          children: [
                            searchField,
                            const SizedBox(width: 8),
                            typeFilter,
                            const SizedBox(width: 8),
                            statusFilter,
                            const SizedBox(width: 8),
                            datePicker,
                            clearButton,
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _showCreateRequestDialog,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Tạo', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Section headers - Pending and Processed in same row
          Row(
            children: [
              // Pending section header
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _showPending = !_showPending),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: _showPending ? 0.15 : 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: _showPending ? 0.5 : 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _showPending ? Icons.expand_more : Icons.chevron_right,
                          color: Colors.orange,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.pending_actions, color: Colors.orange, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Chờ xử lý (${pendingRequests.length})',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Processed section header
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _showProcessed = !_showProcessed),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: _showProcessed ? 0.15 : 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withValues(alpha: _showProcessed ? 0.5 : 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _showProcessed ? Icons.expand_more : Icons.chevron_right,
                          color: Colors.grey[400],
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.history, color: Colors.grey[400], size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Đã xử lý (${_filteredProcessedRequests.length}/${processedRequests.length})',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Content - show based on selection
          if (_showPending) ...[
            if (pendingRequests.isEmpty)
              _buildEmptyState('Không có yêu cầu chờ xử lý')
            else if (MediaQuery.of(context).size.width < 600)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(pendingRequests.length, (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: _buildPendingDeckItem(pendingRequests[i]),
                  ),
                )),
              )
            else
              ...pendingRequests
                  .map((request) => _buildPendingRequestCard(request,
                      key: ValueKey('pending_${request.id}')))
                  ,
            if (_showProcessed) const SizedBox(height: 16),
          ],

          if (_showProcessed) ...[
            if (_filteredProcessedRequests.isEmpty)
              _buildEmptyState(processedRequests.isEmpty ? 'Chưa có yêu cầu được xử lý' : 'Không có kết quả phù hợp')
            else if (MediaQuery.of(context).size.width < 600)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_filteredProcessedRequests.length, (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: _buildProcessedDeckItem(_filteredProcessedRequests[i]),
                  ),
                )),
              )
            else
              ..._filteredProcessedRequests
                  .map((request) => _buildProcessedRequestCard(request,
                      key: ValueKey('processed_${request.id}')))
                  ,
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inbox, size: 36, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(message, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  void _showDateRangeDialog() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _filterDateFrom != null && _filterDateTo != null
          ? DateTimeRange(start: _filterDateFrom!, end: _filterDateTo!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _filterDateFrom = picked.start;
        _filterDateTo = picked.end;
      });
    }
  }

  Widget _buildPendingDeckItem(CorrectionRequestInternal request) {
    final correctionType = request.correctionType.split(':').first;
    final typeColor = _getCorrectionTypeColor(correctionType);
    final typeIcon = _getCorrectionTypeIcon(correctionType);
    final typeLabel = _getCorrectionTypeLabel(correctionType);

    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(typeIcon, color: typeColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(request.employeeName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([typeLabel, DateFormat('dd/MM').format(request.correctionDate), '${request.originalTime} \u2192 ${request.requestedTime}'].join(' \u00b7 '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          InkWell(onTap: () => _approveRequest(request), child: const Icon(Icons.check_circle_outline, size: 22, color: Colors.green)),
          const SizedBox(width: 6),
          InkWell(onTap: () => _rejectRequest(request), child: const Icon(Icons.cancel_outlined, size: 22, color: Colors.red)),
        ]),
      ),
    );
  }

  Widget _buildProcessedDeckItem(CorrectionRequestInternal request) {
    final isApproved = request.status == CorrectionStatus.approved;
    final statusColor = isApproved ? Colors.green : Colors.orange;
    final correctionType = request.correctionType.split(':').first;
    final typeLabel = _getCorrectionTypeLabel(correctionType);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(isApproved ? Icons.check_circle : Icons.cancel, color: statusColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(request.employeeName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text([typeLabel, DateFormat('dd/MM').format(request.correctionDate), request.processedBy ?? ''].where((s) => s.isNotEmpty).join(' \u00b7 '),
              style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(isApproved ? '\u0110\u00e3 duy\u1ec7t' : 'T\u1eeb ch\u1ed1i', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
        ),
      ]),
    );
  }

  Widget _buildPendingRequestCard(CorrectionRequestInternal request,
      {Key? key}) {
    // Get correction type info
    final correctionTypeParts = request.correctionType.split(':');
    final correctionType = correctionTypeParts.first;
    final punchIndex = correctionTypeParts.length > 1 ? correctionTypeParts[1] : '';
    final typeColor = _getCorrectionTypeColor(correctionType);
    final typeIcon = _getCorrectionTypeIcon(correctionType);
    final typeLabel = _getCorrectionTypeLabel(correctionType);

    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Avatar with type icon
            CircleAvatar(
              radius: 16,
              backgroundColor: typeColor.withValues(alpha: 0.15),
              child: Icon(typeIcon, size: 16, color: typeColor),
            ),
            const SizedBox(width: 10),
            // Main info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        request.employeeName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${request.employeeCode})',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM/yyyy').format(request.correctionDate),
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.access_time,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        request.originalTime != null
                            ? '${request.originalTime} → ${request.requestedTime}'
                            : request.requestedTime,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 8),
                      // Correction type badge with color
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: typeColor.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(typeIcon, size: 11, color: typeColor),
                            const SizedBox(width: 3),
                            Text(
                              punchIndex.isNotEmpty ? '$typeLabel lần $punchIndex' : typeLabel,
                              style: TextStyle(
                                fontSize: 10, 
                                color: typeColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Action buttons
            IconButton(
              onPressed: () => _deleteRequest(request),
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Xóa',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(foregroundColor: Colors.grey),
            ),
            IconButton(
              onPressed: () => _rejectRequest(request),
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Từ chối',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(foregroundColor: Colors.orange),
            ),
            IconButton(
              onPressed: () => _approveRequest(request),
              icon: const Icon(Icons.check, size: 18),
              tooltip: 'Duyệt',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessedRequestCard(CorrectionRequestInternal request,
      {Key? key}) {
    final isApproved = request.status == CorrectionStatus.approved;
    final statusColor = isApproved ? Colors.green : Colors.orange;
    final statusText = isApproved ? 'Đã duyệt' : 'Từ chối';
    final statusIcon = isApproved ? Icons.check_circle : Icons.cancel;
    
    // Get correction type info
    final correctionTypeParts = request.correctionType.split(':');
    final correctionType = correctionTypeParts.first;
    final punchIndex = correctionTypeParts.length > 1 ? correctionTypeParts[1] : '';
    final typeColor = _getCorrectionTypeColor(correctionType);
    final typeIcon = _getCorrectionTypeIcon(correctionType);
    final typeLabel = _getCorrectionTypeLabel(correctionType);

    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Avatar with status icon
            CircleAvatar(
              radius: 16,
              backgroundColor: statusColor.withValues(alpha: 0.1),
              child: Icon(statusIcon, size: 16, color: statusColor),
            ),
            const SizedBox(width: 10),
            // Main info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        request.employeeName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      // Correction type badge with color
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: typeColor.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(typeIcon, size: 12, color: typeColor),
                            const SizedBox(width: 3),
                            Text(
                              punchIndex.isNotEmpty ? '$typeLabel lần $punchIndex' : typeLabel,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: typeColor,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                              fontSize: 10,
                              color: statusColor,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM/yyyy').format(request.correctionDate),
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.access_time,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        request.originalTime != null && request.originalTime!.isNotEmpty
                            ? '${request.originalTime} → ${request.requestedTime}'
                            : request.requestedTime,
                        style: TextStyle(
                          fontSize: 11, 
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• ${request.processedBy ?? "-"}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  void _showCreateRequestDialog() {
    final employeeController = TextEditingController();
    final reasonController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String selectedAction = 'add'; // add, edit, delete
    int selectedPunchIndex = 1; // punch index (1-based)
    TimeOfDay selectedTime = const TimeOfDay(hour: 8, minute: 0);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.edit_calendar, color: Colors.orange),
                SizedBox(width: 8),
                Text('Tạo yêu cầu chấm công'),
              ],
            ),
            content: SizedBox(
              width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: employeeController,
                    decoration: const InputDecoration(
                      labelText: 'Tên nhân viên',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 30)),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedDate = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Ngày cần bổ sung',
                              prefixIcon: Icon(Icons.calendar_today),
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                                DateFormat('dd/MM/yyyy').format(selectedDate)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedAction,
                          decoration: const InputDecoration(
                            labelText: 'Loại',
                            prefixIcon: Icon(Icons.category),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'add', child: Text('Thêm')),
                            DropdownMenuItem(
                                value: 'edit', child: Text('Sửa')),
                            DropdownMenuItem(
                                value: 'delete', child: Text('Xóa')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => selectedAction = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Giờ chấm công',
                        prefixIcon: Icon(Icons.access_time),
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Lý do',
                      prefixIcon: Icon(Icons.description),
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () {
                  if (employeeController.text.isNotEmpty &&
                      reasonController.text.isNotEmpty) {
                    final newPending = List<CorrectionRequestInternal>.from(
                        widget.pendingRequests);
                    newPending.insert(
                        0,
                        CorrectionRequestInternal(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          employeeName: employeeController.text,
                          employeeCode:
                              'NV${(widget.pendingRequests.length + widget.processedRequests.length + 1).toString().padLeft(3, '0')}',
                          requestDate: DateTime.now(),
                          correctionDate: selectedDate,
                          reason: reasonController.text,
                          status: CorrectionStatus.pending,
                          correctionType: '$selectedAction:$selectedPunchIndex',
                          requestedTime:
                              '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                        ));

                    widget.onRequestsChanged
                        ?.call(newPending, widget.processedRequests);
                    Navigator.pop(context);
                    appNotification.showSuccess(
                        title: 'Thành công',
                        message: 'Đã tạo yêu cầu chấm công');
                  }
                },
                child: const Text('Gửi yêu cầu'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _approveRequest(CorrectionRequestInternal request) {
    final newPending =
        List<CorrectionRequestInternal>.from(widget.pendingRequests);
    final newProcessed =
        List<CorrectionRequestInternal>.from(widget.processedRequests);

    newPending.removeWhere((r) => r.id == request.id);
    newProcessed.insert(
        0,
        request.copyWith(
          status: CorrectionStatus.approved,
          processedBy: 'Admin',
          processedDate: DateTime.now(),
        ));

    widget.onRequestsChanged?.call(newPending, newProcessed);
    appNotification.showSuccess(
        title: 'Thành công', message: 'Đã phê duyệt yêu cầu');
  }

  void _rejectRequest(CorrectionRequestInternal request) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Từ chối yêu cầu'),
        content: SingleChildScrollView(
          child: TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Lý do từ chối',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final newPending =
                  List<CorrectionRequestInternal>.from(widget.pendingRequests);
              final newProcessed = List<CorrectionRequestInternal>.from(
                  widget.processedRequests);

              newPending.removeWhere((r) => r.id == request.id);
              newProcessed.insert(
                  0,
                  request.copyWith(
                    status: CorrectionStatus.rejected,
                    processedBy: 'Admin',
                    processedDate: DateTime.now(),
                    rejectionReason: reasonController.text.isEmpty
                        ? 'Không có lý do'
                        : reasonController.text,
                  ));

              widget.onRequestsChanged?.call(newPending, newProcessed);
              Navigator.pop(context);
              appNotification.showInfo(
                  title: 'Thông báo', message: 'Đã từ chối yêu cầu');
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Từ chối'),
          ),
        ],
      ),
    );
  }

  /// Xóa yêu cầu
  void _deleteRequest(CorrectionRequestInternal request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Xóa yêu cầu'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bạn có chắc muốn xóa yêu cầu này?'),
            const SizedBox(height: 12),
            Card(
              color: Colors.grey.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nhân viên: ${request.employeeName}'),
                    Text('Loại: ${request.correctionType}'),
                    Text(
                        'Ngày: ${DateFormat('dd/MM/yyyy').format(request.correctionDate)}'),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: () {
              final newPending =
                  List<CorrectionRequestInternal>.from(widget.pendingRequests);
              newPending.removeWhere((r) => r.id == request.id);

              widget.onRequestsChanged
                  ?.call(newPending, widget.processedRequests);
              Navigator.pop(context);
              appNotification.showInfo(
                  title: 'Đã xóa', message: 'Đã xóa yêu cầu thành công');
            },
            icon: const Icon(Icons.delete),
            label: const Text('Xóa'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
  }
}
