import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../models/customer_display_models.dart';
import '../../services/api_service.dart';
import '../../services/customer_display_sync.dart';
import '../../utils/customer_display_media.dart';
import '../../utils/web_route_parser.dart';
import '../../widgets/hrm_page_chrome.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Màn hình phụ phía khách: luôn 2 cột — media | bill (trắng/đen).
/// Không có ảnh/video → panel branding SBOX HRM (giống trang chủ).
class PosCustomerDisplayScreen extends StatefulWidget {
  const PosCustomerDisplayScreen({super.key});

  @override
  State<PosCustomerDisplayScreen> createState() =>
      _PosCustomerDisplayScreenState();
}

class _PosCustomerDisplayScreenState extends State<PosCustomerDisplayScreen> {
  final _sync = CustomerDisplaySync.instance;
  final _api = ApiService();
  final _money = NumberFormat('#,###', 'vi_VN');
  Timer? _idleTimer;
  Timer? _remotePoll;
  int _promoIndex = 0;
  VideoPlayerController? _video;
  String? _playingVideoUrl;
  String? _videoError;
  String _promoFingerprint = '';
  String? _viewerCode;

  static const _billBg = Color(0xFFFFFFFF);
  static const _billFg = Color(0xFF111827);
  static const _billMuted = Color(0xFF6B7280);
  static const _billLine = Color(0xFFE5E7EB);
  static const _mediaBg = Color(0xFF0B1220);

  @override
  void initState() {
    super.initState();
    _viewerCode = parseWebRouteQueryParams()['v']?.trim();
    if ((_viewerCode ?? '').isEmpty) {
      _viewerCode = parseWebRouteQueryParams()['code']?.trim();
    }
    _sync.startListening();
    _sync.addListener(_onSync);
    _restartIdleTimer();
    unawaited(_ensurePromoMedia());
    if ((_viewerCode ?? '').length >= 4) {
      _remotePoll = Timer.periodic(const Duration(milliseconds: 450), (_) {
        unawaited(_pollRemoteState());
      });
      unawaited(_pollRemoteState());
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _remotePoll?.cancel();
    _sync.removeListener(_onSync);
    _disposeVideo();
    super.dispose();
  }

  Future<void> _pollRemoteState() async {
    final code = _viewerCode;
    if (code == null || code.length < 4) return;
    final res = await _api.getPosCustomerDisplayPublicState(code);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final json = (res['data'] as Map)['stateJson']?.toString();
      _sync.applyRemoteStateJson(json);
    }
  }

  void _onSync() {
    if (!mounted) return;
    setState(() {});
    final fp = _promoList
        .map((e) => '${e.videoUrl ?? ''}|${e.imageUrl ?? ''}')
        .join(';');
    if (fp == _promoFingerprint) {
      // Vẫn cập nhật timer nếu idleSeconds đổi.
      _restartIdleTimer();
      return;
    }
    _promoFingerprint = fp;
    _restartIdleTimer();
    unawaited(_ensurePromoMedia());
  }

