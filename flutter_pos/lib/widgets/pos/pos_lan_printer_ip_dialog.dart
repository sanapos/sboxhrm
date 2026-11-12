import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../utils/pos_lan_printer_netconfig.dart';
import '../../utils/pos_lan_printer_scan.dart';
import 'pos_theme.dart';

/// Đặt IP tĩnh cho máy in (gói SAVE UDP) về cùng lớp mạng với máy POS.
/// Trả về máy in ở IP mới (cổng 9100) khi đã kết nối được — người gọi lưu cấu hình.
Future<PosLanPrinterHit?> showPosLanPrinterIpDialog(
  BuildContext context, {
  required PosLanNetDevice device,
  required List<PosLanLink> links,
  Set<String> avoid = const {},
}) {
  return showDialog<PosLanPrinterHit>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _IpDialog(device: device, links: links, avoid: avoid),
  );
}

/// Hướng dẫn khi máy in không đổi IP qua mạng được (Epson trên app, HPRT, Gprinter…).
Future<void> showPosLanPrinterIpHelp(BuildContext context, {PosLanNetDevice? device}) {
  final epson = device?.proto == PosLanNetProto.epson;
  final lines = <String>[
    if (device != null)
      'Máy in ${device.proto.label} đang ở ${device.ip} — khác lớp mạng nên chưa in được.',
    if (epson) ...[
      'Epson: app chưa đổi IP được qua mạng. Cách nhanh nhất:',
      '• Máy tính Windows cùng mạng: mở SBOX Print Agent → «Khác lớp mạng…» → chọn máy Epson → «Đổi IP» (dùng ARP + ping, cần quyền quản trị).',
      '• Hoặc EpsonNet Config (Epson) — vẫn thấy máy in theo MAC dù khác lớp mạng.',
    ],
    '1. Xem IP hiện tại: tắt máy in, giữ nút FEED rồi bật nguồn, nhả khi máy in trang tự kiểm tra (Self-test). Trang này ghi IP, mask, gateway, DHCP.',
    '2. Đổi IP bằng máy tính: đặt tạm IP tĩnh cho máy tính cùng lớp với máy in (vd. máy in 192.168.123.100 → máy tính 192.168.123.50, mask 255.255.255.0), nối chung switch/router.',
    '3. Mở trình duyệt vào http://<IP máy in> (trang cấu hình) hoặc công cụ của hãng (Xprinter «Printer Tool», Rongta «Ethernet Setting», HPRT «Printer Utility», Gprinter «Ethernet Tool»), đặt IP tĩnh cùng lớp Wi‑Fi cửa hàng (vd. 192.168.1.200), lưu, tắt/bật máy in.',
    '4. Trả máy tính về «Obtain an IP address automatically», rồi quét lại trong app.',
    'Mẹo: nhiều máy in có nút reset mạng (giữ FEED ~10 giây khi đang bật) để về DHCP — router sẽ cấp IP đúng lớp.',
  ];
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Đưa máy in về cùng lớp mạng')),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr(l), style: const TextStyle(fontSize: 13.5)),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đã hiểu'))),
      ],
    ),
  );
}

class _IpDialog extends StatefulWidget {
  const _IpDialog({required this.device, required this.links, required this.avoid});

  final PosLanNetDevice device;
  final List<PosLanLink> links;
  final Set<String> avoid;

  @override
  State<_IpDialog> createState() => _IpDialogState();
}

