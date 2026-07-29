import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/business_trip_status.dart';
import '../utils/navigation_notifier.dart';
import '../widgets/auth_cached_image.dart';
import '../widgets/in_app_image_viewer.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

export '../utils/business_trip_status.dart';

const _theme = Color(0xFF0EA5E9);

String advanceStatusLabel(dynamic s) {
  final v = parseTripStatus(s) ?? (s is int ? s : int.tryParse(s?.toString() ?? ''));
  // AdvanceRequestStatus: Pending=0, Approved=1, Rejected=2, Cancelled=3
  // Also accept string names
  final name = s?.toString() ?? '';
  if (name == 'Pending' || v == 0) return 'Chờ duyệt';
  if (name == 'Approved' || v == 1) return 'Đã duyệt';
  if (name == 'Rejected' || v == 2) return 'Từ chối';
  if (name == 'Cancelled' || v == 3) return 'Đã hủy';
  switch (v) {
    case 0:
      return 'Chờ duyệt';
    case 1:
      return 'Đã duyệt';
    case 2:
      return 'Từ chối';
    case 3:
      return 'Đã hủy';
    default:
      return s?.toString() ?? '—';
  }
}

/// Loại chứng từ dòng chi (lưu vào note + hasInvoice).
enum ExpenseDocType {
  vatInvoice,
  salesInvoice,
  none,
}

extension ExpenseDocTypeX on ExpenseDocType {
  String get label => switch (this) {
        ExpenseDocType.vatInvoice => 'Hóa đơn VAT',
        ExpenseDocType.salesInvoice => 'Hóa đơn bán hàng',
        ExpenseDocType.none => 'Không giấy tờ',
      };

  bool get hasInvoice => this != ExpenseDocType.none;

  String encodeNote(String? userNote) {
    final prefix = switch (this) {
      ExpenseDocType.vatInvoice => 'doc:vat',
      ExpenseDocType.salesInvoice => 'doc:sales',
      ExpenseDocType.none => 'doc:none',
    };
    final n = userNote?.trim() ?? '';
    return n.isEmpty ? prefix : '$prefix|$n';
  }

  static ExpenseDocType parse(String? note, bool hasInvoice) {
    final n = note ?? '';
    if (n.startsWith('doc:vat')) return ExpenseDocType.vatInvoice;
    if (n.startsWith('doc:sales')) return ExpenseDocType.salesInvoice;
    if (n.startsWith('doc:none')) return ExpenseDocType.none;
    return hasInvoice ? ExpenseDocType.vatInvoice : ExpenseDocType.none;
  }

  static String? userNoteOf(String? note) {
    if (note == null) return null;
    final i = note.indexOf('|');
    if (note.startsWith('doc:') && i >= 0) return note.substring(i + 1);
    if (note.startsWith('doc:')) return null;
    return note;
  }
}

class _DraftExpenseLine {
  String? id;
  String? categoryId;
  String categoryName;
  DateTime expenseDate;
  double amount;
  String description;
  String note;
  ExpenseDocType docType;
  String? invoiceNumber;
  String? attachmentUrl;
  String? attachmentName;
  List<Map<String, dynamic>> attachments;

  _DraftExpenseLine({
    this.id,
    this.categoryId,
    this.categoryName = '',
    DateTime? expenseDate,
    this.amount = 0,
    this.description = '',
    this.note = '',
    this.docType = ExpenseDocType.none,
    this.invoiceNumber,
    this.attachmentUrl,
    this.attachmentName,
    List<Map<String, dynamic>>? attachments,
  })  : expenseDate = expenseDate ?? DateTime.now(),
        attachments = attachments ?? [];

  Map<String, dynamic> toApi(int sortOrder) {
    final atts = <Map<String, dynamic>>[];
    if (attachments.isNotEmpty) {
      atts.addAll(attachments);
    } else if (attachmentUrl != null && attachmentUrl!.isNotEmpty) {
      atts.add({
        'fileName': attachmentName ?? 'chungtu.jpg',
        'fileUrl': attachmentUrl,
        'contentType': 'image/jpeg',
        'attachmentType': docType == ExpenseDocType.vatInvoice ? 0 : 1,
      });
    }
    return {
      'categoryId': categoryId,
      'expenseDate': expenseDate.toIso8601String(),
      'amount': amount,
      'description':
          description.trim().isEmpty ? categoryName : description.trim(),
      'note': docType.encodeNote(note),
      'hasInvoice': docType.hasInvoice,
      if (invoiceNumber != null && invoiceNumber!.trim().isNotEmpty)
        'invoiceNumber': invoiceNumber!.trim(),
      'sortOrder': sortOrder,
      if (atts.isNotEmpty) 'attachments': atts,
    };
  }
}

class BusinessTripCaseDetailScreen extends StatefulWidget {
  final String caseId;
  const BusinessTripCaseDetailScreen({super.key, required this.caseId});

  @override
  State<BusinessTripCaseDetailScreen> createState() =>
      _BusinessTripCaseDetailScreenState();
}

