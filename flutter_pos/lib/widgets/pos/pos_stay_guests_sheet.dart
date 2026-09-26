import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../notification_overlay.dart';

/// Khách lưu trú của một lượt nhận phòng (khách sạn) — thông tin khai báo tạm trú.
Future<void> showPosStayGuestsSheet(
  BuildContext context, {
  required String sessionId,
  required String roomLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StayGuestsSheet(sessionId: sessionId, roomLabel: roomLabel),
  );
}

class _StayGuestsSheet extends StatefulWidget {
  const _StayGuestsSheet({required this.sessionId, required this.roomLabel});
  final String sessionId;
  final String roomLabel;

  @override
  State<_StayGuestsSheet> createState() => _StayGuestsSheetState();
}

class _StayGuestsSheetState extends State<_StayGuestsSheet> {
  final _api = ApiService();
  final _dateFmt = DateFormat('dd/MM/yyyy');
  bool _loading = true;
  List<Map<String, dynamic>> _guests = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.getPosStayGuests(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _guests = res['isSuccess'] == true && res['data'] is List
          ? (res['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const [];
    });
  }

  Future<void> _edit([Map<String, dynamic>? g]) async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _GuestDialog(initial: g, isFirst: _guests.isEmpty),
    );
    if (body == null || !mounted) return;
    body['resourceSessionId'] = widget.sessionId;
    final res = g == null
        ? await _api.createPosStayGuest(body)
        : await _api.updatePosStayGuest('${g['id']}', body);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
          title: 'Không lưu được', message: res['message']?.toString() ?? '');
      return;
    }
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa khách lưu trú?')),
        content: Text('${g['fullName']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xóa'))),
        ],
      ),
    );
    if (ok != true) return;
    await _api.deletePosStayGuest('${g['id']}');
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${tr('Khách lưu trú')} · ${widget.roomLabel}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: Text(tr('Thêm khách')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(tr('Dùng khai báo tạm trú — xem / xuất Excel ở «Sổ khách lưu trú».'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_guests.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('Chưa có khách nào — bấm «Thêm khách».'), textAlign: TextAlign.center),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final g in _guests)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      elevation: 0,
                      child: ListTile(
                        leading: Icon(g['isPrimary'] == true ? Icons.star : Icons.person_outline,
                            color: g['isPrimary'] == true ? Colors.amber.shade700 : null),
                        title: Text('${g['fullName']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([
                          '${g['idType'] ?? 'CCCD'}: ${g['idNumber'] ?? '—'}',
                          if (DateTime.tryParse('${g['dateOfBirth']}') case final d?) _dateFmt.format(d),
                          if ((g['nationality'] ?? '').toString().isNotEmpty) '${g['nationality']}',
                          if ((g['phone'] ?? '').toString().isNotEmpty) '${g['phone']}',
                        ].join(' · ')),
                        onTap: () => _edit(g),
                        trailing: IconButton(
                          tooltip: tr('Xóa'),
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFB91C1C)),
                          onPressed: () => _delete(g),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GuestDialog extends StatefulWidget {
  const _GuestDialog({this.initial, required this.isFirst});
  final Map<String, dynamic>? initial;
  final bool isFirst;

  @override
  State<_GuestDialog> createState() => _GuestDialogState();
}

class _GuestDialogState extends State<_GuestDialog> {
  late final _name = TextEditingController(text: widget.initial?['fullName']?.toString() ?? '');
  late final _idNo = TextEditingController(text: widget.initial?['idNumber']?.toString() ?? '');
  late final _nat = TextEditingController(text: widget.initial?['nationality']?.toString() ?? 'Việt Nam');
  late final _addr = TextEditingController(text: widget.initial?['address']?.toString() ?? '');
  late final _phone = TextEditingController(text: widget.initial?['phone']?.toString() ?? '');
  late final _note = TextEditingController(text: widget.initial?['note']?.toString() ?? '');
  late String _idType = widget.initial?['idType']?.toString() ?? 'CCCD';
  late String? _gender = widget.initial?['gender']?.toString();
  late DateTime? _dob = DateTime.tryParse('${widget.initial?['dateOfBirth']}');
  late bool _primary = widget.initial?['isPrimary'] == true || (widget.initial == null && widget.isFirst);

  @override
  void dispose() {
    for (final c in [_name, _idNo, _nat, _addr, _phone, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration _deco(String label) => InputDecoration(
        labelText: tr(label),
        isDense: true,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(widget.initial == null ? 'Thêm khách lưu trú' : 'Sửa khách lưu trú')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, decoration: _deco('Họ và tên *'), textCapitalization: TextCapitalization.words),
              const SizedBox(height: 10),
              Row(children: [
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<String>(
                    value: const ['CCCD', 'Hộ chiếu', 'Khác'].contains(_idType) ? _idType : 'Khác',
                    decoration: _deco('Giấy tờ'),
                    items: [
                      for (final t in const ['CCCD', 'Hộ chiếu', 'Khác'])
                        DropdownMenuItem(value: t, child: Text(tr(t))),
                    ],
                    onChanged: (v) => setState(() => _idType = v ?? 'CCCD'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _idNo, decoration: _deco('Số giấy tờ'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                        initialDate: _dob ?? DateTime(1990),
                      );
                      if (d != null) setState(() => _dob = d);
                    },
                    icon: const Icon(Icons.cake_outlined, size: 18),
                    label: Text(_dob == null ? tr('Ngày sinh') : DateFormat('dd/MM/yyyy').format(_dob!)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<String?>(
                    value: const ['Nam', 'Nữ', 'Khác'].contains(_gender) ? _gender : null,
                    decoration: _deco('Giới tính'),
                    items: [
                      for (final t in const ['Nam', 'Nữ', 'Khác'])
                        DropdownMenuItem(value: t, child: Text(tr(t))),
                    ],
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(controller: _nat, decoration: _deco('Quốc tịch')),
              const SizedBox(height: 10),
              TextField(controller: _addr, decoration: _deco('Địa chỉ thường trú'), maxLines: 2),
              const SizedBox(height: 10),
              TextField(controller: _phone, decoration: _deco('Điện thoại'), keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              TextField(controller: _note, decoration: _deco('Ghi chú')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _primary,
                onChanged: (v) => setState(() => _primary = v ?? false),
                title: Text(tr('Người đứng tên nhận phòng')),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) {
              NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: tr('Nhập họ tên khách'));
              return;
            }
            Navigator.pop(context, {
              'fullName': _name.text.trim(),
              'idType': _idType,
              'idNumber': _idNo.text.trim(),
              if (_dob != null) 'dateOfBirth': DateTime(_dob!.year, _dob!.month, _dob!.day).toIso8601String(),
              'gender': _gender,
              'nationality': _nat.text.trim(),
              'address': _addr.text.trim(),
              'phone': _phone.text.trim(),
              'note': _note.text.trim(),
              'isPrimary': _primary,
            });
          },
          child: Text(tr('Lưu')),
        ),
      ],
    );
  }
}
