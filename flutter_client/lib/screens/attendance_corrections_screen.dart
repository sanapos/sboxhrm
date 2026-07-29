import 'package:flutter/material.dart';
import '../widgets/app_scroll_safe.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../utils/attendance_correction_privilege.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/safe_layout_widgets.dart';
import '../widgets/hrm_fab_clearance.dart';
import 'package:intl/intl.dart';
import '../models/hrm.dart';
import '../services/api_service.dart';
import '../utils/api_datetime.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/attendance_correction_reason_field.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class AttendanceCorrectionsScreen extends StatefulWidget {
  final String? highlightId;
  const AttendanceCorrectionsScreen({super.key, this.highlightId});

  @override
  State<AttendanceCorrectionsScreen> createState() =>
      _AttendanceCorrectionsScreenState();
}

class _AttendanceCorrectionsScreenState
    extends State<AttendanceCorrectionsScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  List<AttendanceCorrectionRequest> _requests = [];
  List<AttendanceCorrectionRequest> _pendingRequests = [];
  bool _isLoading = true;
  bool _allowManualCorrection = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final settingResult =
          await _apiService.getAppSetting('allow_manual_correction');
      if (mounted) {
        final val = settingResult['data']?['value']?.toString();
        setState(() => _allowManualCorrection = val != 'false');
      }
      final result = await _apiService.getMyAttendanceCorrections(
        page: 1,
        pageSize: 100,
      );
      if (mounted) {
        setState(() {
          if (result['isSuccess'] == true && result['data'] != null) {
            final data = result['data'];
            final items = List<Map<String, dynamic>>.from(
                data['items'] ?? data is List ? data : []);
            _requests = items
                .map((e) => AttendanceCorrectionRequest.fromJson(e))
                .toList();
            _pendingRequests = _requests
                .where((r) => r.status == CorrectionStatus.pending)
                .toList();
          } else {
            _requests = [];
            _pendingRequests = [];
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading correction requests: $e');
      if (mounted) {
        appNotification.showError(
            title: 'Lỗi', message: tr('Không thể tải dữ liệu'));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _maybeOpenHighlight();
    }
  }

  bool _highlightOpened = false;
  void _maybeOpenHighlight() {
    if (_highlightOpened) return;
    final id = widget.highlightId;
    if (id == null || id.isEmpty) return;
    AttendanceCorrectionRequest? match;
    for (final r in _requests) {
      if (r.id == id) {
        match = r;
        break;
      }
    }
    if (match == null) return;
    _highlightOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showRequestDetail(match!);
    });
  }

  void _showCreateDialog() {
    DateTime selectedDate = DateTime.now();
    CorrectionAction selectedAction = CorrectionAction.edit;
    TimeOfDay? newCheckIn;
    TimeOfDay? newCheckOut;
    final reasonController = TextEditingController();

    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<CorrectionAction>(
                  initialValue: selectedAction,
                  decoration: InputDecoration(
                    labelText: tr('Loại yêu cầu *'),
                    border: OutlineInputBorder(),
                  ),
                  items: CorrectionAction.values
                      .map((action) => DropdownMenuItem(
                            value: action,
                            child: Text(tr(getCorrectionActionLabel(action))),
                          ))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedAction = val!),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: tr('Ngày chấm công *'),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(tr(DateFormat('dd/MM/yyyy').format(selectedDate))),
                  ),
                ),
                const SizedBox(height: 16),
                if (selectedAction != CorrectionAction.delete) ...[
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: newCheckIn ?? TimeOfDay.now(),
                            );
                            if (time != null) {
                              setDialogState(() => newCheckIn = time);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: tr('Giờ vào mới'),
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              tr(newCheckIn != null
                                  ? '${newCheckIn!.hour.toString().padLeft(2, '0')}:${newCheckIn!.minute.toString().padLeft(2, '0')}'
                                  : '--:--'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: newCheckOut ?? TimeOfDay.now(),
                            );
                            if (time != null) {
                              setDialogState(() => newCheckOut = time);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: tr('Giờ ra mới'),
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              tr(newCheckOut != null
                                  ? '${newCheckOut!.hour.toString().padLeft(2, '0')}:${newCheckOut!.minute.toString().padLeft(2, '0')}'
                                  : '--:--'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                AttendanceCorrectionReasonField(
                  controller: reasonController,
                  kind: reasonKindFromCorrectionAction(selectedAction),
                  date: selectedDate,
                  timeText: newCheckIn != null
                      ? '${newCheckIn!.hour.toString().padLeft(2, '0')}:${newCheckIn!.minute.toString().padLeft(2, '0')}'
                      : (newCheckOut != null
                          ? '${newCheckOut!.hour.toString().padLeft(2, '0')}:${newCheckOut!.minute.toString().padLeft(2, '0')}'
                          : null),
                  punchLabel: newCheckIn != null
                      ? 'Vào'
                      : (newCheckOut != null ? 'Ra' : null),
                ),
              ],
            ),
          );
          Future<Null> onSubmit() async {
            if (reasonController.text.trim().isEmpty) {
              appNotification.showWarning(
                  title: 'Cảnh báo', message: tr('Vui lòng nhập lý do'));
              return;
            }
            try {
              final result = await _apiService.createAttendanceCorrection(
                action: selectedAction.index,
                newDate: selectedDate,
                newTime: newCheckIn != null
                    ? '${newCheckIn!.hour.toString().padLeft(2, '0')}:${newCheckIn!.minute.toString().padLeft(2, '0')}'
                    : null,
                reason: reasonController.text.trim(),
              );
              if (result['isSuccess'] == true) {
                if (!context.mounted) return;
                final auth = context.read<AuthProvider>();
                final perm = context.read<PermissionProvider>();
                final expectedDirect = canDirectAttendanceCorrection(
                  role: auth.user?.role,
                  allowManualSetting: _allowManualCorrection,
                  permissions: perm,
                );
                Navigator.pop(context);
                appNotification.showSuccess(
                    title: 'Thành công',
                    message: attendanceCorrectionSuccessMessage(
                      result,
                      expectedDirect: expectedDirect,
                    ));
                _loadData();
              } else {
                appNotification.showError(
                    title: 'Lỗi',
                    message: result['message'] ?? 'Không thể gửi yêu cầu');
              }
            } catch (e) {
              appNotification.showError(
                  title: 'Lỗi', message: tr('Lỗi kết nối: $e'));
            } finally {
              reasonController.dispose();
            }
          }

          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(tr('Yêu cầu sửa chấm công'),
                        overflow: TextOverflow.ellipsis, maxLines: 1),
                    leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(tr('Hủy'))),
                        const SizedBox(width: 12),
                        ElevatedButton(
                            onPressed: onSubmit,
                            child: Text(tr('Gửi yêu cầu'))),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: Text(tr('Yêu cầu sửa chấm công')),
            content: formContent,
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Hủy'))),
              ElevatedButton(
                  onPressed: onSubmit, child: Text(tr('Gửi yêu cầu'))),
            ],
          );
        },
      ),
    );
  }

  Color _getStatusColor(CorrectionStatus status) {
    switch (status) {
      case CorrectionStatus.pending:
        return Colors.orange;
      case CorrectionStatus.approved:
        return Colors.green;
      case CorrectionStatus.rejected:
        return Colors.red;
    }
  }

  Color _getActionColor(CorrectionAction action) {
    switch (action) {
      case CorrectionAction.add:
        return Colors.green;
      case CorrectionAction.edit:
        return Colors.blue;
      case CorrectionAction.delete:
        return Colors.red;
    }
  }

  Color _getApprovalStatusColor(ApprovalStatus status) {
    switch (status) {
      case ApprovalStatus.pending:
        return Colors.orange;
      case ApprovalStatus.approved:
        return Colors.green;
      case ApprovalStatus.rejected:
        return Colors.red;
      case ApprovalStatus.cancelled:
        return Colors.grey;
      case ApprovalStatus.expired:
        return Colors.grey;
    }
  }

  IconData _getApprovalStatusIcon(ApprovalStatus status) {
    switch (status) {
      case ApprovalStatus.pending:
        return Icons.hourglass_empty;
      case ApprovalStatus.approved:
        return Icons.check_circle;
      case ApprovalStatus.rejected:
        return Icons.cancel;
      case ApprovalStatus.cancelled:
        return Icons.block;
      case ApprovalStatus.expired:
        return Icons.timer_off;
    }
  }

  String _getApprovalStatusLabel(ApprovalStatus status) {
    switch (status) {
      case ApprovalStatus.pending:
        return 'Chờ duyệt';
      case ApprovalStatus.approved:
        return 'Đã duyệt';
      case ApprovalStatus.rejected:
        return 'Từ chối';
      case ApprovalStatus.cancelled:
        return 'Đã hủy';
      case ApprovalStatus.expired:
        return 'Hết hạn';
    }
  }

  void _showRequestDetail(AttendanceCorrectionRequest request) {
    showAppSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getActionColor(request.action)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.edit_calendar,
                        color: _getActionColor(request.action)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('${getCorrectionActionLabel(request.action)} · ${DateFormat('dd/MM/yyyy').format(request.correctionDate)}'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (request.reason != null &&
                            request.reason!.isNotEmpty)
                          Text(tr(request.reason!),
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(request.status)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tr(getCorrectionStatusLabel(request.status)),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(request.status)),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Time info
              if (request.action != CorrectionAction.delete) ...[
                _detailRow('Giờ cũ',
                    '${request.originalCheckIn ?? '--:--'} / ${request.originalCheckOut ?? '--:--'}'),
                _detailRow('Giờ mới',
                    '${request.newCheckIn ?? '--:--'} / ${request.newCheckOut ?? '--:--'}'),
              ],
              _detailRow('Ngày tạo',
                  formatApiDateTime(request.createdAt)),

              // Multi-level approval progress
              if (request.totalApprovalLevels > 1 ||
                  request.approvalRecords.isNotEmpty) ...[
                const Divider(height: 24),
                Row(
                  children: [
                    const Icon(Icons.account_tree,
                        size: 16, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    Text(tr('Tiến trình duyệt (${request.currentApprovalStep}/${request.totalApprovalLevels})'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildApprovalTimeline(request),
              ] else ...[
                // Single-level info
                if (request.approvedByName != null)
                  _detailRow('Người duyệt', request.approvedByName!),
                if (request.approvedAt != null)
                  _detailRow('Ngày duyệt', formatApiDateTime(request.approvedAt)),
                if (request.rejectReason != null &&
                    request.rejectReason!.isNotEmpty)
                  _detailRow('Lý do từ chối', request.rejectReason!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(tr(label),
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(child: Text(tr(value), style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildApprovalTimeline(AttendanceCorrectionRequest request) {
    final records = request.approvalRecords;
    if (records.isEmpty) {
      return Text(tr('Chưa có dữ liệu duyệt'),
          style: TextStyle(fontSize: 12, color: Colors.grey));
    }

    return Column(
      children: records.asMap().entries.map((entry) {
        final idx = entry.key;
        final record = entry.value;
        final isLast = idx == records.length - 1;
        final color = _getApprovalStatusColor(record.status);

        return SafeTimelineRow(
          isLast: isLast,
          indicator: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(_getApprovalStatusIcon(record.status),
                size: 12, color: color),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    tr(record.stepName ?? 'Bước ${record.stepOrder}'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tr(_getApprovalStatusLabel(record.status)),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tr(record.status == ApprovalStatus.pending
                    ? 'Người duyệt: ${record.assignedUserName ?? 'Chưa xác định'}'
                    : 'Người duyệt: ${record.actualUserName ?? record.assignedUserName ?? '--'}'),
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              if (record.note != null && record.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(tr('Ghi chú: ${record.note}'),
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic),
                  ),
                ),
              if (record.actionDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    tr(formatApiDateTime(record.actionDate)),
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500]),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRequestDeckItem(AttendanceCorrectionRequest request) {
    final actionColor = _getActionColor(request.action);
    final statusColor = _getStatusColor(request.status);
    return InkWell(
      onTap: () => _showRequestDetail(request),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: actionColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child:
                      Icon(Icons.edit_calendar, color: actionColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('${getCorrectionActionLabel(request.action)} · ${DateFormat('dd/MM/yyyy').format(request.correctionDate)}'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr([
                          if (request.action != CorrectionAction.delete)
                            '${request.originalCheckIn ?? '--:--'}/${request.originalCheckOut ?? '--:--'} → ${request.newCheckIn ?? '--:--'}/${request.newCheckOut ?? '--:--'}',
                          if (request.reason != null &&
                              request.reason!.isNotEmpty)
                            request.reason!,
                        ].join(' · ')),
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(tr(getCorrectionStatusLabel(request.status)),
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (request.totalApprovalLevels > 1) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 48),
                  const Icon(Icons.account_tree,
                      size: 12, color: Colors.blueGrey),
                  const SizedBox(width: 4),
                  Text(tr('Duyệt ${request.currentApprovalStep}/${request.totalApprovalLevels}'),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                  const SizedBox(width: 8),
                  ...List.generate(request.totalApprovalLevels, (i) {
                    Color dotColor;
                    final isRejected =
                        request.status == CorrectionStatus.rejected;
                    if (isRejected) {
                      dotColor = i < request.currentApprovalStep
                          ? Colors.green
                          : (i == request.currentApprovalStep
                              ? Colors.red
                              : Colors.grey[300]!);
                    } else {
                      dotColor = i < request.currentApprovalStep
                          ? Colors.green
                          : (i == request.currentApprovalStep &&
                                  request.status == CorrectionStatus.pending
                              ? Colors.orange
                              : Colors.grey[300]!);
                    }
                    return Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: dotColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: dotColor, width: 1.5),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsList(List<AttendanceCorrectionRequest> requests) {
    if (_isLoading) {
      return const LoadingWidget();
    }

    if (requests.isEmpty) {
      return const EmptyState(
        icon: Icons.access_time,
        title: 'Không có yêu cầu',
        description: 'Chưa có yêu cầu sửa chấm công nào',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: requests.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildRequestDeckItem(requests[index]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showCreateFab = _allowManualCorrection &&
        canShowCorrectionButtons(
          role: Provider.of<AuthProvider>(context, listen: false).userRole,
          allowManualSetting: _allowManualCorrection,
          permissions:
              Provider.of<PermissionProvider>(context, listen: false),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Sửa chấm công'),
            overflow: TextOverflow.ellipsis, maxLines: 1),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('Chờ duyệt')),
                  if (_pendingRequests.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        tr('${_pendingRequests.length}'),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(text: tr('Tất cả')),
          ],
        ),
      ),
      body: HrmFabClearance(
        fabVisible: showCreateFab,
        extendedFab: true,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildRequestsList(_pendingRequests),
            _buildRequestsList(_requests),
          ],
        ),
      ),
      floatingActionButton: showCreateFab
          ? FloatingActionButton.extended(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add),
              label: Text(tr('Yêu cầu mới')),
            )
          : null,
    );
  }
}
