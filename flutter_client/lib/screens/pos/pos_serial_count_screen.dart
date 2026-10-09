import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/api_datetime.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_serial_list_dialog.dart';

/// Kiểm kho theo mã: quét barcode / thẻ RFID (đầu đọc gõ phím, máy kiểm kho cầm tay, dán lô mã) rồi đối chiếu
/// với sổ seri — máy khớp, máy thiếu, mã lạ. Hoàn thành để ghi nhận máy thiếu và cân bằng tồn.
class PosSerialCountScreen extends StatefulWidget {
  const PosSerialCountScreen({super.key});

  @override
  State<PosSerialCountScreen> createState() => _PosSerialCountScreenState();
}

class _PosSerialCountScreenState extends State<PosSerialCountScreen> {
  final _api = ApiService();
  final _scanCtl = TextEditingController();
  final _focus = FocusNode();

  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _d; // phiếu đang mở (có lists)
  final List<Map<String, dynamic>> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  @override
  void dispose() {
    _scanCtl.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(dynamic v) => [
        for (final x in (v as List? ?? const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ];

  int _n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  void _toast(Map<String, dynamic> r, String ok) {
    if (r['isSuccess'] == true) {
      if (ok.isNotEmpty) NotificationOverlayManager().showSuccess(title: 'Kiểm kho theo mã', message: ok);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Kiểm kho theo mã', message: r['message']?.toString() ?? 'Thao tác thất bại');
    }
  }

  Future<void> _loadList() async {
    setState(() => _loading = true);
    final r = await _api.getPosSerialCounts();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _sessions = r['isSuccess'] == true ? _rows((r['data'] as Map?)?['items']) : [];
    });
  }

  Future<void> _open(String id) async {
    final r = await _api.getPosSerialCount(id);
    if (!mounted) return;
    if (r['isSuccess'] != true) return _toast(r, '');
    setState(() {
      _d = Map<String, dynamic>.from(r['data'] as Map);
      _recent.clear();
    });
    _focus.requestFocus();
  }

  Future<void> _refresh() async {
    final id = _d?['id']?.toString();
    if (id == null) return;
    final r = await _api.getPosSerialCount(id);
    if (mounted && r['isSuccess'] == true) setState(() => _d = Map<String, dynamic>.from(r['data'] as Map));
  }

  Future<void> _create() async {
    final nameCtl = TextEditingController();
    var source = 'Barcode';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Phiếu kiểm kho theo mã')),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(labelText: tr('Tên phiếu (không bắt buộc)'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'Barcode', label: Text(tr('Mã vạch / seri')), icon: const Icon(Icons.qr_code_2_rounded)),
                  ButtonSegment(value: 'RFID', label: Text(tr('Thẻ RFID')), icon: const Icon(Icons.sensors_rounded)),
                ],
                selected: {source},
                onSelectionChanged: (s) => setD(() => source = s.first),
              ),
              const SizedBox(height: 8),
              Text(
                tr('Kiểm toàn bộ hàng quản lý theo seri. Mỗi mã quét được đối chiếu với seri hoặc mã thẻ gắn trong sổ.'),
                style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Bắt đầu kiểm'))),
          ],
        ),
      ),
    );
    final name = nameCtl.text.trim();
    nameCtl.dispose();
    if (ok != true) return;
    final r = await _api.createPosSerialCount(name, source);
    if (!mounted) return;
    _toast(r, '');
    if (r['isSuccess'] == true) {
      await _open((r['data'] as Map)['id'].toString());
      _loadList();
    }
  }

  Future<void> _scan(List<String> codes) async {
    final id = _d?['id']?.toString();
    if (id == null || codes.isEmpty) return;
    setState(() => _busy = true);
    final r = await _api.scanPosSerialCount(id, codes, 'app');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] != true) {
      _toast(r, '');
    } else {
      final results = _rows((r['data'] as Map?)?['results']);
      setState(() {
        _recent.insertAll(0, results.reversed);
        if (_recent.length > 60) _recent.removeRange(60, _recent.length);
      });
      await _refresh();
    }
    _focus.requestFocus();
  }

  void _submitScan(String text) {
    _scanCtl.clear();
    _scan(parsePosSerialList(text));
  }

  Future<void> _pasteMany() async {
    final r = await showPosSerialListDialog(
      context,
      productName: 'Dán lô mã quét',
      qty: 0,
      hint: 'Dán danh sách seri / mã thẻ RFID — mỗi mã một dòng',
    );
    if (r != null && r.isNotEmpty) await _scan(r);
  }

  Future<void> _bindTags() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Gắn thẻ RFID cho máy')),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctl,
              minLines: 6,
              maxLines: 12,
              decoration: InputDecoration(
                hintText: tr('Mỗi dòng một cặp: SERI,MÃ_THẺ\nVD: SN12345,E2001234ABCD'),
                border: const OutlineInputBorder(),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Gắn thẻ'))),
        ],
      ),
    );
    final text = ctl.text;
    ctl.dispose();
    if (ok != true) return;
    final items = <Map<String, String>>[];
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final parts = line.split(RegExp(r'[,;\t]'));
      if (parts.length >= 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty) {
        items.add({'serial': parts[0].trim(), 'tagCode': parts[1].trim()});
      }
    }
    if (items.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Gắn thẻ', message: tr('Chưa có cặp seri,mã thẻ hợp lệ'));
      return;
    }
    final r = await _api.bindPosSerialTags(items);
    if (!mounted) return;
    if (r['isSuccess'] != true) return _toast(r, '');
    final d = r['data'] as Map?;
    final errs = (d?['errors'] as List?) ?? const [];
    NotificationOverlayManager().showSuccess(
      title: 'Gắn thẻ RFID',
      message: tr('Đã gắn ${d?['bound'] ?? 0} máy${errs.isEmpty ? '' : ', lỗi ${errs.length}: ${errs.take(3).join('; ')}'}'),
    );
  }

  Future<void> _complete() async {
    final d = _d!;
    var mark = true, adjust = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Hoàn thành kiểm kho')),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('Dự kiến ${_n(d['expected'])} · khớp ${_n(d['matched'])} · thiếu ${_n(d['missing'])} · mã lạ ${_n(d['unknown'])}'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: mark,
                onChanged: (v) => setD(() {
                  mark = v;
                  if (!v) adjust = false;
                }),
                title: Text(tr('Ghi nhận ${_n(d['missing'])} máy thiếu')),
                subtitle: Text(tr('Máy thiếu ra khỏi kho bán; quét thấy lại lần sau sẽ được khôi phục')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: adjust,
                onChanged: mark ? (v) => setD(() => adjust = v) : null,
                title: Text(tr('Cân bằng tồn kho')),
                subtitle: Text(tr('Trừ tồn các mặt hàng theo số máy thiếu')),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Hoàn thành'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final r = await _api.completePosSerialCount(d['id'].toString(), mark, adjust, null);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(r, 'Đã hoàn thành phiếu kiểm');
    if (r['isSuccess'] == true) {
      final na = ((r['data'] as Map?)?['productsNotAdjusted'] as List?) ?? const [];
      if (na.isNotEmpty) {
        NotificationOverlayManager().showWarning(
            title: 'Chưa cân bằng tồn', message: tr('Hàng có biến thể cần chỉnh tay: ${na.join(', ')}'));
      }
      await _refresh();
      _loadList();
    }
  }

  Future<void> _cancel() async {
    final r = await _api.cancelPosSerialCount(_d!['id'].toString());
    if (!mounted) return;
    _toast(r, 'Đã hủy phiếu');
    if (r['isSuccess'] == true) {
      setState(() => _d = null);
      _loadList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inSession = _d != null;
    return PopScope(
      canPop: !inSession,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inSession) {
          setState(() => _d = null);
          _loadList();
        }
      },
      child: Scaffold(
        backgroundColor: SboxColors.slate50,
        appBar: AppBar(
          title: Text(tr(inSession ? '${_d!['countNo']} · ${_d!['name']}' : 'Kiểm kho theo mã')),
          leading: inSession
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () {
                    setState(() => _d = null);
                    _loadList();
                  },
                )
              : null,
          actions: [
            IconButton(
              tooltip: tr('Gắn thẻ RFID cho máy'),
              icon: const Icon(Icons.sensors_rounded),
              onPressed: _bindTags,
            ),
          ],
        ),
        floatingActionButton: inSession
            ? null
            : FloatingActionButton.extended(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: Text(tr('Phiếu kiểm mới')),
              ),
        body: inSession ? _session() : _list(),
      ),
    );
  }

  Widget _list() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tr('Chưa có phiếu kiểm theo mã.\nBấm «Phiếu kiểm mới» rồi quét seri / thẻ RFID để đối chiếu với kho.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: SboxColors.slate500),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadList,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          for (final s in _sessions)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14), side: const BorderSide(color: SboxColors.slate200)),
              child: ListTile(
                onTap: () => _open(s['id'].toString()),
                leading: Icon(s['source'] == 'RFID' ? Icons.sensors_rounded : Icons.qr_code_2_rounded,
                    color: SboxColors.brand600),
                title: Text(tr('${s['countNo']} · ${s['name']}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr(
                    '${_status(s['status'])} · ${_dt(s['startedAt'])}'
                    '${s['status'] == 'Completed' ? ' · thiếu ${_n(s['missingQty'])}/${_n(s['expectedQty'])}' : ''}')),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
        ],
      ),
    );
  }

  String _status(dynamic s) => switch (s) {
        'InProgress' => 'Đang kiểm',
        'Completed' => 'Đã hoàn thành',
        'Cancelled' => 'Đã hủy',
        _ => '$s',
      };

  String _dt(dynamic v) {
    final d = parseApiUtcDateTime(v?.toString())?.toLocal();
    if (d == null) return '';
    String p(int x) => x.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}';
  }

  Widget _stat(String label, int v, Color c, IconData icon) => Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.35)),
          ),
          child: Column(children: [
            Icon(icon, size: 18, color: c),
            Text('$v', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
            Text(tr(label), style: const TextStyle(fontSize: 11, color: SboxColors.slate600), textAlign: TextAlign.center),
          ]),
        ),
      );

  Color _resColor(String? r) => switch (r) {
        'Matched' || 'Recovered' => SboxColors.success,
        'Duplicate' => SboxColors.slate400,
        'Unknown' => SboxColors.danger,
        _ => SboxColors.warning,
      };

  String _resLabel(String? r) => switch (r) {
        'Matched' => 'Khớp',
        'Recovered' => 'Tìm thấy lại',
        'Duplicate' => 'Đã quét',
        'Unknown' => 'Mã lạ',
        'NotInStock' => 'Không còn trong kho',
        'OutOfScope' => 'Ngoài phạm vi',
        _ => '$r',
      };

  Widget _session() {
    final d = _d!;
    final open = d['status'] == 'InProgress';
    final lists = (d['lists'] as Map?) ?? const {};
    List<String> strs(dynamic v) => [for (final x in (v as List? ?? const [])) '$x'];
    final missing = _rows(lists['missing']);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          _stat('Dự kiến trong kho', _n(d['expected']), SboxColors.brand600, Icons.inventory_2_outlined),
          _stat('Đã khớp', _n(d['matched']), SboxColors.success, Icons.check_circle_outline_rounded),
          _stat('Còn thiếu', _n(d['missing']), SboxColors.warning, Icons.hourglass_empty_rounded),
          _stat('Mã lạ', _n(d['unknown']), SboxColors.danger, Icons.help_outline_rounded),
        ]),
        const SizedBox(height: 8),
        if (open)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SboxColors.brand500, width: 1.4),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _scanCtl,
                focusNode: _focus,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: _submitScan,
                decoration: InputDecoration(
                  labelText: tr(d['source'] == 'RFID' ? 'Quét thẻ RFID (đầu đọc tự Enter)' : 'Quét seri / mã vạch (máy quét tự Enter)'),
                  prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send_rounded),
                    onPressed: () => _submitScan(_scanCtl.text),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _pasteMany,
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: Text(tr('Dán / nhập lô mã')),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _complete,
                  icon: const Icon(Icons.task_alt_rounded, size: 18),
                  label: Text(tr('Hoàn thành')),
                ),
                TextButton(onPressed: _busy ? null : _cancel, child: Text(tr('Hủy phiếu'))),
              ]),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Text(tr('${_status(d['status'])} · ${_dt(d['completedAt'])}'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        if (_recent.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('Vừa quét'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (final r in _recent.take(25))
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _resColor(r['result']?.toString()).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                    tr('${r['code']}${r['productName'] != null ? ' · ${r['productName']}' : ''}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(tr(_resLabel(r['result']?.toString())),
                    style: TextStyle(fontWeight: FontWeight.w700, color: _resColor(r['result']?.toString()))),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        _expand('Máy còn thiếu (${_n(d['missing'])})', SboxColors.warning, [
          for (final m in missing) '${m['serial']}${m['tag'] != null ? ' · thẻ ${m['tag']}' : ''} — ${m['productName']}',
        ]),
        _expand('Mã lạ — không có trong sổ (${_n(d['unknown'])})', SboxColors.danger, strs(lists['unknown'])),
        _expand('Không còn trong kho — đã bán / đã xuất (${_n(d['notInStock'])})', SboxColors.warning,
            strs(lists['notInStock'])),
        _expand('Tìm thấy lại máy từng báo thiếu (${_n(d['recovered'])})', SboxColors.success, strs(lists['recovered'])),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _expand(String title, Color c, List<String> items) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), side: const BorderSide(color: SboxColors.slate200)),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(tr(title), style: TextStyle(fontWeight: FontWeight.w700, color: items.isEmpty ? SboxColors.slate500 : c)),
          children: [
            if (items.isEmpty)
              Padding(padding: const EdgeInsets.all(12), child: Text(tr('Không có')))
            else
              for (final i in items.take(300))
                ListTile(dense: true, title: Text(i, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}
