import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../models/customer_display_models.dart';
import '../../services/api_service.dart';
import '../../services/customer_display_sync.dart';
import '../../utils/customer_display_media.dart';
import '../../utils/web_route_parser.dart';
import '../../widgets/hrm_page_chrome.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Màn hình phụ phía khách.
/// - Chờ khách: ảnh / video chiếu TOÀN màn (tên cửa hàng góc dưới).
/// - Đang bán: màn ngang → media | hóa đơn; màn dọc → dải media 16:9 trên, hóa đơn dưới.
/// - Chữ / mã QR co giãn theo cạnh ngắn của màn (7″ 1024×600 … TV 1920×1080).
/// - Video: tiếng theo thiết lập «Bật tiếng video» (trình duyệt chặn tự phát có tiếng → phát tắt tiếng,
///   hiện nút «Chạm để bật tiếng»); phát hết rồi sang mục kế; lỗi / treo → bỏ qua.
/// Không có ảnh/video → panel branding SBOX.
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
  bool _awaitingRemote = false;
  String? _remoteStatus;

  /// Tăng mỗi lần đổi media — kết quả khởi tạo video cũ (chậm) bị bỏ, không rò controller.
  int _mediaGen = 0;
  bool _advancing = false;

  /// Trình duyệt chặn tự phát có tiếng → đang phát tắt tiếng, chờ khách chạm để bật.
  bool _soundBlocked = false;

  static const _billBg = Color(0xFFFFFFFF);
  static const _billFg = SboxColors.slate900;
  static const _billMuted = SboxColors.slate500;
  static const _billLine = SboxColors.slate200;
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
    _promoFingerprint = _fingerprint();
    _restartIdleTimer();
    unawaited(_ensurePromoMedia());
    if ((_viewerCode ?? '').length >= 4) {
      _remotePoll = Timer.periodic(const Duration(milliseconds: 1500), (_) {
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
    _mediaGen++;
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
      if (json != null && json.isNotEmpty) {
        _sync.applyRemoteStateJson(json);
        if (_awaitingRemote || _remoteStatus != null) {
          setState(() {
            _awaitingRemote = false;
            _remoteStatus = null;
          });
        }
        return;
      }
    }
    if (!_awaitingRemote || _remoteStatus == null) {
      setState(() {
        _awaitingRemote = true;
        _remoteStatus =
            'Đang chờ máy thu ngân… (mã $code) — mở bán hàng và bấm truyền màn phụ';
      });
    }
  }

  String _fingerprint() => _promoList
      .map((e) => '${e.videoUrl ?? ''}|${e.imageUrl ?? ''}')
      .join(';');

  /// Thiết lập «Bật tiếng video»: state do máy thu ngân đóng dấu (máy xem từ xa chỉ có state).
  bool get _wantSound => _sync.state.updatedAtMs > 0 ? _sync.state.videoSound : _sync.config.videoSound;

  void _onSync() {
    if (!mounted) return;
    setState(() {});
    // Đổi thiết lập tiếng khi video đang phát.
    final v = _video;
    if (v != null && v.value.isInitialized && !_soundBlocked) {
      final want = _wantSound ? 1.0 : 0.0;
      if (v.value.volume != want) unawaited(v.setVolume(want));
    }
    final fp = _fingerprint();
    if (fp == _promoFingerprint) {
      // Vẫn cập nhật timer nếu idleSeconds đổi.
      _restartIdleTimer();
      return;
    }
    _promoFingerprint = fp;
    final n = _promoList.length;
    if (n > 0 && _promoIndex >= n) _promoIndex = 0;
    _restartIdleTimer();
    unawaited(_ensurePromoMedia());
  }

  int get _idleSeconds {
    final fromState = _sync.state.idleSeconds;
    if (fromState >= 3) return fromState.clamp(3, 60);
    return _sync.config.idleSeconds.clamp(3, 60);
  }

  bool get _videoPlaying =>
      _video != null &&
      _video!.value.isInitialized &&
      !_video!.value.hasError &&
      (_playingVideoUrl ?? '').isNotEmpty;

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    final sec = _idleSeconds;
    _idleTimer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted) return;
      // Video đang phát: chờ phát hết (listener tự chuyển), không cắt giữa chừng.
      if (_videoPlaying) return;
      _next();
    });
  }

  /// Sang mục trình chiếu kế tiếp.
  void _next() {
    final items = _promoList;
    if (items.isEmpty || !mounted) return;
    setState(() => _promoIndex = (_promoIndex + 1) % items.length);
    unawaited(_ensurePromoMedia());
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
    return lower.startsWith('http');
  }

  /// Máy Android: lần đầu phát qua mạng và tải file về bộ nhớ đệm; các vòng sau phát từ file
  /// (không tải lại video mỗi lượt, không bị Drive giới hạn lượt tải).
  Future<VideoPlayerController> _videoControllerFor(String url) async {
    if (!kIsWeb) {
      try {
        final cached = await DefaultCacheManager().getFileFromCache(url);
        if (cached != null) return VideoPlayerController.file(cached.file);
        unawaited(DefaultCacheManager().downloadFile(url).then((_) {}, onError: (_) {}));
      } catch (_) {}
    }
    return VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
  }

  /// Tải trước ảnh của mục kế tiếp — chuyển slide không còn khoảng tối chờ tải ảnh.
  void _precacheNext(List<CustomerDisplayPromoItem> items) {
    if (items.length < 2 || !mounted) return;
    final next = items[(_promoIndex + 1) % items.length];
    if ((next.videoUrl ?? '').trim().isNotEmpty) return;
    final url = _resolveMediaUrl(next.imageUrl);
    if (url.isEmpty) return;
    // Sau khung hình: precacheImage đọc MediaQuery, không gọi được ngay trong initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(precacheImage(CachedNetworkImageProvider(url), context).catchError((_) {}));
    });
  }

  Future<void> _ensurePromoMedia() async {
    final gen = ++_mediaGen;
    final items = _promoList;
    if (items.isEmpty) {
      _disposeVideo();
      if (mounted) setState(() => _videoError = null);
      return;
    }
    final item = items[_promoIndex % items.length];
    _precacheNext(items);
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
            'Video không hợp lệ — dùng link file .mp4 / Google Drive (không YouTube)');
      }
      return;
    }
    if (_video != null && _playingVideoUrl == url) {
      // Cùng video (danh sách chỉ có 1 mục) — phát lại từ đầu nếu đã dừng.
      _video!.setLooping(items.length == 1);
      if (!_video!.value.isPlaying) {
        await _video!.seekTo(Duration.zero);
        await _video!.play();
      }
      return;
    }
    _disposeVideo();
    if (mounted) setState(() => _videoError = null);
    VideoPlayerController? c;
    try {
      c = await _videoControllerFor(url);
      await c.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || gen != _mediaGen) {
        await c.dispose();
        return;
      }
      await c.setLooping(items.length == 1);
      final ctrl = c;
      ctrl.addListener(() => _onVideoTick(ctrl, gen));
      final blocked = await _playWithSoundSetting(ctrl);
      if (!mounted || gen != _mediaGen) {
        await c.dispose();
        return;
      }
      setState(() {
        _video = c;
        _playingVideoUrl = url;
        _videoError = null;
        _soundBlocked = blocked;
      });
    } catch (_) {
      await c?.dispose();
      if (!mounted || gen != _mediaGen) return;
      _disposeVideo();
      setState(() => _videoError = 'Không phát được video — chuyển mục khác');
      // Bỏ qua video hỏng thay vì đứng ở màn lỗi.
      if (items.length > 1) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && gen == _mediaGen) _next();
        });
      }
    }
  }

  /// Phát theo thiết lập tiếng. Trả true nếu trình duyệt chặn phát có tiếng (đã chuyển sang tắt tiếng).
  /// Android / iOS không chặn; trình duyệt chỉ cho phát có tiếng sau khi người xem chạm vào trang.
  Future<bool> _playWithSoundSetting(VideoPlayerController c) async {
    if (!_wantSound) {
      await c.setVolume(0);
      await c.play();
      return false;
    }
    if (!kIsWeb) {
      await c.setVolume(1);
      await c.play();
      return false;
    }
    // Trình duyệt: phát có tiếng khi chưa có thao tác của người xem sẽ bị từ chối (và plugin báo lỗi video).
    // Luôn bắt đầu tắt tiếng (được phép), rồi mới bật tiếng: bị chặn thì trình duyệt dừng video →
    // quay lại tắt tiếng và hiện nút «Chạm để bật tiếng».
    await c.setVolume(0);
    await c.play();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await c.setVolume(1);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (c.value.isPlaying && !c.value.hasError) return false;
    await c.setVolume(0);
    await c.play();
    return true;
  }

  Future<void> _unblockSound() async {
    final v = _video;
    if (v == null) return;
    await v.setVolume(1);
    if (!v.value.isPlaying) await v.play();
    if (mounted) setState(() => _soundBlocked = false);
  }

  /// Phát hết (khi có nhiều mục) hoặc lỗi giữa chừng → sang mục kế.
  void _onVideoTick(VideoPlayerController c, int gen) {
    if (gen != _mediaGen || _advancing || !identical(c, _video)) return;
    final v = c.value;
    final ended = v.isInitialized &&
        !v.isLooping &&
        v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 300) &&
        !v.isPlaying;
    if (!ended && !v.hasError) return;
    _advancing = true;
    scheduleMicrotask(() {
      _advancing = false;
      if (!mounted || gen != _mediaGen) return;
      if (_promoList.length > 1) {
        _next();
      } else {
        unawaited(c.seekTo(Duration.zero).then((_) => c.play()));
      }
    });
  }

  void _disposeVideo() {
    final v = _video;
    _video = null;
    _playingVideoUrl = null;
    _soundBlocked = false;
    v?.dispose();
  }

  bool _paymentConfirmed(CustomerDisplayState s) =>
      (s.paymentStatus ?? '').toLowerCase() == 'confirmed';

  bool _hasQr(CustomerDisplayState s) =>
      !_paymentConfirmed(s) && (s.paymentQrUrl ?? '').isNotEmpty;

  Widget _buildQrPanel(CustomerDisplayState s, double scale) {
    return ColoredBox(
      key: const ValueKey('qr-panel'),
      color: const Color(0xFFF1F5F9),
      child: LayoutBuilder(builder: (context, c) {
        final qr = math.min(c.maxWidth * 0.8, c.maxHeight - 150 * scale).clamp(120.0, 560.0);
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr((s.paymentStatus ?? '').toLowerCase() == 'waiting'
                      ? 'Quét mã để chuyển khoản'
                      : 'Mã QR thanh toán'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _billFg, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_money.format(s.total)}đ',
                  style: const TextStyle(color: SboxColors.danger, fontSize: 30, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Container(
                  width: qr + 16,
                  height: qr + 16,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 4))],
                  ),
                  child: CachedNetworkImage(
                    imageUrl: s.paymentQrUrl!,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => Icon(Icons.qr_code_2, size: qr * 0.5, color: _billMuted),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPaidPanel(CustomerDisplayState s, double scale) {
    return ColoredBox(
      key: const ValueKey('paid-panel'),
      color: SboxColors.successSoft,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, color: SboxColors.success, size: 96 * scale),
              const SizedBox(height: 12),
              Text(
                tr((s.paymentConfirmedMessage ?? 'Đã nhận chuyển khoản').trim()),
                textAlign: TextAlign.center,
                style: const TextStyle(color: SboxColors.successText, fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Cảm ơn quý khách'),
                style: const TextStyle(color: SboxColors.successText, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _showBill(CustomerDisplayState s) =>
      s.isActive ||
      (s.paymentQrUrl ?? '').isNotEmpty ||
      (s.paymentStatus ?? '').toLowerCase() == 'confirmed';

  @override
  Widget build(BuildContext context) {
    final s = _sync.state;
    final body = LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        // 600 px cạnh ngắn = cỡ chuẩn (màn 7″ 1024×600); TV 1080p → ×1.8.
        final scale = (math.min(w, h) / 600).clamp(0.8, 2.0).toDouble();
        Widget content;
        if (!_showBill(s)) {
          content = _buildMediaPane(s, scale, idle: true);
        } else if (w >= h * 1.1) {
          final billW = (w * 0.38).clamp(300 * scale, math.max(300 * scale, w * 0.5)).toDouble();
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildMediaPane(s, scale)),
              SizedBox(width: math.min(billW, w * 0.6), child: _buildBillPane(s, scale)),
            ],
          );
        } else {
          // Màn dọc / vuông: dải media đúng 16:9 theo bề ngang, phần còn lại cho hóa đơn.
          final mediaH = math.min(w * 9 / 16, h * 0.42);
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: mediaH, child: _buildMediaPane(s, scale)),
              Expanded(child: _buildBillPane(s, scale)),
            ],
          );
        }
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: content,
        );
      },
    );
    return Scaffold(
      backgroundColor: _billBg,
      // Thông báo chờ máy thu ngân nằm trên cùng, đẩy nội dung xuống — trước đây nổi đè lên tiêu đề hóa đơn.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_awaitingRemote && (_remoteStatus ?? '').isNotEmpty)
            Material(
              color: const Color(0xFF1E3A8A),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    _remoteStatus!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildMediaPane(CustomerDisplayState s, double scale, {bool idle = false}) {
    // Đang chờ chuyển khoản / vừa nhận tiền: vùng media lớn dành cho mã QR / xác nhận (dễ quét trên màn 7″).
    if (!idle && _paymentConfirmed(s)) return _buildPaidPanel(s, scale);
    if (!idle && _hasQr(s)) return _buildQrPanel(s, scale);
    final items = _promoList;
    if (items.isEmpty) {
      return _buildBrandFallback(s.storeName, scale: scale);
    }
    final item = items[_promoIndex % items.length];
    final hasVideo = _video != null && _video!.value.isInitialized;
    final imageUrl = (item.videoUrl ?? '').trim().isEmpty ? _resolveMediaUrl(item.imageUrl) : '';
    final caption = item.title.trim() == 'Giới thiệu' ? '' : item.title.trim();
    final store = (s.storeName ?? '').trim();

    Widget media;
    if (hasVideo) {
      media = Center(
        key: ValueKey('v:$_playingVideoUrl'),
        child: AspectRatio(
          aspectRatio: _video!.value.aspectRatio > 0 ? _video!.value.aspectRatio : 16 / 9,
          child: VideoPlayer(_video!),
        ),
      );
    } else if (imageUrl.isNotEmpty) {
      media = _buildImageSlide(imageUrl, s.storeName, scale);
    } else if ((_videoError ?? '').isNotEmpty) {
      media = _buildBrandFallback(s.storeName, hint: _videoError, scale: scale);
    } else {
      // Video đang tải.
      media = const Center(
        key: ValueKey('loading'),
        child: SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 3)),
      );
    }

    return ColoredBox(
      color: _mediaBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: KeyedSubtree(key: ValueKey('m:$_promoIndex:${media.key}'), child: media),
          ),
          if (hasVideo && _soundBlocked)
            Positioned(
              top: 12 * scale,
              right: 12 * scale,
              child: Material(
                color: const Color(0xCC000000),
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _unblockSound,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.volume_up_rounded, color: Colors.white, size: 20 * scale),
                        const SizedBox(width: 6),
                        Text(tr('Chạm để bật tiếng'),
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (caption.isNotEmpty || item.price != null || (idle && store.isNotEmpty))
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildCaption(
                title: caption.isNotEmpty ? caption : store,
                price: item.price,
                scale: scale,
              ),
            ),
        ],
      ),
    );
  }

  /// Ảnh hiện trọn (không cắt); khoảng trống quanh ảnh lấp bằng chính ảnh đó làm mờ — không còn viền đen
  /// khi ảnh vuông (ảnh hàng hóa) chiếu trên màn ngang.
  Widget _buildImageSlide(String url, String? storeName, double scale) {
    return Stack(
      key: ValueKey('i:$url'),
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        const ColoredBox(color: Color(0x66000000)),
        CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          fadeInDuration: const Duration(milliseconds: 250),
          errorWidget: (_, __, ___) => _buildBrandFallback(
            storeName,
            hint: 'Không tải được ảnh',
            scale: scale,
          ),
        ),
      ],
    );
  }

  Widget _buildCaption({required String title, double? price, required double scale}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xB3000000)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20 * scale, 28 * scale, 20 * scale, 14 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                tr(title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, height: 1.2),
              ),
            ),
            if (price != null && price > 0) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: SboxColors.danger, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '${_money.format(price)}đ',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBrandFallback(String? storeName, {String? hint, double scale = 1}) {
    final store = (storeName ?? '').trim();
    return Container(
      key: ValueKey('brand-fallback:${hint ?? ''}'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HrmPageChrome.primaryNavy,
            HrmPageChrome.primaryNavy.withValues(alpha: 0.85),
          ],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96 * scale,
                height: 96 * scale,
                padding: EdgeInsets.all(14 * scale),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.storefront_rounded,
                    color: Colors.white,
                    size: 48 * scale,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                tr(store.isNotEmpty ? store : 'Xin chào quý khách'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(store.isNotEmpty ? 'Xin chào quý khách' : 'SBOX HRM - SBOX POS'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if ((hint ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  tr(hint!),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBillPane(CustomerDisplayState s, double scale) {
    final active = s.isActive;
    final table = [
      if ((s.areaName ?? '').isNotEmpty) s.areaName,
      if ((s.tableLabel ?? '').isNotEmpty) s.tableLabel,
    ].whereType<String>().join(' · ');
    final confirmed = _paymentConfirmed(s);
    final hasQr = _hasQr(s);
    final pad = 14 + 10 * scale;

    return LayoutBuilder(builder: (context, c) {
      final tight = c.maxHeight < 560 * scale;
      return Container(
        color: _billBg,
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad * 0.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr((s.storeName ?? 'Hóa đơn').trim()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _billFg,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tr([
                active ? (table.isEmpty ? 'Đơn hiện tại' : table) : 'Thanh toán',
                if ((s.orderNo ?? '').isNotEmpty) s.orderNo,
                if (s.guestCount > 0) '${s.guestCount} khách',
              ].join(' · ')),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _billMuted, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Container(height: 1, color: _billLine),
            const SizedBox(height: 8),
            Expanded(
              child: s.lines.isEmpty
                  ? Center(
                      child: Text(
                        tr(active ? 'Chưa có món' : 'Xin chào quý khách'),
                        style: const TextStyle(color: _billMuted, fontSize: 18),
                      ),
                    )
                  : ListView.separated(
                      itemCount: s.lines.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _lineRow(s.lines[i]),
                    ),
            ),
            Container(height: 1, color: _billLine),
            const SizedBox(height: 10),
            _billRow('Tạm tính', '${_money.format(s.subtotal)}đ'),
            if (s.discount > 0) ...[
              const SizedBox(height: 4),
              _billRow(
                'Giảm giá',
                '-${_money.format(s.discount)}đ',
                valueColor: SboxColors.danger,
              ),
            ],
            const SizedBox(height: 6),
            _billRow(
              'TỔNG CỘNG',
              '${_money.format(s.total)}đ',
              emphasize: true,
            ),
            if (confirmed || hasQr) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: confirmed ? SboxColors.successSoft : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(confirmed ? Icons.check_circle : Icons.qr_code_2,
                        color: confirmed ? SboxColors.success : const Color(0xFF1D4ED8), size: 22 * scale),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(confirmed
                            ? (s.paymentConfirmedMessage ?? 'Đã nhận chuyển khoản').trim()
                            : 'Quét mã QR trên màn hình để thanh toán'),
                        style: TextStyle(
                          color: confirmed ? SboxColors.successText : const Color(0xFF1D4ED8),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!tight) ...[
              const SizedBox(height: 12),
              Text(
                tr('Cảm ơn quý khách'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: HrmPageChrome.primaryNavy.withValues(alpha: 0.85),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _lineRow(CustomerDisplayLine l) {
    final qty = l.qty % 1 == 0 ? l.qty.toStringAsFixed(0) : l.qty.toStringAsFixed(2);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(l.name),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
                style: const TextStyle(color: _billMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          tr('${_money.format(l.lineTotal)}đ'),
          style: const TextStyle(
            color: _billFg,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
        const SizedBox(width: 8),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              tr(value),
              style: TextStyle(
                color: valueColor ?? _billFg,
                fontSize: emphasize ? 28 : 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
