import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';

/// Màn nạp theo `deferred as` — bản web tách thành file JS riêng, chỉ tải khi mở lần đầu
/// (giảm main.dart.js). Trên Android / iOS `loadLibrary()` xong ngay.
///
/// ```dart
/// import 'comm/comm_hub_screen.dart' deferred as comm_hub;
/// DeferredScreen(load: comm_hub.loadLibrary, builder: () => comm_hub.CommHubScreen())
/// ```
class DeferredScreen extends StatefulWidget {
  const DeferredScreen({
    super.key,
    required this.load,
    required this.builder,
  });

  final Future<void> Function() load;
  final Widget Function() builder;

  @override
  State<DeferredScreen> createState() => _DeferredScreenState();
}

class _DeferredScreenState extends State<DeferredScreen> {
  late Future<void> _loading = widget.load();

  void _retry() => setState(() => _loading = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done && !snap.hasError) {
          return widget.builder();
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Không tải được màn hình (mạng chập chờn).')),
                const SizedBox(height: 12),
                FilledButton(onPressed: _retry, child: Text(tr('Thử lại'))),
              ],
            ),
          );
        }
        // Thanh mảnh trên cùng thay spinner giữa màn — không nháy bố cục.
        return const Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(minHeight: 2),
        );
      },
    );
  }
}
