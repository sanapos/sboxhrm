import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../utils/pos_lan_printer_scan.dart';
import '../../utils/pos_thermal_printer_settings.dart';
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
  final _hits = <PosLanPrinterHit>[];

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
      _hits.clear();
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
                        fontSize: 17,
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
                  'Tìm Zywell / Xprinter / HPRT (cổng 9100) trên mạng nội bộ.',
                ),
                style: TextStyle(fontSize: 12.5, color: PosTheme.textSecondary),
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
              child: _hits.isEmpty && !_running
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          tr(
                            _error ??
                                'Không thấy máy in cổng 9100.\nKiểm tra máy in cùng Wi‑Fi/LAN, bật RAW 9100, rồi quét lại.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _hits.length,
                      itemBuilder: (_, i) {
                        final h = _hits[i];
                        return ListTile(
                          leading: Icon(Icons.print, color: PosTheme.kiotBlue),
                          title: Text(h.title),
                          subtitle: Text(
                            tr(
                              h.brand == PosThermalPrinterBrand.generic
                                  ? 'ESC/POS · cổng ${h.port}'
                                  : '${h.brand.label} · cổng ${h.port}',
                            ),
                          ),
                          onTap: () => Navigator.pop(context, h),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
