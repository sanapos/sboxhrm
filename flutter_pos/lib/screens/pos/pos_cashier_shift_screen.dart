import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_numeric_keypad.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/pos_vnd_thousands_formatter.dart';
import 'pos_sell_industry_settings_hub_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

final _money = NumberFormat('#,##0', 'vi_VN');
final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');
final _timeFmt = DateFormat('HH:mm');

/// Mở ca / đóng ca / đếm két. Chỉ dùng khi bật trong thiết lập ngành hàng.
class PosCashierShiftScreen extends StatefulWidget {
  const PosCashierShiftScreen({super.key});

  @override
  State<PosCashierShiftScreen> createState() => _PosCashierShiftScreenState();
}

class _PosCashierShiftScreenState extends State<PosCashierShiftScreen> {
  final _api = ApiService();
  final _cashCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _enabled = false;
  bool _open = false;
  _ShiftSnap? _shift;
  List<_ShiftSnap> _todayShifts = const [];
  List<_ShiftSnap> _historyShifts = const [];
  int _historyDays = 7;
  bool _historyLoading = false;

  static const _quickAmounts = <int>[
    0,
    100000,
    200000,
    500000,
    1000000,
    2000000,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getPosCashierShiftCurrent();
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được ca thu ngân';
      });
      return;
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final enabled = data['enabled'] == true || data['Enabled'] == true;
    final open = data['open'] == true || data['Open'] == true;
    final raw = data['shift'] ?? data['Shift'];
    final shift = raw is Map
        ? _ShiftSnap.fromJson(Map<String, dynamic>.from(raw))
        : null;
    _cashCtrl.text = '';
    _noteCtrl.text = shift?.note ?? '';

    List<_ShiftSnap> today = const [];
    List<_ShiftSnap> history = const [];
    if (enabled) {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final hist = await _api.getPosCashierShifts(
        from: day,
        to: day,
      );
      if (hist['isSuccess'] == true && hist['data'] is Map) {
        final items = (hist['data'] as Map)['items'];
        if (items is List) {
          today = items
              .whereType<Map>()
              .map((e) => _ShiftSnap.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
      history = await _fetchShiftHistory(days: _historyDays);
    }

    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _open = open;
      _shift = shift;
      _todayShifts = today;
      _historyShifts = history;
      _loading = false;
    });
  }

  Future<List<_ShiftSnap>> _fetchShiftHistory({required int days}) async {
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    final from = to.subtract(Duration(days: days - 1));
    final hist = await _api.getPosCashierShifts(from: from, to: to);
    if (hist['isSuccess'] != true || hist['data'] is! Map) return const [];
    final items = (hist['data'] as Map)['items'];
    if (items is! List) return const [];
    final list = items
        .whereType<Map>()
        .map((e) => _ShiftSnap.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    list.sort((a, b) {
      final ao = a.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bo = b.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bo.compareTo(ao);
    });
    return list;
  }

  Future<void> _loadMoreHistory() async {
    setState(() {
      _historyDays = (_historyDays + 14).clamp(7, 90);
      _historyLoading = true;
    });
    final history = await _fetchShiftHistory(days: _historyDays);
    if (!mounted) return;
    setState(() {
      _historyShifts = history;
      _historyLoading = false;
    });
  }

  double _parseCash() => PosVndThousandsFormatter.parse(_cashCtrl.text);

  void _setCash(num value) {
    _cashCtrl.text = PosVndThousandsFormatter.format(value);
    setState(() {});
  }

  Future<void> _openPad({required String title}) async {
    final next = await showPosNumericKeypad(
      context: context,
      title: title,
      initial: PosVndThousandsFormatter.parse(_cashCtrl.text)
          .round()
          .toString(),
      allowDecimal: false,
    );
    if (next == null || !mounted) return;
    _setCash(PosVndThousandsFormatter.parse(next));
  }

  Future<void> _openShift() async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await _api.openPosCashierShift(
      openingCash: _parseCash(),
      note: _noteCtrl.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không mở ca',
        message: res['message']?.toString() ?? 'Thử lại',
      );
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: 'Đã mở ca',
      message: tr('Có thể thanh toán. Đóng ca khi hết ca để đếm két.'),
    );
    await _load();
  }

  Future<void> _closeShift() async {
    final id = _shift?.id;
    if (_busy || id == null || id.isEmpty) return;
    setState(() => _busy = true);
    final counted = _parseCash();
    final expected = _shift?.expectedCash ?? 0;
    final diff = counted - expected;
    final res = await _api.closePosCashierShift(
      id,
      countedCash: counted,
      note: _noteCtrl.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không đóng ca',
        message: res['message']?.toString() ?? 'Thử lại',
      );
      return;
    }
    final diffLabel = diff == 0
        ? 'khớp két'
        : (diff > 0
            ? 'thừa ${_money.format(diff)}'
            : 'thiếu ${_money.format(-diff)}');
    NotificationOverlayManager().showSuccess(
      title: 'Đã đóng ca',
      message: tr('Đếm ${_money.format(counted)} · $diffLabel'),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final pushed = PosHubScope.pushedSubPageOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: pushed,
        title: Text(tr('Ca thu ngân')),
        actions: [
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                    const SizedBox(height: 12),
                  ],
                  if (!_enabled)
                    _buildDisabled()
                  else if (!_open)
                    _buildOpenForm()
                  else
                    _buildCloseForm(),
                  if (_enabled && _todayShifts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildTodayShifts(),
                  ],
                  if (_enabled &&
                      _historyShifts
                          .any((s) => !_todayShifts.any((t) => t.id == s.id))) ...[
                    const SizedBox(height: 16),
                    _buildShiftHistory(),
                  ],
                  if (_enabled) ...[
                    const SizedBox(height: 12),
                    _buildEodHint(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildEodHint() {
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                'Ca thu ngân = đếm két theo từng lần mở/đóng. '
                'Tổng kết cuối ngày = doanh thu cả ngày (không nhân đôi khi mở 2 ca). '
                'Mỗi ca đóng là một lần đối chiếu két riêng.',
              ),
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayShifts() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Ca hôm nay (${_todayShifts.length})'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            tr('Chạm vào một ca để xem chi tiết tài khoản / tiền két'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          for (final s in _todayShifts) _shiftHistoryTile(s),
        ],
      ),
    );
  }

  Widget _buildShiftHistory() {
    final todayIds = _todayShifts.map((e) => e.id).toSet();
    final older =
        _historyShifts.where((s) => !todayIds.contains(s.id)).toList();
    if (older.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Lịch sử mở/đóng ca ($_historyDays ngày gần nhất)'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            tr('Tài khoản mở · đóng · tiền đầu · đếm · lệch — chạm xem lại'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          for (final s in older) _shiftHistoryTile(s),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _historyLoading || _historyDays >= 90
                  ? null
                  : () => unawaited(_loadMoreHistory()),
              icon: _historyLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history, size: 18),
              label: Text(tr(_historyDays >= 90
                  ? 'Đã tải tối đa 90 ngày'
                  : 'Xem thêm ca cũ')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shiftHistoryTile(_ShiftSnap s) {
    final openBy = (s.openedByName ?? '').trim();
    final closeBy = (s.closedByName ?? '').trim();
    final who = openBy.isNotEmpty
        ? (closeBy.isNotEmpty && closeBy != openBy
            ? 'Mở: $openBy · Đóng: $closeBy'
            : openBy)
        : tr('Không rõ tài khoản');
    final when = [
      if (s.openedAt != null) _dtFmt.format(s.openedAt!),
      if (s.closedAt != null) '→ ${_dtFmt.format(s.closedAt!)}',
    ].join(' ');
    final money = [
      'đầu ${_money.format(s.openingCash)}',
      if (s.countedCash != null) 'đếm ${_money.format(s.countedCash!)}',
      if (s.difference != null) 'lệch ${_money.format(s.difference!)}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showShiftDetail(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: s.status == 'Open'
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tr(s.status == 'Open' ? 'Đang mở' : 'Đã đóng'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: s.status == 'Open'
                          ? const Color(0xFF166534)
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        who,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (when.isNotEmpty)
                        Text(
                          when,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      Text(
                        money,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: Colors.grey.shade500),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showShiftDetail(_ShiftSnap s) {
    final openBy = (s.openedByName ?? '').trim();
    final closeBy = (s.closedByName ?? '').trim();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        Widget row(String label, String value) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    tr(label),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value.isEmpty ? '—' : value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(s.status == 'Open'
                      ? 'Chi tiết ca đang mở'
                      : 'Chi tiết ca đã đóng'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                row('Trạng thái',
                    s.status == 'Open' ? 'Đang mở' : 'Đã đóng'),
                row(
                  'Mở lúc',
                  s.openedAt != null ? _dtFmt.format(s.openedAt!) : '',
                ),
                row('Tài khoản mở ca', openBy),
                row(
                  'Đóng lúc',
                  s.closedAt != null ? _dtFmt.format(s.closedAt!) : '',
                ),
                row('Tài khoản đóng ca', closeBy),
                row('Tiền đầu ca', '${_money.format(s.openingCash)} đ'),
                row(
                  'Tiền đếm két',
                  s.countedCash != null
                      ? '${_money.format(s.countedCash!)} đ'
                      : '',
                ),
                row(
                  'Tiền kỳ vọng',
                  s.expectedCash != null
                      ? '${_money.format(s.expectedCash!)} đ'
                      : '',
                ),
                row(
                  'Chênh lệch',
                  s.difference != null
                      ? '${_money.format(s.difference!)} đ'
                      : '',
                ),
                row('Ghi chú', (s.note ?? '').trim()),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: PosTheme.kiotBlue,
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(tr('Đóng')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDisabled() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Chưa bật ca thu ngân'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Tắt mặc định. Bật tại Thiết lập POS → Ngành hàng & chế độ bán → '
              '«Ca thu ngân». Mỗi tài khoản thu ngân mở ca riêng. '
              'Mở lại Menu ⋮ → Ca thu ngân sau khi bật.',
            ),
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PosHubScope(
                    embeddedInHub: false,
                    pushedSubPage: true,
                    child: PosSellIndustrySettingsHubScreen(),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings_outlined),
            label: Text(tr('Mở thiết lập ngành hàng')),
          ),
        ],
      ),
    );
  }

  Widget _moneyInput({
    required String label,
    required String keypadTitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _cashCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
          inputFormatters: [PosVndThousandsFormatter()],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: tr(label),
            hintText: '0',
            suffixText: 'đ',
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            suffixIcon: IconButton(
              tooltip: tr('Bàn phím số'),
              onPressed: () => _openPad(title: keypadTitle),
              icon: const Icon(Icons.dialpad_outlined),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in _quickAmounts)
              ActionChip(
                label: Text(
                  a == 0 ? tr('0') : _money.format(a),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onPressed: () => _setCash(a),
                backgroundColor: const Color(0xFFEFF6FF),
                side: BorderSide(color: Colors.blue.shade100),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildOpenForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Mở ca'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  'Nhập tiền mặt đầu ca trong két. Mỗi tài khoản mở ca riêng — '
                  'sau khi mở mới thanh toán được trên tài khoản này.',
                ),
                style: TextStyle(color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 16),
              _moneyInput(
                label: 'Tiền mặt đầu ca',
                keypadTitle: 'Tiền mặt đầu ca',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: tr('Ghi chú (không bắt buộc)'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _openShift,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.lock_open_outlined),
                  label: Text(
                    tr(_busy ? 'Đang mở…' : 'Mở ca'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCloseForm() {
    final s = _shift;
    final expected = s?.expectedCash ?? s?.openingCash ?? 0;
    final opening = s?.openingCash ?? 0;
    final counted = _parseCash();
    final hasCount = _cashCtrl.text.trim().isNotEmpty;
    final diff = counted - expected;
    final diffColor = !hasCount
        ? Colors.grey.shade600
        : (diff == 0
            ? const Color(0xFF166534)
            : (diff > 0 ? const Color(0xFFB45309) : const Color(0xFFB91C1C)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tr('Đang mở ca'),
                      style: const TextStyle(
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (s?.openedAt != null)
                    Text(
                      _dtFmt.format(s!.openedAt!),
                      style:
                          TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                ],
              ),
              if ((s?.openedByName ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  tr('Mở bởi ${s!.openedByName}'),
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 16),
              _kv('Tiền mặt đầu ca', '${_money.format(opening)}đ'),
              _kv('Tiền mặt kỳ vọng', '${_money.format(expected)}đ'),
              Text(
                tr(
                  'Kỳ vọng = đầu ca + đơn hoàn thành thanh toán tiền mặt trong ca này.',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Đóng ca / đếm két'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 16),
              _moneyInput(
                label: 'Tiền mặt đếm được',
                keypadTitle: 'Tiền mặt đếm được',
              ),
              if (hasCount) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: diffColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: diffColor.withOpacity(0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(
                          diff == 0
                              ? 'Khớp két'
                              : (diff > 0
                                  ? 'Thừa ${_money.format(diff)}đ'
                                  : 'Thiếu ${_money.format(-diff)}đ'),
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: diffColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr(
                          'Đếm ${_money.format(counted)}đ − kỳ vọng ${_money.format(expected)}đ',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: tr('Ghi chú (không bắt buộc)'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB45309),
                  ),
                  onPressed: _busy ? null : _closeShift,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.lock_outlined),
                  label: Text(
                    tr(_busy ? 'Đang đóng…' : 'Đóng ca'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(tr(label), style: TextStyle(color: Colors.grey.shade700)),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _ShiftSnap {
  const _ShiftSnap({
    required this.id,
    this.openedAt,
    this.closedAt,
    this.openedByName,
    this.closedByName,
    this.openingCash = 0,
    this.countedCash,
    this.expectedCash,
    this.difference,
    this.note,
    this.status = 'Open',
  });

  final String id;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final String? openedByName;
  final String? closedByName;
  final double openingCash;
  final double? countedCash;
  final double? expectedCash;
  final double? difference;
  final String? note;
  final String status;

  factory _ShiftSnap.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    DateTime? d(dynamic v) {
      if (v == null) return null;
      final parsed = DateTime.tryParse(v.toString());
      if (parsed == null) return null;
      return parsed.isUtc ? parsed.toLocal() : parsed;
    }

    return _ShiftSnap(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      openedAt: d(json['openedAt'] ?? json['OpenedAt']),
      closedAt: d(json['closedAt'] ?? json['ClosedAt']),
      openedByName: (json['openedByName'] ?? json['OpenedByName'])?.toString(),
      closedByName: (json['closedByName'] ?? json['ClosedByName'])?.toString(),
      openingCash: n(json['openingCash'] ?? json['OpeningCash']),
      countedCash: json.containsKey('countedCash') ||
              json.containsKey('CountedCash')
          ? n(json['countedCash'] ?? json['CountedCash'])
          : null,
      expectedCash: json.containsKey('expectedCash') ||
              json.containsKey('ExpectedCash')
          ? n(json['expectedCash'] ?? json['ExpectedCash'])
          : null,
      difference: json.containsKey('difference') || json.containsKey('Difference')
          ? n(json['difference'] ?? json['Difference'])
          : null,
      note: (json['note'] ?? json['Note'])?.toString(),
      status: (json['status'] ?? json['Status'] ?? 'Open').toString(),
    );
  }
}
