import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../models/customer_display_models.dart';
import '../../services/customer_display_sync.dart';
import '../../widgets/pos/pos_theme.dart';

/// Màn hình phụ phía khách: idle = promo ảnh/video; active = menu + hóa đơn.
class PosCustomerDisplayScreen extends StatefulWidget {
  const PosCustomerDisplayScreen({super.key});

  @override
  State<PosCustomerDisplayScreen> createState() =>
      _PosCustomerDisplayScreenState();
}

class _PosCustomerDisplayScreenState extends State<PosCustomerDisplayScreen> {
  final _sync = CustomerDisplaySync.instance;
  final _money = NumberFormat('#,###', 'vi_VN');
  Timer? _idleTimer;
  int _promoIndex = 0;
  VideoPlayerController? _video;
  String? _playingVideoUrl;

  @override
  void initState() {
    super.initState();
    _sync.startListening();
    _sync.addListener(_onSync);
    _restartIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _sync.removeListener(_onSync);
    _disposeVideo();
    super.dispose();
  }

  void _onSync() {
    if (!mounted) return;
    setState(() {});
    final s = _sync.state;
    if (s.isActive) {
      _idleTimer?.cancel();
      _disposeVideo();
    } else {
      _restartIdleTimer();
      _ensurePromoMedia();
    }
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    final sec = _sync.config.idleSeconds.clamp(3, 60);
    _idleTimer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted) return;
      if (_sync.state.isActive) return;
      final items = _promoList;
      if (items.isEmpty) return;
      setState(() {
        _promoIndex = (_promoIndex + 1) % items.length;
      });
      _ensurePromoMedia();
    });
  }

  List<CustomerDisplayPromoItem> get _promoList {
    final fromState = _sync.state.promoItems;
    if (fromState.isNotEmpty) return fromState;
    final videos = _sync.config.promoVideoUrls;
    return [
      for (final u in videos)
        CustomerDisplayPromoItem(title: 'Giới thiệu', videoUrl: u),
    ];
  }

  Future<void> _ensurePromoMedia() async {
    final items = _promoList;
    if (items.isEmpty) return;
    final item = items[_promoIndex % items.length];
    final url = (item.videoUrl ?? '').trim();
    if (url.isEmpty) {
      _disposeVideo();
      return;
    }
    if (_video != null && _playingVideoUrl == url) return;
    _disposeVideo();
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.setLooping(true);
      await c.play();
      setState(() {
        _video = c;
        _playingVideoUrl = url;
      });
    } catch (_) {
      _disposeVideo();
    }
  }

  void _disposeVideo() {
    final v = _video;
    _video = null;
    _playingVideoUrl = null;
    v?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _sync.state;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: s.isActive ? _buildActive(s) : _buildIdle(s),
      ),
    );
  }

  Widget _buildIdle(CustomerDisplayState s) {
    final items = _promoList;
    final store = (s.storeName ?? 'SBOX').trim();
    if (items.isEmpty) {
      return Center(
        key: const ValueKey('idle-empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              store,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Xin chào quý khách',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 22),
            ),
          ],
        ),
      );
    }
    final item = items[_promoIndex % items.length];
    final hasVideo = _video != null && _video!.value.isInitialized;
    return Stack(
      key: ValueKey('idle-$_promoIndex'),
      fit: StackFit.expand,
      children: [
        if (hasVideo)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _video!.value.size.width,
              height: _video!.value.size.height,
              child: VideoPlayer(_video!),
            ),
          )
        else if ((item.imageUrl ?? '').isNotEmpty)
          CachedNetworkImage(
            imageUrl: item.imageUrl!,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(color: const Color(0xFF111827)),
          )
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF0B1220)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.15),
                Colors.black.withValues(alpha: 0.75),
              ],
            ),
          ),
        ),
        Positioned(
          left: 48,
          right: 48,
          bottom: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                store,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 18,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ((item.subtitle ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.subtitle!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 20,
                  ),
                ),
              ],
              if (item.price != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${_money.format(item.price)}đ',
                  style: const TextStyle(
                    color: Color(0xFF5EEAD4),
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActive(CustomerDisplayState s) {
    final table = [
      if ((s.areaName ?? '').isNotEmpty) s.areaName,
      if ((s.tableLabel ?? '').isNotEmpty) s.tableLabel,
    ].whereType<String>().join(' · ');
    return Row(
      key: const ValueKey('active'),
      children: [
        Expanded(
          flex: 5,
          child: Container(
            color: const Color(0xFF111827),
            padding: const EdgeInsets.fromLTRB(28, 28, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  table.isEmpty ? 'Đơn hiện tại' : table,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((s.orderNo ?? '').isNotEmpty || s.guestCount > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if ((s.orderNo ?? '').isNotEmpty) s.orderNo,
                      if (s.guestCount > 0) '${s.guestCount} khách',
                    ].join(' · '),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 16,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Expanded(
                  child: s.lines.isEmpty
                      ? Center(
                          child: Text(
                            'Chưa có món',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 20,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: s.lines.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final l = s.lines[i];
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F2937),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 64,
                                      height: 64,
                                      child: (l.imageUrl ?? '').isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: l.imageUrl!,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) =>
                                                  const ColoredBox(
                                                color: Color(0xFF374151),
                                              ),
                                            )
                                          : const ColoredBox(
                                              color: Color(0xFF374151),
                                              child: Icon(Icons.restaurant,
                                                  color: Colors.white54),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          l.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'SL ${l.qty % 1 == 0 ? l.qty.toStringAsFixed(0) : l.qty.toStringAsFixed(2)}'
                                          '${(l.unitLabel ?? '').isNotEmpty ? ' ${l.unitLabel}' : ''}'
                                          ' × ${_money.format(l.unitPrice)}đ',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.6),
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${_money.format(l.lineTotal)}đ',
                                    style: const TextStyle(
                                      color: Color(0xFF5EEAD4),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Container(
            color: const Color(0xFF0B1220),
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  (s.storeName ?? 'Hóa đơn').trim(),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                _billRow('Tạm tính', '${_money.format(s.subtotal)}đ'),
                if (s.discount > 0) ...[
                  const SizedBox(height: 10),
                  _billRow('Giảm giá', '-${_money.format(s.discount)}đ',
                      accent: true),
                ],
                const SizedBox(height: 18),
                Container(height: 1, color: Colors.white24),
                const SizedBox(height: 18),
                const Text(
                  'TỔNG CỘNG',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_money.format(s.total)}đ',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: PosTheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PosTheme.primary.withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    'Cảm ơn quý khách',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF5EEAD4),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _billRow(String label, String value, {bool accent = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 18,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: accent ? const Color(0xFFFCA5A5) : Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