  int get _idleSeconds {
    final fromState = _sync.state.idleSeconds;
    if (fromState >= 3) return fromState.clamp(3, 60);
    return _sync.config.idleSeconds.clamp(3, 60);
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    final sec = _idleSeconds;
    _idleTimer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted) return;
      final items = _promoList;
      if (items.isEmpty) return;
      // Đang phát video thành công — không nhảy slide (tránh cắt giữa chừng).
      if (_video != null &&
          _video!.value.isInitialized &&
          (_playingVideoUrl ?? '').isNotEmpty) {
        return;
      }
      setState(() {
        _promoIndex = (_promoIndex + 1) % items.length;
      });
      unawaited(_ensurePromoMedia());
    });
  }

  List<CustomerDisplayPromoItem> get _promoList {
    final fromState = _sync.state.promoItems;
    if (fromState.isNotEmpty) return fromState;
    final videos = _sync.config.promoVideoUrls;
    final images = _sync.config.promoImageUrls;
    return [
      for (final u in videos)
        CustomerDisplayPromoItem(title: 'Giới thiệu', videoUrl: u),
      for (final u in images)
        CustomerDisplayPromoItem(title: '', imageUrl: u),
    ];
  }

  String _resolveMediaUrl(String? raw) =>
      resolveCustomerDisplayMediaUrl(_api, raw);

  bool _looksLikeDirectVideo(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('vimeo.com')) {
      return false;
    }
    // Drive/Dropbox đã chuẩn hoá → cho phép.
    if (lower.contains('drive.google.com') ||
        lower.contains('dropbox')) {
      return true;
    }
    return lower.contains('.mp4') ||
        lower.contains('.webm') ||
        lower.contains('.mov') ||
        lower.contains('public-serve') ||
        lower.startsWith('http');
  }

  Future<void> _ensurePromoMedia() async {
    final items = _promoList;
    if (items.isEmpty) {
      _disposeVideo();
      if (mounted) setState(() => _videoError = null);
      return;
    }
    final item = items[_promoIndex % items.length];
    final raw = (item.videoUrl ?? '').trim();
    if (raw.isEmpty) {
      _disposeVideo();
      if (mounted) setState(() => _videoError = null);
      return;
    }
    final url = _resolveMediaUrl(raw);
    if (url.isEmpty || !_looksLikeDirectVideo(url)) {
      _disposeVideo();
      if (mounted) {
        setState(() => _videoError =
            'Video không hợp lệ — dùng URL file .mp4/.webm (không YouTube)');
      }
      return;
    }
    if (_video != null && _playingVideoUrl == url) return;
    _disposeVideo();
    if (mounted) setState(() => _videoError = null);
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
        _videoError = null;
      });
    } catch (e) {
      _disposeVideo();
      if (mounted) {
        setState(() => _videoError = 'Không phát được video');
      }
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
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return Scaffold(
      backgroundColor: _billBg,
      body: wide
          ? Row(
              children: [
                // ~60% media — full khung, không bị bill đè.
                Expanded(flex: 62, child: _buildMediaPane(s)),
                Expanded(flex: 38, child: _buildBillPane(s)),
              ],
            )
          : Column(
              children: [
                Expanded(flex: 55, child: _buildMediaPane(s)),
                Expanded(flex: 45, child: _buildBillPane(s)),
              ],
            ),
    );
  }

  Widget _buildMediaPane(CustomerDisplayState s) {
    final items = _promoList;
    if (items.isEmpty) {
      return _buildBrandFallback(s.storeName);
    }
    final item = items[_promoIndex % items.length];
    final hasVideo = _video != null && _video!.value.isInitialized;
    final imageUrl = _resolveMediaUrl(item.imageUrl);

    // Nền tối + contain: ảnh/video hiện trọn, không bị cắt / che.
    return ColoredBox(
      color: _mediaBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasVideo)
            Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: _video!.value.size.width,
                  height: _video!.value.size.height,
                  child: VideoPlayer(_video!),
                ),
              ),
            )
          else if (imageUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              alignment: Alignment.center,
              errorWidget: (_, __, ___) => _buildBrandFallback(
                s.storeName,
                hint: 'Không tải được ảnh',
              ),
            )
          else if ((_videoError ?? '').isNotEmpty)
            _buildBrandFallback(s.storeName, hint: _videoError)
          else
            _buildBrandFallback(s.storeName),
        ],
      ),
    );
  }

  Widget _buildBrandFallback(String? storeName, {String? hint}) {
    final store = (storeName ?? '').trim();
    return Container(
      key: const ValueKey('brand-fallback'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HrmPageChrome.primaryNavy,
            HrmPageChrome.primaryNavy.withOpacity(0.85),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.storefront_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              tr('SBOX HRM'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(store.isNotEmpty ? store : 'Xin chào quý khách'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 18,
              ),
            ),
            if ((hint ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  tr(hint!),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBillPane(CustomerDisplayState s) {
    final active = s.isActive;
    final table = [
      if ((s.areaName ?? '').isNotEmpty) s.areaName,
      if ((s.tableLabel ?? '').isNotEmpty) s.tableLabel,
    ].whereType<String>().join(' · ');

    return Container(
      color: _billBg,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr((s.storeName ?? 'Hóa đơn').trim()),
            style: const TextStyle(
              color: _billFg,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr(active
                ? (table.isEmpty ? 'Đơn hiện tại' : table)
                : 'Chờ phục vụ'),
            style: const TextStyle(color: _billMuted, fontSize: 14),
          ),
          if (active &&
              ((s.orderNo ?? '').isNotEmpty || s.guestCount > 0)) ...[
            const SizedBox(height: 2),
            Text(
              tr([
                if ((s.orderNo ?? '').isNotEmpty) s.orderNo,
                if (s.guestCount > 0) '${s.guestCount} khách',
              ].join(' · ')),
              style: const TextStyle(color: _billMuted, fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
          Container(height: 1, color: _billLine),
          const SizedBox(height: 12),
          Expanded(
            child: !active || s.lines.isEmpty
                ? Center(
                    child: Text(
                      tr(active ? 'Chưa có món' : 'Xin chào quý khách'),
                      style: const TextStyle(
                        color: _billMuted,
                        fontSize: 18,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: s.lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final l = s.lines[i];
                      final qty = l.qty % 1 == 0
                          ? l.qty.toStringAsFixed(0)
                          : l.qty.toStringAsFixed(2);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(l.name),
                                  style: const TextStyle(
                                    color: _billFg,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tr('SL $qty'
                                  '${(l.unitLabel ?? '').isNotEmpty ? ' ${l.unitLabel}' : ''}'
                                  ' × ${_money.format(l.unitPrice)}đ'),
                                  style: const TextStyle(
                                    color: _billMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(tr('${_money.format(l.lineTotal)}đ'),
                            style: const TextStyle(
                              color: _billFg,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Container(height: 1, color: _billLine),
          const SizedBox(height: 12),
          _billRow('Tạm tính', '${_money.format(s.subtotal)}đ'),
          if (s.discount > 0) ...[
            const SizedBox(height: 6),
            _billRow(
              'Giảm giá',
              '-${_money.format(s.discount)}đ',
              valueColor: const Color(0xFFDC2626),
            ),
          ],
          const SizedBox(height: 10),
          _billRow(
            'TỔNG CỘNG',
            '${_money.format(s.total)}đ',
            emphasize: true,
          ),
          const SizedBox(height: 16),
          Text(tr('Cảm ơn quý khách'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HrmPageChrome.primaryNavy.withOpacity(0.85),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _billRow(
    String label,
    String value, {
    bool emphasize = false,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Text(
          tr(label),
          style: TextStyle(
            color: emphasize ? _billFg : _billMuted,
            fontSize: emphasize ? 16 : 15,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          tr(value),
          style: TextStyle(
            color: valueColor ?? _billFg,
            fontSize: emphasize ? 28 : 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
