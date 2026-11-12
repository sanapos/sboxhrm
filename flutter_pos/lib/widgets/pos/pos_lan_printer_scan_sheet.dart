import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../utils/pos_lan_printer_netconfig.dart';
import '../../utils/pos_lan_printer_scan.dart';
import '../../utils/pos_thermal_printer_settings.dart';
import 'pos_lan_printer_ip_dialog.dart';
import 'pos_theme.dart';

Future<PosLanPrinterHit?> showPosLanPrinterScanSheet(BuildContext context) {
  return showModalBottomSheet<PosLanPrinterHit>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => const _LanScanSheet(),
  );
}

class _LanScanSheet extends StatefulWidget {
  const _LanScanSheet();

  @override
  State<_LanScanSheet> createState() => _LanScanSheetState();
}

class _LanScanSheetState extends State<_LanScanSheet> {
  var _cancelled = false;
  var _running = true;
  var _done = 0;
  var _total = 1;
  String? _error;
  String _ranges = '';
  final _hits = <PosLanPrinterHit>[];

  /// Máy in trả lời dò UDP broadcast (kể cả khác lớp mạng).
  final _udp = <PosLanNetDevice>[];
  var _links = <PosLanLink>[];
  var _udpRunning = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _cancelled = false;
      _running = true;
      _done = 0;
      _total = 1;
      _error = null;
      _ranges = '';
      _hits.clear();
      _udp.clear();
    });
    if (kIsWeb) {
      setState(() {
        _running = false;
        _error = 'Quét LAN chỉ dùng trên máy POS / app, không trên web.';
      });
      return;
    }
    final locals = await PosLanPrinterScan.localIpv4s();
    if (!mounted) return;
    if (locals.isEmpty) {
      setState(() {
        _running = false;
        _error =
            'Không thấy IP nội bộ. Kết nối Wi‑Fi hoặc LAN (cùng mạng với máy in) rồi thử lại.';
      });
      return;
    }
    setState(() => _ranges = PosLanPrinterScan.rangesLabel(locals));
    _links = await PosLanNetConfig.localLinks(locals);
    if (!mounted) return;
    unawaited(_discoverUdp());
    final hits = await PosLanPrinterScan.scan(
      isCancelled: () => _cancelled || !mounted,
      onProgress: (done, total, hit) {
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total < 1 ? 1 : total;
          if (hit != null) _hits.add(hit);
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      if (_hits.isEmpty && hits.isNotEmpty) {
        _hits
          ..clear()
          ..addAll(hits);
      }
    });
  }

  Future<void> _discoverUdp() async {
    setState(() => _udpRunning = true);
    await PosLanNetConfig.discover(
      timeout: const Duration(seconds: 3),
      onFound: (d) {
        if (mounted) setState(() => _udp.add(d));
      },
    );
    if (mounted) setState(() => _udpRunning = false);
  }

  /// Máy in ở IP mà máy POS không cùng lớp mạng (không in được trực tiếp).
  bool _otherSubnet(PosLanNetDevice d) =>
      !_links.any((l) => sameSubnet(d.ip, l.ip, l.mask));

  List<PosLanNetDevice> get _udpOther => _udp.where(_otherSubnet).toList();

  /// Máy in cùng lớp mạng chỉ thấy qua UDP (TCP 9100 chưa trả lời).
  List<PosLanNetDevice> get _udpSameOnly => _udp
      .where((d) => !_otherSubnet(d) && !_hits.any((h) => h.host == d.ip))
      .toList();

  PosLanNetDevice? _udpFor(String host) {
    for (final d in _udp) {
      if (d.ip == host) return d;
    }
    return null;
  }

  Future<void> _changeIp(PosLanNetDevice d) async {
    if (!d.canSetIp) {
      await showPosLanPrinterIpHelp(context, device: d);
      return;
    }
    if (_links.isEmpty) return;
    final hit = await showPosLanPrinterIpDialog(
      context,
      device: d,
      links: _links,
      avoid: {for (final h in _hits) h.host, for (final u in _udp) u.ip}..remove(d.ip),
    );
    if (hit == null || !mounted) return;
    Navigator.pop(context, hit);
  }

  Widget _udpTile(PosLanNetDevice d, {required bool other}) {
    final info = [
      if (d.macText.isNotEmpty) 'MAC ${d.macText}',
      if (d.mask != null) 'mask ${d.mask}',
      if (d.dhcp != null) d.dhcp! ? 'DHCP' : 'IP tĩnh',
    ].join(' · ');
    return ListTile(
      leading: Icon(
        other ? Icons.warning_amber_rounded : Icons.print,
        color: other ? Colors.orange.shade800 : PosTheme.kiotBlue,
      ),
      title: Text(d.title),
      subtitle: Text(tr(other
          ? 'Khác lớp mạng với máy này — chưa in được. $info'
          : 'Chưa mở cổng 9100. $info')),
      trailing: other
          ? FilledButton.tonal(
              onPressed: () => _changeIp(d),
              child: Text(tr(d.canSetIp ? 'Đổi IP' : 'Hướng dẫn')),
            )
          : null,
      onTap: () => _changeIp(d),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.62;
    final progress = (_done / _total).clamp(0.0, 1.0);
    return SafeArea(
      child: SizedBox(
        height: h,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Quét máy in LAN'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_running)
                    IconButton(
                      tooltip: tr('Dừng'),
                      onPressed: () => setState(() => _cancelled = true),
                      icon: const Icon(Icons.stop_circle_outlined),
                    )
                  else
                    IconButton(
                      tooltip: tr('Quét lại'),
                      onPressed: _start,
                      icon: const Icon(Icons.refresh),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                tr(
                  'Tìm Zywell / Xprinter / HPRT (cổng 9100) trên mạng nội bộ, '
                  'và máy in Xprinter / Rongta / Epson còn IP khác lớp mạng (dò broadcast).',
                ),
                style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary),
              ),
            ),
            // Máy in khác dải này (vd máy in 192.168.1.x, điện thoại 192.168.0.x) sẽ không quét thấy —
            // nhập thẳng IP rồi In thử.
            if (_ranges.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr('Dải quét: $_ranges'),
                    style: TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                  ),
                ),
              ),
            if (_running) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: _total > 8 ? progress : null,
                  color: PosTheme.kiotBlue,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr('Đã quét $_done/$_total · tìm thấy ${_hits.length}'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr(_error!),
                  style: TextStyle(color: Colors.orange.shade800),
                ),
              ),
            const Divider(height: 16),
            Expanded(
              child: _hits.isEmpty && _udp.isEmpty && !_running && !_udpRunning
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          tr(
                            _error ??
                                'Không thấy máy in cổng 9100.\nKiểm tra máy in cùng Wi‑Fi/LAN, bật RAW 9100, rồi quét lại. Biết IP thì nhập thẳng vào ô IP LAN rồi In thử.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        if (_udpOther.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                            child: Text(
                              tr('Máy in khác lớp mạng (cần đổi IP)'),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        for (final d in _udpOther) _udpTile(d, other: true),
                        for (final h in _hits) _hitTile(h),
                        for (final d in _udpSameOnly) _udpTile(d, other: false),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showPosLanPrinterIpHelp(context),
                  icon: const Icon(Icons.help_outline, size: 18),
                  label: Text(tr('Không thấy máy in? Hướng dẫn đổi IP')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hitTile(PosLanPrinterHit h) {
    final u = _udpFor(h.host);
    return ListTile(
      leading: const Icon(Icons.print, color: PosTheme.kiotBlue),
      title: Text(u?.model != null ? '${u!.model} · ${h.host}:${h.port}' : h.title),
      subtitle: Text(
        tr(
          (h.brand == PosThermalPrinterBrand.generic
                  ? 'ESC/POS · cổng ${h.port}'
                  : '${h.brand.label} · cổng ${h.port}') +
              (u?.dhcp == true ? ' · DHCP — IP có thể nhảy' : u?.dhcp == false ? ' · IP tĩnh' : ''),
        ),
        style: u?.dhcp == true ? TextStyle(color: Colors.orange.shade800) : null,
      ),
      // Máy in DHCP: đặt IP tĩnh để router không đổi IP về sau.
      trailing: u != null && u.canSetIp && u.dhcp == true
          ? TextButton(
              onPressed: () => _changeIp(u),
              child: Text(tr('Đặt IP tĩnh')),
            )
          : null,
      onTap: () => _pick(h, u),
    );
  }

  /// Chọn máy in DHCP: hỏi đặt IP tĩnh trước khi lưu (tránh IP nhảy → mất máy in).
  Future<void> _pick(PosLanPrinterHit h, PosLanNetDevice? u) async {
    if (u != null && u.canSetIp && u.dhcp == true) {
      final yes = await askPosLanPrinterMakeStatic(context, u);
      if (!mounted) return;
      if (yes) {
        await _changeIp(u);
        return;
      }
    }
    Navigator.pop(context, h);
  }
}
