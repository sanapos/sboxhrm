import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_sell_industry_settings_hub_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

final _money = NumberFormat('#,##0', 'vi_VN');
final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');

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
    setState(() {
      _enabled = enabled;
      _open = open;
      _shift = shift;
      _loading = false;
    });
  }

  double _parseCash() {
    final raw = _cashCtrl.text.trim().replaceAll(' ', '').replaceAll('.', '');
    final normalized = raw.replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
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
                  if (!_enabled) _buildDisabled() else if (!_open) _buildOpenForm() else _buildCloseForm(),
                ],
              ),
            ),
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
              'Tính năng tắt mặc định. Bật trong Thiết lập POS → Ngành hàng → '
              '«Ca thu ngân (mở ca / đóng két)» rồi quay lại đây để mở ca.',
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
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Nhập tiền mặt đầu ca trong két. Sau khi mở ca mới được thanh toán.'),
                style: TextStyle(color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cashCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: tr('Tiền mặt đầu ca'),
                  prefixText: '₫ ',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: tr('Ghi chú (không bắt buộc)'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _openShift,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.lock_open_outlined),
                label: Text(tr(_busy ? 'Đang mở…' : 'Mở ca')),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
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
              _kv('Tiền mặt đầu ca', _money.format(opening)),
              _kv('Tiền mặt kỳ vọng', _money.format(expected)),
              Text(
                tr('Kỳ vọng = đầu ca + đơn hoàn thành thanh toán tiền mặt trong ca.'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
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
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cashCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: tr('Tiền mặt đếm được'),
                  prefixText: '₫ ',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: tr('Ghi chú (không bắt buộc)'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB45309)),
                onPressed: _busy ? null : _closeShift,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.lock_outlined),
                label: Text(tr(_busy ? 'Đang đóng…' : 'Đóng ca')),
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
          Expanded(child: Text(tr(label), style: TextStyle(color: Colors.grey.shade700))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
    this.openedByName,
    this.openingCash = 0,
    this.expectedCash,
    this.note,
  });

  final String id;
  final DateTime? openedAt;
  final String? openedByName;
  final double openingCash;
  final double? expectedCash;
  final String? note;

  factory _ShiftSnap.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    DateTime? d(dynamic v) {
      if (v == null) return null;
      final parsed = DateTime.tryParse(v.toString());
      if (parsed == null) return null;
      return parsed.isUtc ? parsed.toLocal() : parsed;
    }

    return _ShiftSnap(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      openedAt: d(json['openedAt'] ?? json['OpenedAt']),
      openedByName: (json['openedByName'] ?? json['OpenedByName'])?.toString(),
      openingCash: n(json['openingCash'] ?? json['OpeningCash']),
      expectedCash: json.containsKey('expectedCash') || json.containsKey('ExpectedCash')
          ? n(json['expectedCash'] ?? json['ExpectedCash'])
          : null,
      note: (json['note'] ?? json['Note'])?.toString(),
    );
  }
}
