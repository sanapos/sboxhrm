import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/pos_scale_reader.dart';
import '../notification_overlay.dart';

final _kgFmt = NumberFormat('#,##0.000', 'vi_VN');

/// Khối lượng cân đang đọc (trực tiếp). Bấm → thiết lập cân.
class PosScaleWeightBadge extends StatefulWidget {
  const PosScaleWeightBadge({super.key, this.onTap, this.dense = false});
  final VoidCallback? onTap;
  final bool dense;

  @override
  State<PosScaleWeightBadge> createState() => _PosScaleWeightBadgeState();
}

class _PosScaleWeightBadgeState extends State<PosScaleWeightBadge> {
  @override
  void initState() {
    super.initState();
    // Nạp cấu hình cân của máy, tự nối lại nếu đã bật.
    PosScaleReader.instance.ensureStarted();
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final dense = widget.dense;
    final r = PosScaleReader.instance;
    return AnimatedBuilder(
      animation: r,
      builder: (context, _) {
        final cur = r.current;
        final (text, fg, bg) = !r.settings.enabled
            ? ('Cân: chưa nối', SboxColors.slate600, SboxColors.slate100)
            : r.connecting
                ? ('Cân: đang nối…', SboxColors.slate600, SboxColors.slate100)
                : !r.connected
                    ? ('Cân: mất kết nối', SboxColors.dangerText, SboxColors.dangerSoft)
                    : cur == null
                        ? ('Cân: chờ tín hiệu', SboxColors.warningText, SboxColors.warningSoft)
                        : ('${_kgFmt.format(cur.kg)} kg${cur.stable ? '' : ' …'}',
                            cur.stable ? SboxColors.successText : SboxColors.slate700,
                            cur.stable ? SboxColors.successSoft : SboxColors.slate100);
        return Material(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap ?? () => showPosScaleDeviceDialog(context),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 4 : 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.scale_outlined, size: dense ? 15 : 17, color: fg),
                const SizedBox(width: 5),
                Text(tr(text),
                    style: TextStyle(
                        fontSize: dense ? 12 : 13.5,
                        fontWeight: FontWeight.w700,
                        color: fg,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Thiết lập cân nối máy này: cổng, tốc độ, lệnh hỏi, xem khối lượng trực tiếp.
Future<void> showPosScaleDeviceDialog(BuildContext context) async {
  await PosScaleReader.instance.ensureStarted();
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => const _ScaleDeviceDialog());
}

class _ScaleDeviceDialog extends StatefulWidget {
  const _ScaleDeviceDialog();

  @override
  State<_ScaleDeviceDialog> createState() => _ScaleDeviceDialogState();
}

class _ScaleDeviceDialogState extends State<_ScaleDeviceDialog> {
  final _reader = PosScaleReader.instance;
  late PosScaleDeviceSettings _s = _reader.settings;
  List<String> _ports = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPorts();
  }

  Future<void> _loadPorts() async {
    final p = await _reader.listPorts();
    if (mounted) setState(() => _ports = p);
  }

  Future<void> _apply({bool enable = true}) async {
    setState(() => _busy = true);
    await _reader.updateSettings(_s.copyWith(enabled: enable));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _s = _reader.settings;
    });
    if (enable && !_reader.connected) {
      NotificationOverlayManager().showError(title: 'Chưa nối được cân', message: _reader.error ?? '');
    }
  }

  Future<void> _pickWebPort() async {
    final r = await _reader.requestWebPort();
    if (r == null) return;
    _s = _s.copyWith(webUsbVendorId: r.vendorId, webUsbProductId: r.productId);
    await _loadPorts();
    await _apply();
  }

  @override
  Widget build(BuildContext context) {
    final supported = _reader.supported;
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.scale_outlined),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('Cân điện tử nối máy này'))),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: !supported
              ? Text(tr(_reader.unsupportedReason))
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(
                    tr(_reader.isWeb
                        ? 'Cân nối máy tính qua cáp USB / RS232-USB. Bấm «Chọn cổng cân» → chọn cổng của cân '
                            '(trình duyệt hỏi quyền một lần). Chỉ Chrome / Edge.'
                        : 'Cân nối qua cổng RS232 hoặc cáp USB-Serial (hiện thành COMx trong Device Manager). '
                            'Chọn cổng và tốc độ đúng như cài trên cân.'),
                    style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600),
                  ),
                  const SizedBox(height: 12),
                  Center(child: PosScaleWeightBadge(onTap: () {})),
                  if (_reader.error != null && _s.enabled) ...[
                    const SizedBox(height: 6),
                    Text(tr(_reader.error!),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: SboxColors.dangerText)),
                  ],
                  const SizedBox(height: 12),
                  if (_reader.isWeb)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickWebPort,
                      icon: const Icon(Icons.usb),
                      label: Text(tr(_ports.isEmpty ? 'Chọn cổng cân' : 'Chọn cổng cân khác (${_ports.join(', ')})')),
                    )
                  else
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _ports.contains(_s.port) ? _s.port : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: tr('Cổng COM'),
                            helperText: tr(_ports.isEmpty ? 'Không thấy cổng COM — cắm cáp cân, cài driver USB-Serial' : ''),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [for (final p in _ports) DropdownMenuItem(value: p, child: Text(p))],
                          onChanged: (v) => setState(() => _s = _s.copyWith(port: v ?? '')),
                        ),
                      ),
                      IconButton(onPressed: _loadPorts, icon: const Icon(Icons.refresh), tooltip: tr('Tìm lại cổng')),
                    ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _s.baudRate,
                        decoration: InputDecoration(
                            labelText: tr('Tốc độ (baud)'), border: const OutlineInputBorder(), isDense: true),
                        items: [
                          for (final b in const [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200])
                            DropdownMenuItem(value: b, child: Text('$b')),
                        ],
                        onChanged: (v) => setState(() => _s = _s.copyWith(baudRate: v)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: '${_s.dataBits}${_s.parity[0].toUpperCase()}${_s.stopBits}',
                        decoration: InputDecoration(
                            labelText: tr('Khung dữ liệu'), border: const OutlineInputBorder(), isDense: true),
                        items: [
                          for (final f in const ['8N1', '7E1', '7O1', '8E1', '8N2'])
                            DropdownMenuItem(value: f, child: Text(f)),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _s = _s.copyWith(
                                dataBits: int.parse(v[0]),
                                parity: switch (v[1]) { 'E' => 'even', 'O' => 'odd', _ => 'none' },
                                stopBits: int.parse(v[2]),
                              ));
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PosScalePoll>(
                    value: _s.poll,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: tr('Cách lấy số'), border: const OutlineInputBorder(), isDense: true),
                    items: [
                      for (final p in PosScalePoll.values)
                        DropdownMenuItem(value: p, child: Text(tr(p.label), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _s = _s.copyWith(poll: v)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _s.unitWhenMissing,
                    decoration: InputDecoration(
                        labelText: tr('Cân gửi số không kèm đơn vị thì hiểu là'),
                        border: const OutlineInputBorder(),
                        isDense: true),
                    items: [
                      DropdownMenuItem(value: 'kg', child: Text(tr('kg (vd 0.456)'))),
                      DropdownMenuItem(value: 'g', child: Text(tr('gram (vd 456)'))),
                    ],
                    onChanged: (v) => setState(() => _s = _s.copyWith(unitWhenMissing: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Màn bán: chọn hàng cân thì lấy luôn khối lượng')),
                    subtitle: Text(tr('Hàng bán theo kg / gram / lạng: đặt hàng lên cân rồi chọn hàng → SL = số trên cân. '
                        'F7 = lấy lại khối lượng cho dòng vừa chọn.')),
                    value: _s.autoWeighOnSell,
                    onChanged: (v) => setState(() => _s = _s.copyWith(autoWeighOnSell: v)),
                  ),
                ]),
        ),
      ),
      actions: [
        if (supported && _s.enabled)
          TextButton(
            onPressed: _busy ? null : () => _apply(enable: false),
            child: Text(tr('Ngắt cân')),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Đóng'))),
        if (supported)
          FilledButton(
            onPressed: _busy ? null : () => _apply(),
            child: Text(tr(_busy ? 'Đang nối…' : 'Lưu & nối cân')),
          ),
      ],
    );
  }
}