class _BusinessTripCaseDetailScreenState
    extends State<BusinessTripCaseDetailScreen> {
  final ApiService _api = ApiService();
  final _currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
  final _dateFmt = DateFormat('dd/MM/yyyy');

  Map<String, dynamic>? _case;
  List<Map<String, dynamic>> _categories = [];
  final List<_DraftExpenseLine> _lines = [];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String _settlementNote = '';

  bool get _canApprove =>
      Provider.of<PermissionProvider>(context, listen: false)
          .canApprove('BusinessTripExpense');

  bool get _canCreate =>
      Provider.of<PermissionProvider>(context, listen: false)
          .canCreate('BusinessTripExpense') ||
      Provider.of<PermissionProvider>(context, listen: false)
          .canEdit('BusinessTripExpense');

  bool get _canEditHeader {
    if (!_canCreate) return false;
    if (_status == 8 || _status == 9) return false;
    // Đang chờ duyệt: chỉ QL/KT (Approve) được sửa
    if (_status == 1 || _status == 5) return _canApprove;
    return true;
  }

  bool get _canEditSettlement {
    if (!_canCreate) return false;
    final settlementStatus = parseTripStatus(_case?['settlement'] is Map
        ? (_case!['settlement'] as Map)['status']
        : null);
    return _status == 0 ||
        _status == 3 ||
        _status == 4 ||
        settlementStatus == 2;
  }

  int get _status => parseTripStatus(_case?['status']) ?? 0;

  double get _linesTotal {
    if (_lines.isNotEmpty) {
      return _lines.fold(0.0, (s, l) => s + l.amount);
    }
    final settlement = _case?['settlement'];
    if (settlement is Map && settlement['totalAmount'] is num) {
      return (settlement['totalAmount'] as num).toDouble();
    }
    final settled = _case?['settledAmount'];
    if (settled is num) return settled.toDouble();
    return 0;
  }

  double get _advanceAmount {
    final advance = _case?['advance'];
    if (advance is Map && advance['amount'] is num) {
      return (advance['amount'] as num).toDouble();
    }
    final a = _case?['advanceAmount'];
    if (a is num) return a.toDouble();
    return 0;
  }

  double get _balance {
    final settlement = _case?['settlement'];
    if (settlement is Map && settlement['balanceAmount'] is num) {
      return (settlement['balanceAmount'] as num).toDouble();
    }
    final bal = _case?['balanceAmount'];
    if (bal is num) return bal.toDouble();
    return _linesTotal - _advanceAmount;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final seedRes = await _api.seedBusinessTripExpenseCategories();
      // Seed có thể 403 nếu thiếu quyền — vẫn tiếp tục tải hồ sơ.
      if (seedRes['isSuccess'] != true) {
        // ignore
      }
      final results = await Future.wait([
        _api.getBusinessTripCase(widget.caseId),
        _api.getBusinessTripExpenseCategories(),
      ]);
      if (!mounted) return;

      final caseRes = results[0];
      final catRes = results[1];

      if (caseRes['isSuccess'] == true && caseRes['data'] is Map) {
        _case = Map<String, dynamic>.from(caseRes['data'] as Map);
        _hydrateLinesFromCase();
      } else {
        _loadError = caseRes['message']?.toString() ?? 'Không tìm thấy hồ sơ';
      }

      if (catRes['isSuccess'] == true) {
        final raw = catRes['data'];
        if (raw is List) {
          _categories = raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
            ..sort((a, b) =>
                ((a['sortOrder'] as num?)?.toInt() ?? 0)
                    .compareTo((b['sortOrder'] as num?)?.toInt() ?? 0));
        }
      }
    } catch (e) {
      _loadError = 'Lỗi tải hồ sơ: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _hydrateLinesFromCase() {
    _lines.clear();
    final settlement = _case?['settlement'];
    if (settlement is! Map) return;
    _settlementNote = settlement['note']?.toString() ?? '';
    final rawLines = settlement['lines'] ?? settlement['Lines'];
    if (rawLines is! List) return;
    for (final e in rawLines.whereType<Map>()) {
      final m = Map<String, dynamic>.from(e);
      final note = m['note']?.toString();
      final hasInv = m['hasInvoice'] == true;
      DateTime date = DateTime.now();
      try {
        if (m['expenseDate'] != null) {
          date = DateTime.parse(m['expenseDate'].toString());
        }
      } catch (_) {}
      final attsRaw = m['attachments'] ?? m['Attachments'];
      final atts = <Map<String, dynamic>>[];
      if (attsRaw is List) {
        for (final a in attsRaw.whereType<Map>()) {
          atts.add(Map<String, dynamic>.from(a));
        }
      }
      String? url;
      String? name;
      if (atts.isNotEmpty) {
        url = atts.first['fileUrl']?.toString() ??
            atts.first['url']?.toString();
        name = atts.first['fileName']?.toString() ??
            atts.first['name']?.toString();
      }
      _lines.add(_DraftExpenseLine(
        id: m['id']?.toString(),
        categoryId: m['categoryId']?.toString(),
        categoryName: m['categoryName']?.toString() ?? '',
        expenseDate: date,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        description: m['description']?.toString() ?? '',
        note: ExpenseDocTypeX.userNoteOf(note) ?? '',
        docType: ExpenseDocTypeX.parse(note, hasInv),
        invoiceNumber: m['invoiceNumber']?.toString(),
        attachmentUrl: url,
        attachmentName: name,
        attachments: atts,
      ));
    }
  }

  Future<void> _reload() async {
    final res = await _api.getBusinessTripCase(widget.caseId);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() {
        _case = Map<String, dynamic>.from(res['data'] as Map);
        _hydrateLinesFromCase();
      });
    }
  }

  Future<void> _editCaseHeader() async {
    final c = _case;
    if (c == null) return;
    final titleCtrl = TextEditingController(text: tr(c['title']?.toString() ?? ''));
    final destCtrl =
        TextEditingController(text: tr(c['destination']?.toString() ?? ''));
    final noteCtrl = TextEditingController(text: tr(c['note']?.toString() ?? ''));
    DateTime? from = DateTime.tryParse(c['tripFromDate']?.toString() ?? '');
    DateTime? to = DateTime.tryParse(c['tripToDate']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr('Sửa hồ sơ công tác')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(labelText: tr('Tiêu đề *'))),
                TextField(
                    controller: destCtrl,
                    decoration: InputDecoration(labelText: tr('Điểm đến'))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final p = await showDatePicker(
                            context: ctx,
                            initialDate: from ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate:
                                DateTime.now().add(const Duration(days: 730)),
                          );
                          if (p != null) setDlg(() => from = p);
                        },
                        child: Text(tr(from == null
                            ? 'Từ ngày'
                            : _dateFmt.format(from!))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final p = await showDatePicker(
                            context: ctx,
                            initialDate: to ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate:
                                DateTime.now().add(const Duration(days: 730)),
                          );
                          if (p != null) setDlg(() => to = p);
                        },
                        child: Text(
                            tr(to == null ? 'Đến ngày' : _dateFmt.format(to!))),
                      ),
                    ),
                  ],
                ),
                TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: tr('Ghi chú'))),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Hủy'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Lưu'))),
          ],
        ),
      ),
    );
    final title = titleCtrl.text.trim();
    final dest = destCtrl.text.trim();
    final note = noteCtrl.text.trim();
    titleCtrl.dispose();
    destCtrl.dispose();
    noteCtrl.dispose();
    if (ok != true) return;
    if (title.isEmpty) {
      appNotification.showError(
          title: 'Thiếu thông tin', message: tr('Nhập tiêu đề'));
      return;
    }
    final res = await _api.updateBusinessTripCase(widget.caseId, {
      'title': title,
      if (dest.isNotEmpty) 'destination': dest,
      if (note.isNotEmpty) 'note': note,
      if (from != null) 'tripFromDate': from!.toIso8601String(),
      if (to != null) 'tripToDate': to!.toIso8601String(),
    });
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      appNotification.showSuccess(title: 'Đã lưu', message: tr('Đã cập nhật hồ sơ'));
      await _reload();
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không sửa được',
      );
    }
  }

  Future<void> _deleteCase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa / hủy hồ sơ?')),
        content: Text(
          tr('Hồ sơ nháp chưa duyệt sẽ bị xóa.\n'
          'Hồ sơ đã gửi sẽ chuyển sang Hủy và hủy các phiếu Thu chi chờ thanh toán / phiếu ứng·HT chưa chi.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Đóng'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xác nhận')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final res = await _api.deleteBusinessTripCase(widget.caseId);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Thành công', message: tr('Đã xóa/hủy hồ sơ'));
      Navigator.pop(context);
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không xóa được',
      );
    }
  }

  Future<void> _advanceDialog() async {
    final amountCtrl = TextEditingController();
    final reasonCtrl =
        TextEditingController(text: tr(_case?['title']?.toString() ?? ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Ứng công tác')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              decoration: InputDecoration(
                labelText: tr('Số tiền ứng *'),
                prefixText: tr('₫ '),
              ),
            ),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(labelText: tr('Lý do')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Gửi duyệt'))),
        ],
      ),
    );
    final amount = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
    final reason = reasonCtrl.text.trim();
    amountCtrl.dispose();
    reasonCtrl.dispose();
    if (ok != true) return;
    if (amount <= 0) {
      appNotification.showError(
          title: 'Thiếu thông tin', message: tr('Số tiền ứng phải lớn hơn 0'));
      return;
    }
    final res = await _api.createBusinessTripAdvance(widget.caseId, {
      'amount': amount,
      'reason': reason,
    });
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Thành công', message: tr('Đã gửi duyệt ứng công tác'));
      await _reload();
    } else {
      appNotification.showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không gửi được phiếu ứng');
    }
  }

  Future<String?> _pickPaymentMethod() async {
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(tr('Chọn hình thức chi / thu'),
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(tr('Tiền mặt')),
              onTap: () => Navigator.pop(ctx, 'Cash'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(tr('Chuyển khoản')),
              onTap: () => Navigator.pop(ctx, 'BankTransfer'),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: Text(tr('VietQR')),
              onTap: () => Navigator.pop(ctx, 'VietQR'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openCashVoucher(String? cashId) {
    if (cashId == null || cashId.isEmpty) {
      appNotification.showError(
          title: 'Chưa có phiếu', message: tr('Chưa tạo phiếu Thu chi liên kết'));
      return;
    }
    NavigationNotifier.goToCashTransaction(highlightId: cashId);
  }

  Future<void> _approveSettlementWithSurplusCheck() async {
    final bal = _balance;
    var surplusAsCashRefund = false;
    if (bal < 0) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Dư ứng công tác')),
          content: Text(tr('${tr('Hoạch toán dư ')}${_currency.format(bal.abs())}.\n'
            'Chọn cách xử lý:'),
            style: const TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Hủy'))),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'refund'),
              child: Text(tr('Thu tiền mặt')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'debt'),
              child: Text(tr('Ghi nợ ứng lương')),
            ),
          ],
        ),
      );
      if (choice == null) return;
      surplusAsCashRefund = choice == 'refund';
    }

    final res = await _api.approveBusinessTripSettlement(
      widget.caseId,
      true,
      surplusAsCashRefund: surplusAsCashRefund,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      appNotification.showSuccess(
        title: 'Đã duyệt',
        message: bal < 0
            ? (surplusAsCashRefund
                ? 'Đã tạo phiếu thu hoàn dư ứng'
                : 'Đã ghi nợ ứng lương (trừ kỳ lương)')
            : 'Hoạch toán đã duyệt',
      );
      await _reload();
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Duyệt thất bại',
      );
    }
  }

  Future<void> _openAttachment(
    String? url, {
    List<String>? galleryUrls,
  }) async {
    if (!mounted) return;
    await openAttachmentInApp(
      context,
      apiService: _api,
      url: url,
      galleryUrls: galleryUrls,
      title: 'Chứng từ',
    );
  }

  Future<void> _showLineDetail(_DraftExpenseLine line, int index) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final atts = line.attachments.isNotEmpty
            ? line.attachments
            : (line.attachmentUrl != null && line.attachmentUrl!.isNotEmpty
                ? [
                    {
                      'fileUrl': line.attachmentUrl,
                      'fileName': line.attachmentName ?? 'Đính kèm',
                    }
                  ]
                : <Map<String, dynamic>>[]);
        Widget row(String label, String value) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(label),
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(tr(value.isEmpty ? '—' : value),
                      style: const TextStyle(fontSize: 15, height: 1.35)),
                ],
              ),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long, color: _theme),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(line.categoryName.isEmpty
                            ? 'Chi tiết khoản chi'
                            : line.categoryName),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 20),
                row('Số tiền', _currency.format(line.amount)),
                row('Ngày chi', _dateFmt.format(line.expenseDate)),
                row('Mô tả', line.description),
                row('Loại giấy tờ', line.docType.label),
                row('Số hóa đơn / chứng từ', line.invoiceNumber ?? ''),
                row('Ghi chú', line.note),
                Text(tr('Đính kèm (${atts.length})'),
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (atts.isEmpty)
                  Text(tr('Chưa có file đính kèm'),
                      style: TextStyle(color: Colors.grey[600]))
                else
                  ...atts.asMap().entries.map((entry) {
                    final a = entry.value;
                    final url =
                        a['fileUrl']?.toString() ?? a['url']?.toString() ?? '';
                    final name = a['fileName']?.toString() ??
                        a['name']?.toString() ??
                        'Tệp đính kèm';
                    final isImg = isLikelyImageUrl(url);
                    final gallery = atts
                        .map((x) =>
                            x['fileUrl']?.toString() ??
                            x['url']?.toString() ??
                            '')
                        .where((u) => u.isNotEmpty && isLikelyImageUrl(u))
                        .toList();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        leading: isImg && url.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: AuthCachedImage(
                                  imagePath: url,
                                  apiService: _api,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      const Icon(Icons.attach_file),
                                ),
                              )
                            : const Icon(Icons.attach_file),
                        title: Text(tr(name),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            tr(isImg ? 'Chạm để xem trong app' : 'Chạm để mở tệp')),
                        trailing: Icon(
                          isImg ? Icons.zoom_in : Icons.open_in_new,
                          size: 18,
                        ),
                        onTap: () => _openAttachment(url, galleryUrls: gallery),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                if (_canEditSettlement)
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(tr('Sửa khoản chi này')),
                  ),
                if (!_canEditSettlement &&
                    _canApprove &&
                    parseTripStatus(_case?['settlement'] is Map
                            ? (_case!['settlement'] as Map)['status']
                            : null) ==
                        0) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'supplement'),
                    icon: const Icon(Icons.playlist_add_check),
                    label: Text(tr('Yêu cầu bổ sung giấy tờ')),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (action == 'edit') {
      await _addOrEditLine(existing: line, index: index);
    } else if (action == 'supplement') {
      await _requestSettlementSupplement(
        hint: 'Thiếu giấy tờ cho khoản: ${line.categoryName.isEmpty ? 'chi phí' : line.categoryName}',
      );
    }
  }

  Future<void> _requestSettlementSupplement({String? hint}) async {
    final ctrl = TextEditingController(text: tr(hint ?? ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Yêu cầu bổ sung giấy tờ')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Phiếu hoạch toán sẽ trả về nhân viên để bổ sung/sửa khoản chi và đính kèm. Nhập nội dung cần bổ sung:'),
              style: TextStyle(height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: tr('Nội dung yêu cầu *'),
                hintText: tr('VD: Thiếu hóa đơn VAT tiền khách sạn ngày 10/7'),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Gửi yêu cầu'))),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    if (text.isEmpty) {
      appNotification.showError(
          title: 'Thiếu nội dung', message: tr('Nhập yêu cầu bổ sung'));
      return;
    }
    final reason = text.startsWith('Bổ sung')
        ? text
        : 'Bổ sung giấy tờ: $text';
    final res = await _api.approveBusinessTripSettlement(
      widget.caseId,
      false,
      rejectionReason: reason,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      appNotification.showSuccess(
        title: 'Đã gửi',
        message: tr('Đã yêu cầu NV bổ sung giấy tờ / sửa hoạch toán'),
      );
      await _reload();
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không gửi được yêu cầu',
      );
    }
  }

  Future<void> _rejectSettlementDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Từ chối hoạch toán')),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: tr('Lý do từ chối *'),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Từ chối')),
          ),
        ],
      ),
    );
    final reason = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    if (reason.isEmpty) {
      appNotification.showError(title: 'Thiếu lý do', message: tr('Nhập lý do từ chối'));
      return;
    }
    final res = await _api.approveBusinessTripSettlement(
      widget.caseId,
      false,
      rejectionReason: reason,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      appNotification.showSuccess(title: 'Đã từ chối', message: reason);
      await _reload();
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không từ chối được',
      );
    }
  }

  Future<void> _addOrEditLine({_DraftExpenseLine? existing, int? index}) async {
    if (_categories.isEmpty) {
      appNotification.showError(
        title: 'Chưa có hạn mục',
        message: tr('Chưa seed được danh mục chi phí. Thử tải lại.'),
      );
      return;
    }

    final line = existing ??
        _DraftExpenseLine(
          categoryId: _categories.first['id']?.toString(),
          categoryName: _categories.first['name']?.toString() ?? '',
        );

    final amountCtrl =
        TextEditingController(text: tr(line.amount > 0 ? line.amount.toStringAsFixed(0) : ''));
    final descCtrl = TextEditingController(text: tr(line.description));
    final noteCtrl = TextEditingController(text: tr(line.note));
    final invoiceCtrl = TextEditingController(text: tr(line.invoiceNumber ?? ''));
    var categoryId = line.categoryId;
    var categoryName = line.categoryName;
    var docType = line.docType;
    var expenseDate = line.expenseDate;
    var attachmentUrl = line.attachmentUrl;
    var attachmentName = line.attachmentName;
    var uploading = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> pickAttach() async {
              final picker = ImagePicker();
              final photo = await picker.pickImage(
                source: ImageSource.gallery,
                maxWidth: 1920,
                imageQuality: 80,
              );
              if (photo == null) return;
              setSheet(() => uploading = true);
              final bytes = await photo.readAsBytes();
              final up = await _api.uploadFile(
                bytes,
                photo.name,
                folder: 'business-trip',
              );
              setSheet(() => uploading = false);
              if (up['isSuccess'] == true) {
                final data = up['data'];
                final url = data is Map
                    ? (data['url'] ?? data['fileUrl'] ?? data['path'])
                        ?.toString()
                    : up['url']?.toString();
                if (url != null && url.isNotEmpty) {
                  setSheet(() {
                    attachmentUrl = url;
                    attachmentName = photo.name;
                  });
                }
              } else {
                appNotification.showError(
                  title: 'Upload lỗi',
                  message: up['message']?.toString() ?? 'Không tải được ảnh',
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          tr(existing == null ? 'Thêm khoản chi' : 'Sửa khoản chi'),
                          style: Theme.of(ctx).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(tr('Hạn mục'),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700])),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _categories.map((c) {
                        final id = c['id']?.toString();
                        final name = c['name']?.toString() ?? '';
                        final selected = id == categoryId;
                        return ChoiceChip(
                          label: Text(tr(name)),
                          selected: selected,
                          selectedColor: _theme.withValues(alpha: 0.2),
                          onSelected: (_) => setSheet(() {
                            categoryId = id;
                            categoryName = name;
                            if (c['requiresInvoice'] == true &&
                                docType == ExpenseDocType.none) {
                              docType = ExpenseDocType.vatInvoice;
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: tr('Số tiền *'),
                        prefixText: tr('₫ '),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: InputDecoration(
                        labelText: tr('Mô tả'),
                        hintText: tr('VD: Ăn trưa 2 người'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: expenseDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 30)),
                        );
                        if (d != null) setSheet(() => expenseDate = d);
                      },
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(tr('Ngày chi: ${_dateFmt.format(expenseDate)}')),
                    ),
                    const SizedBox(height: 12),
                    Text(tr('Chứng từ'),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700])),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ExpenseDocType.values.map((t) {
                        return ChoiceChip(
                          label: Text(tr(t.label)),
                          selected: docType == t,
                          onSelected: (_) => setSheet(() => docType = t),
                        );
                      }).toList(),
                    ),
                    if (docType.hasInvoice) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: invoiceCtrl,
                        decoration: InputDecoration(
                          labelText: tr('Số hóa đơn'),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: tr('Ghi chú dòng'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (attachmentUrl != null && attachmentUrl!.isNotEmpty) ...[
                      GestureDetector(
                        onTap: () => openAttachmentInApp(
                          context,
                          apiService: _api,
                          url: attachmentUrl,
                          title: attachmentName ?? 'Chứng từ',
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AuthCachedImage(
                            imagePath: attachmentUrl!,
                            apiService: _api,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              height: 80,
                              color: const Color(0xFFF3F4F6),
                              alignment: Alignment.center,
                              child: Text(tr('Không xem trước được ảnh')),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton.icon(
                      onPressed: uploading ? null : pickAttach,
                      icon: uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file),
                      label: Text(tr(attachmentUrl == null
                          ? 'Đính kèm ảnh chứng từ'
                          : 'Đổi ảnh: ${attachmentName ?? 'ảnh'}')),
                    ),
                    if (attachmentUrl != null)
                      TextButton.icon(
                        onPressed: () => openAttachmentInApp(
                          context,
                          apiService: _api,
                          url: attachmentUrl,
                          title: attachmentName ?? 'Chứng từ',
                        ),
                        icon: const Icon(Icons.zoom_in, size: 18),
                        label: Text(tr('Xem ảnh trong app')),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        final amount = double.tryParse(
                              amountCtrl.text.replaceAll(',', ''),
                            ) ??
                            0;
                        if (amount <= 0) {
                          appNotification.showError(
                            title: 'Thiếu thông tin',
                            message: tr('Số tiền phải lớn hơn 0'),
                          );
                          return;
                        }
                        if (categoryId == null) {
                          appNotification.showError(
                            title: 'Thiếu thông tin',
                            message: tr('Chọn hạn mục chi phí'),
                          );
                          return;
                        }
                        line.categoryId = categoryId;
                        line.categoryName = categoryName;
                        line.amount = amount;
                        line.description = descCtrl.text.trim();
                        line.note = noteCtrl.text.trim();
                        line.docType = docType;
                        line.expenseDate = expenseDate;
                        line.invoiceNumber = invoiceCtrl.text.trim().isEmpty
                            ? null
                            : invoiceCtrl.text.trim();
                        line.attachmentUrl = attachmentUrl;
                        line.attachmentName = attachmentName;
                        if (attachmentUrl != null &&
                            attachmentUrl!.isNotEmpty) {
                          line.attachments = [
                            {
                              'fileName': attachmentName ?? 'chungtu.jpg',
                              'fileUrl': attachmentUrl,
                              'contentType': 'image/jpeg',
                              'attachmentType':
                                  docType == ExpenseDocType.vatInvoice ? 0 : 1,
                            }
                          ];
                        }
                        Navigator.pop(ctx, true);
                      },
                      child: Text(tr(existing == null ? 'Thêm vào danh sách' : 'Lưu')),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    amountCtrl.dispose();
    descCtrl.dispose();
    noteCtrl.dispose();
    invoiceCtrl.dispose();

    if (saved == true) {
      setState(() {
        if (index != null) {
          _lines[index] = line;
        } else {
          _lines.add(line);
        }
      });
    }
  }

  Future<void> _submitSettlement() async {
    if (_lines.isEmpty) {
      appNotification.showError(
        title: 'Thiếu khoản chi',
        message: tr('Thêm ít nhất một khoản chi phí trước khi gửi duyệt'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await _api.saveBusinessTripSettlement(widget.caseId, {
        'note': _settlementNote.trim().isEmpty ? null : _settlementNote.trim(),
        'lines': [
          for (var i = 0; i < _lines.length; i++) _lines[i].toApi(i),
        ],
      });
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: tr('Đã gửi hoạch toán công tác'),
        );
        await _reload();
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không gửi được hoạch toán',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Hồ sơ công tác'))),
        body: const LoadingWidget(),
      );
    }
    final c = _case;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Hồ sơ công tác'))),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr(_loadError ?? 'Không tìm thấy')),
              const SizedBox(height: 12),
              FilledButton(onPressed: _bootstrap, child: Text(tr('Thử lại'))),
            ],
          ),
        ),
      );
    }

    final advance = c['advance'] is Map
        ? Map<String, dynamic>.from(c['advance'] as Map)
        : null;
    final settlement = c['settlement'] is Map
        ? Map<String, dynamic>.from(c['settlement'] as Map)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(tr(c['caseCode']?.toString() ?? 'Công tác')),
        actions: [
          if (_canEditHeader)
            IconButton(
              tooltip: tr('Sửa hồ sơ'),
              onPressed: _editCaseHeader,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (_canCreate && _status != 8 && _status != 9)
            IconButton(
              tooltip: tr('Xóa / hủy hồ sơ'),
              onPressed: _deleteCase,
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(onPressed: _bootstrap, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              children: [
                _headerCard(c),
                const SizedBox(height: 12),
                _advanceCard(advance),
                const SizedBox(height: 12),
                _settlementSection(settlement),
                if (_canApprove) ...[
                  const SizedBox(height: 12),
                  _approvalActions(advance, settlement),
                ],
              ],
            ),
          ),
          if (_canEditSettlement) _bottomBar(),
        ],
      ),
    );
  }

  Widget _headerCard(Map<String, dynamic> c) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(c['title']?.toString() ?? ''),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tripStatusColor(_status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tr(tripStatusLabel(_status)),
                    style: TextStyle(
                        color: tripStatusColor(_status),
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(tr('NV: ${c['employeeName'] ?? '—'}')),
            if ((c['destination']?.toString().isNotEmpty ?? false))
              Text(tr('${tr('Điểm đến: ')}${c['destination']}')),
            if (c['tripFromDate'] != null || c['tripToDate'] != null)
              Text(tr('${tr('Thời gian: ')}${_fmtDate(c['tripFromDate'])} → ${_fmtDate(c['tripToDate'])}'),
              ),
            if ((c['note']?.toString().isNotEmpty ?? false))
              Text(tr('${tr('Ghi chú: ')}${c['note']}')),
          ],
        ),
      ),
    );
  }

  Widget _advanceCard(Map<String, dynamic>? advance) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payments_outlined, color: _theme),
                const SizedBox(width: 8),
                Text(tr('Ứng công tác'),
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_status == 0 && _canCreate)
                  FilledButton.tonal(
                    onPressed: _advanceDialog,
                    child: Text(tr('Tạo phiếu ứng')),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(tr('Đã ứng: ${_currency.format(_advanceAmount)}'),
                style: const TextStyle(fontSize: 15)),
            if (advance != null) ...[
              Text(tr('${tr('Trạng thái: ')}${advanceStatusLabel(advance['status'])}')),
              Text(tr('${tr('Đã chi: ')}${advance['isPaid'] == true ? 'Có' : 'Chưa'}')),
            ] else if (_status == 0)
              Text(tr('Chưa có phiếu ứng. Có thể tạo ứng trước, hoặc bỏ qua và hoạch toán trực tiếp.'),
                style: TextStyle(color: Colors.grey[700], height: 1.35),
              ),
          ],
        ),
      ),
    );
  }

  Widget _settlementSection(Map<String, dynamic>? settlement) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: _theme),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('Hoạch toán chi phí'),
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (_canEditSettlement)
                  IconButton.filledTonal(
                    onPressed: () => _addOrEditLine(),
                    icon: const Icon(Icons.add),
                    tooltip: tr('Thêm khoản chi'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_canEditSettlement) ...[
              Text(tr('Chọn loại chi phí → nhập số tiền & phân loại hóa đơn/giấy tờ'),
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
              const SizedBox(height: 10),
              if (_categories.isEmpty)
                OutlinedButton.icon(
                  onPressed: () async {
                    await _api.seedBusinessTripExpenseCategories();
                    await _bootstrap();
                  },
                  icon: const Icon(Icons.playlist_add),
                  label: Text(tr('Khởi tạo danh mục chi phí mẫu')),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _categories.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.4,
                  ),
                  itemBuilder: (_, i) {
                    final cat = _categories[i];
                    final needInv = cat['requiresInvoice'] == true;
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          final draft = _DraftExpenseLine(
                            categoryId: cat['id']?.toString(),
                            categoryName: cat['name']?.toString() ?? '',
                            docType: needInv
                                ? ExpenseDocType.vatInvoice
                                : ExpenseDocType.none,
                          );
                          _addOrEditLine(existing: draft);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: _theme.withValues(alpha: 0.12),
                                child: Icon(
                                  needInv
                                      ? Icons.receipt_long
                                      : Icons.add_shopping_cart,
                                  size: 16,
                                  color: _theme,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tr(cat['name']?.toString() ?? ''),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addOrEditLine(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Khoản khác (không theo danh mục)')),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_lines.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Text(
                  tr(_case?['settlement'] == null &&
                          ((_case?['settledAmount'] as num?) ?? 0) != 0
                      ? 'Chi tiết hạn mục không còn trên hồ sơ (dữ liệu hoạch toán bị mất).\nTổng đã quyết toán: ${_currency.format(_linesTotal)}.'
                      : _canEditSettlement
                          ? 'Chưa có khoản chi.\nThêm tiền ăn, tiền xe, nhà nghỉ, vé máy bay… giống nhập hàng.'
                          : 'Chưa có dòng hoạch toán.'),
                  style: TextStyle(color: Colors.grey[700], height: 1.4),
                ),
              )
            else
              ...List.generate(_lines.length, (i) {
                final l = _lines[i];
                return Dismissible(
                  key: ValueKey('line-$i-${l.categoryId}-${l.amount}'),
                  direction: _canEditSettlement
                      ? DismissDirection.endToStart
                      : DismissDirection.none,
                  onDismissed: (_) => setState(() => _lines.removeAt(i)),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: _theme.withValues(alpha: 0.12),
                      child: Text(
                        tr('${i + 1}'),
                        style: const TextStyle(
                            color: _theme, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      tr(l.categoryName.isEmpty ? 'Chi phí' : l.categoryName),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      tr([
                        if (l.description.isNotEmpty) l.description,
                        l.docType.label,
                        _dateFmt.format(l.expenseDate),
                        if (l.note.isNotEmpty) 'Ghi chú: ${l.note}',
                        if (l.attachmentUrl != null || l.attachments.isNotEmpty)
                          'Có đính kèm',
                      ].join(' · ')),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr(_currency.format(l.amount)),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right,
                            color: Colors.grey[500], size: 20),
                      ],
                    ),
                    onTap: () => _showLineDetail(l, i),
                  ),
                );
              }),
            const Divider(height: 24),
            _totalRow('Tổng chi', _linesTotal, bold: true),
            _totalRow('Đã ứng', _advanceAmount),
            _totalRow(
              _balance >= 0 ? 'Thiếu (chi bù)' : 'Dư (ghi nợ ứng)',
              _balance.abs(),
              color: _balance >= 0
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF16A34A),
            ),
            if (settlement != null) ...[
              const SizedBox(height: 8),
              Text(tr('${tr('Trạng thái HT: ')}${advanceStatusLabel(settlement['status'])}'),
                style: TextStyle(color: Colors.grey[700]),
              ),
              if ((settlement['rejectionReason']?.toString() ?? '')
                  .trim()
                  .isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDBA74)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr((settlement['rejectionReason']
                                    ?.toString()
                                    .toLowerCase()
                                    .contains('bổ sung') ==
                                true)
                            ? 'Yêu cầu bổ sung'
                            : 'Lý do trả về'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFC2410C)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(settlement['rejectionReason'].toString()),
                        style: const TextStyle(
                            height: 1.35, color: Color(0xFF9A3412)),
                      ),
                      if (_canEditSettlement) ...[
                        const SizedBox(height: 8),
                        Text(tr('Hãy sửa khoản chi / đính kèm rồi bấm Gửi hoạch toán lại.'),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[700]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, double amount,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            tr(label),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr(_currency.format(amount)),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color,
                fontSize: bold ? 16 : 14,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _approvalActions(
      Map<String, dynamic>? advance, Map<String, dynamic>? settlement) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (advance != null && advance['status'] == 0) ...[
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await _api.approveBusinessTripAdvance(
                        widget.caseId,
                        false,
                        rejectionReason: 'Từ chối',
                      );
                      await _reload();
                    },
                    child: Text(tr('Từ chối ứng')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await _api.approveBusinessTripAdvance(
                          widget.caseId, true);
                      await _reload();
                    },
                    child: Text(tr('Duyệt ứng')),
                  ),
                ),
              ]),
            ],
            if (advance != null &&
                advance['status'] == 1 &&
                advance['isPaid'] != true) ...[
              const SizedBox(height: 8),
              if (advance['cashTransactionId'] != null)
                OutlinedButton.icon(
                  onPressed: () =>
                      _openCashVoucher(advance['cashTransactionId']?.toString()),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(tr('Mở phiếu chi ứng (Thu chi)')),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  final method = await _pickPaymentMethod();
                  if (method == null) return;
                  await _api.payBusinessTripAdvance(widget.caseId,
                      paymentMethod: method);
                  await _reload();
                },
                child: Text(tr('Chi ứng ngay')),
              ),
            ],
            if (settlement != null && settlement['status'] == 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _rejectSettlementDialog,
                    child: Text(tr('Từ chối')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _requestSettlementSupplement(),
                    child: Text(tr('Bổ sung GT')),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _approveSettlementWithSurplusCheck,
                child: Text(tr('Duyệt hoạch toán')),
              ),
            ],
            if (settlement != null &&
                settlement['settlementType'] == 1 &&
                settlement['isExtraPaid'] != true) ...[
              const SizedBox(height: 8),
              if (settlement['extraCashTransactionId'] != null)
                OutlinedButton.icon(
                  onPressed: () => _openCashVoucher(
                      settlement['extraCashTransactionId']?.toString()),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(tr('Mở phiếu chi bù (Thu chi)')),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  final method = await _pickPaymentMethod();
                  if (method == null) return;
                  await _api.payBusinessTripSettlementExtra(widget.caseId,
                      paymentMethod: method);
                  await _reload();
                },
                child: Text(tr('Chi bù ngay')),
              ),
            ],
            if (settlement != null &&
                settlement['settlementType'] == 3 &&
                settlement['isExtraPaid'] != true) ...[
              const SizedBox(height: 8),
              Text(tr('Đang chờ thu hoàn dư ứng ${_currency.format((_balance).abs())}'),
                style: const TextStyle(
                    color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
              ),
              if (settlement['extraCashTransactionId'] != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openCashVoucher(
                      settlement['extraCashTransactionId']?.toString()),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(tr('Mở phiếu thu hoàn (Thu chi)')),
                ),
              ],
            ],
            if (settlement != null &&
                settlement['settlementType'] == 2 &&
                settlement['surplusAdvanceRequestId'] != null) ...[
              const SizedBox(height: 8),
              Text(tr('Đã ghi nợ ứng lương ${_currency.format((_balance).abs())} — sẽ trừ kỳ lương'),
                style: TextStyle(color: Colors.grey[700], height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final s = _case?['settlement'];
    final isResubmit = s is Map &&
        (s['rejectionReason']?.toString() ?? '').trim().isNotEmpty;

    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(tr('${_lines.length} khoản'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    tr(_currency.format(_linesTotal)),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  tr(_balance >= 0
                      ? 'Thiếu ${_currency.format(_balance.abs())}'
                      : 'Dư ${_currency.format(_balance.abs())}'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _balance >= 0
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF16A34A),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      _saving || _lines.isEmpty ? null : _submitSettlement,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(tr(isResubmit ? 'Gửi lại' : 'Gửi duyệt')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '—';
    try {
      return _dateFmt.format(DateTime.parse(v.toString()).toLocal());
    } catch (_) {
      return v.toString();
    }
  }
}