class _IpDialogState extends State<_IpDialog> {
  final _ip = TextEditingController();
  final _mask = TextEditingController();
  final _gw = TextEditingController();
  late PosLanLink _link;
  var _busy = false;
  var _closed = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _link = widget.links.first;
    _applyLink();
  }

  @override
  void dispose() {
    _closed = true;
    _ip.dispose();
    _mask.dispose();
    _gw.dispose();
    super.dispose();
  }

  void _applyLink() {
    _mask.text = _link.mask;
    _gw.text = _link.gateway;
    _ip.clear();
    final d = widget.device;
    if (sameSubnet(d.ip, _link.ip, _link.mask)) {
      // Đã cùng lớp mạng (máy in DHCP): giữ IP đang dùng, chỉ chuyển sang tĩnh.
      _ip.text = d.ip;
      _status = 'Giữ IP ${d.ip}, chuyển sang IP tĩnh (có thể sửa).';
      return;
    }
    _suggest();
  }

  Future<void> _suggest() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Đang tìm IP trống trong lớp ${_link.ip}/${_link.mask}…';
    });
    final ip = await PosLanNetConfig.suggestFreeIp(_link,
        avoid: widget.avoid, isCancelled: () => _closed);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ip != null) {
        _ip.text = ip;
        _status = 'Gợi ý $ip (chưa thấy máy nào dùng). Có thể sửa.';
      } else {
        _status = null;
        _error = 'Không tìm được IP trống — nhập tay một IP chưa dùng.';
      }
    });
  }

  String? _validate() {
    final ip = _ip.text.trim(), mask = _mask.text.trim(), gw = _gw.text.trim();
    if (parseIpv4(ip) == null) return 'IP mới không hợp lệ.';
    if (!isValidMask(mask)) return 'Subnet mask không hợp lệ (vd. 255.255.255.0).';
    if (parseIpv4(gw) == null) return 'Gateway không hợp lệ.';
    if (!sameSubnet(ip, _link.ip, mask)) {
      return 'IP $ip không cùng lớp mạng với máy này (${_link.ip}).';
    }
    if (!isUsableHost(ip, mask)) return 'IP $ip là địa chỉ mạng / broadcast.';
    if (!sameSubnet(gw, ip, mask)) return 'Gateway phải cùng lớp mạng với IP mới.';
    if (ip == _link.ip) return 'Đây là IP của chính máy này.';
    if (ip == gw) return 'Trùng IP gateway (router).';
    return null;
  }

  Future<void> _apply() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final ip = _ip.text.trim(), mask = _mask.text.trim(), gw = _gw.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Kiểm tra $ip chưa có máy dùng…';
    });
    final keep = ip == widget.device.ip;
    if (!keep && (widget.avoid.contains(ip) || await PosLanNetConfig.isIpInUse(ip))) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
        _error = 'IP $ip đã có thiết bị dùng — chọn IP khác.';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _status = 'Đang gửi cấu hình tới máy in ${widget.device.macText}…');
    try {
      await PosLanNetConfig.sendStaticIp(widget.device, ip: ip, mask: mask, gateway: gw);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
        _error = 'Gửi lệnh thất bại: $e';
      });
      return;
    }
    await _waitAndFinish(ip);
  }

  Future<void> _waitAndFinish(String ip) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Đang chờ máy in lên IP $ip (tối đa 20 giây)…';
    });
    final ok = await PosLanNetConfig.waitForIp(widget.device, ip, isCancelled: () => _closed);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(
        context,
        PosLanPrinterHit(host: ip, port: 9100, brand: widget.device.brand, model: widget.device.model),
      );
      return;
    }
    setState(() {
      _busy = false;
      _status = null;
      _error = 'Chưa kết nối được $ip:9100. Tắt rồi bật lại máy in, chờ ~10 giây, bấm «Thử kết nối lại». '
          'Nếu vẫn không được: in trang tự kiểm tra (giữ FEED khi bật nguồn) xem IP thực tế.';
      _waitedIp = ip;
    });
  }

  String? _waitedIp;

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return AlertDialog(
      title: Text(tr('Đổi IP máy in')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('${d.model ?? d.proto.label} · MAC ${d.macText}\n'
                    'Hiện tại: ${d.ip}${d.mask != null ? ' / ${d.mask}' : ''}'
                    '${d.dhcp == true ? ' (DHCP)' : ''}'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (widget.links.length > 1)
                DropdownButtonFormField<PosLanLink>(
                  // flutter_pos chạy Flutter 3.22: chưa có `initialValue`.
                  value: _link,
                  decoration: InputDecoration(labelText: tr('Mạng của máy này')),
                  items: [
                    for (final l in widget.links)
                      DropdownMenuItem(value: l, child: Text('${l.ip} / ${l.mask}')),
                  ],
                  onChanged: _busy
                      ? null
                      : (l) {
                          if (l == null) return;
                          setState(() => _link = l);
                          _applyLink();
                        },
                ),
              TextField(
                controller: _ip,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: digits,
                decoration: InputDecoration(labelText: tr('IP mới (tĩnh)')),
              ),
              TextField(
                controller: _mask,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: digits,
                decoration: InputDecoration(labelText: tr('Subnet mask')),
              ),
              TextField(
                controller: _gw,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: digits,
                decoration: InputDecoration(labelText: tr('Gateway (router)')),
              ),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr(_status!),
                      style: const TextStyle(fontSize: 12.5, color: PosTheme.textSecondary)),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr(_error!),
                      style: TextStyle(fontSize: 12.5, color: Colors.orange.shade800)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Đóng')),
        ),
        if (!_busy && _waitedIp != null)
          TextButton(
            onPressed: () => _waitAndFinish(_waitedIp!),
            child: Text(tr('Thử kết nối lại')),
          ),
        if (!_busy)
          TextButton(onPressed: _suggest, child: Text(tr('Gợi ý IP khác'))),
        FilledButton(
          onPressed: _busy ? null : _apply,
          child: Text(tr('Đổi IP')),
        ),
      ],
    );
  }
}
