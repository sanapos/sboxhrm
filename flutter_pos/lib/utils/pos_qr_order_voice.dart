import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hrm.dart';
import '../services/signalr_service.dart';
import '../utils/navigation_notifier.dart';
import '../widgets/notification_overlay.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

class PosTtsVoiceOption {
  const PosTtsVoiceOption({
    required this.name,
    required this.locale,
    required this.label,
    this.score = 0,
  });

  final String name;
  final String locale;
  final String label;
  final int score;
}

/// Loa đọc thông báo POS trên Android 6 (A6 / Sunmi T1).
/// `flutter_tts` yêu cầu minSdk 24 → dùng TextToSpeech native qua kênh
/// `com.sboxhrm/tts` (PosTts.kt). Máy không có giọng tiếng Việt → phát tiếng bíp.
class PosQrOrderVoiceAlert {
  PosQrOrderVoiceAlert._();
  static final PosQrOrderVoiceAlert instance = PosQrOrderVoiceAlert._();

  static const _channel = MethodChannel('com.sboxhrm/tts');
  static const _voiceNameKey = 'pos_tts_voice_name';
  static const _rateKey = 'pos_tts_rate';

  StreamSubscription<Map<String, dynamic>>? _sub;
  String? _lastKey;
  DateTime? _lastAt;
  int _kdsForeground = 0;
  double _rate = 0.45;
  String? _voiceName;
  bool _prefsLoaded = false;
  List<PosTtsVoiceOption>? _cachedVoices;

  double get rate => _rate;
  String? get voiceName => _voiceName;

  void enterKds() => _kdsForeground++;
  void leaveKds() {
    if (_kdsForeground > 0) _kdsForeground--;
  }

  bool get _onKds => _kdsForeground > 0;

  Future<void> start() async {
    if (_sub != null) return;
    _sub = SignalRService().onPosFloorChanged.listen(_onFloor);
  }

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _voiceName = p.getString(_voiceNameKey);
      _rate = (p.getDouble(_rateKey) ?? 0.45).clamp(0.25, 0.75);
    } catch (_) {}
  }

  /// Thang flutter_tts (0.5 = bình thường) → TextToSpeech native (1.0 = bình thường).
  double get _nativeRate => _rate * 2;

  Future<List<PosTtsVoiceOption>> listVoices() async {
    if (_cachedVoices != null) return _cachedVoices!;
    if (kIsWeb) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('listVoices');
      final out = <PosTtsVoiceOption>[];
      for (final e in (raw ?? const []).whereType<Map>()) {
        out.add(PosTtsVoiceOption(
          name: (e['name'] ?? '').toString(),
          locale: (e['locale'] ?? '').toString(),
          label: (e['label'] ?? '').toString(),
          score: (e['score'] as num?)?.toInt() ?? 0,
        ));
      }
      out.sort((a, b) => b.score.compareTo(a.score));
      _cachedVoices = out;
      return out;
    } catch (e) {
      debugPrint('POS TTS listVoices: $e');
      return const [];
    }
  }

  Future<void> setVoice(PosTtsVoiceOption voice) async {
    _voiceName = voice.name;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_voiceNameKey, voice.name);
    } catch (_) {}
    await _applyOptions();
  }

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.25, 0.75);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_rateKey, _rate);
    } catch (_) {}
    await _applyOptions();
  }

  Future<void> _applyOptions() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('setOptions', {
        if (_voiceName != null) 'voice': _voiceName,
        'rate': _nativeRate,
      });
    } catch (_) {}
  }

  Future<void> preview() => speak(
        'Xin chào. Đây là giọng đọc. Đã thanh toán chuyển khoản thành công.',
      );

  Future<void> showSettingsSheet(BuildContext context) async {
    await _loadPrefs();
    final voices = await listVoices();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Giọng đọc'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 12),
                Text(tr('Tốc độ: ${(_rate * 100).round()}%')),
                Slider(
                  value: _rate,
                  min: 0.25,
                  max: 0.75,
                  divisions: 10,
                  onChanged: (v) => setLocal(() => _rate = v),
                  onChangeEnd: (v) => unawaited(setRate(v)),
                ),
                if (voices.isEmpty)
                  Text(tr(
                      'Máy chưa có giọng tiếng Việt — loa sẽ phát tiếng bíp. Cài Google Text-to-Speech + gói tiếng Việt để nghe đọc.'))
                else
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      itemCount: voices.length,
                      itemBuilder: (_, i) {
                        final v = voices[i];
                        final on = v.name == _voiceName;
                        return ListTile(
                          dense: true,
                          selected: on,
                          title: Text(v.label),
                          subtitle: Text(v.locale),
                          trailing: on ? const Icon(Icons.check) : null,
                          onTap: () async {
                            await setVoice(v);
                            if (ctx.mounted) setLocal(() {});
                          },
                        );
                      },
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => unawaited(preview()),
                  icon: const Icon(Icons.record_voice_over),
                  label: Text(tr('Nghe thử')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _isKdsOnlyGuestAlert(String reason) =>
      reason == 'qrcallpayment' ||
      reason == 'qrcallstaff' ||
      reason == 'qrpaidconfirm';

  void _onFloor(Map<String, dynamic> event) {
    final reason =
        (event['reason'] ?? event['Reason'] ?? '').toString().toLowerCase();
    if (_onKds && _isKdsOnlyGuestAlert(reason)) return;
    final table =
        (event['tableName'] ?? event['TableName'] ?? '').toString().trim();
    final extra =
        (event['message'] ?? event['Message'] ?? '').toString().trim();
    final orderId = (event['orderId'] ?? event['OrderId'] ?? '').toString();
    late final String title;
    late final String spoken;
    var playAlertSound = false;
    var paymentProblem = false;
    switch (reason) {
      case 'qrorder':
        final needsConfirm = extra.toLowerCase().contains('needsconfirm');
        playAlertSound = needsConfirm;
        title = needsConfirm ? 'QR cần xác nhận' : 'QR order tại bàn';
        spoken = needsConfirm
            ? (table.isEmpty
                ? 'Có đơn QR cần xác nhận trước khi in bếp'
                : 'Có đơn QR cần xác nhận $table trước khi in bếp')
            : (table.isEmpty
                ? 'Có khách đặt món tại bàn'
                : 'Có khách đặt món $table');
        break;
      case 'qronlineorder':
        playAlertSound = true;
        title = 'Đơn online — gọi lại khách';
        spoken = extra.isNotEmpty
            ? 'Có đơn đặt online. $extra. Gọi lại khách để xác nhận.'
            : 'Có đơn đặt hàng online. Gọi lại khách để xác nhận.';
        break;
      case 'qronlinestatus':
        title = 'Cập nhật đơn online';
        spoken = extra.isNotEmpty
            ? 'Đơn online. $extra'
            : 'Trạng thái đơn online đã cập nhật';
        break;
      case 'qrcallpayment':
        title = 'Gọi thanh toán';
        spoken =
            table.isEmpty ? 'Có khách gọi thanh toán' : '$table gọi thanh toán';
        break;
      case 'qrcallstaff':
        title = 'Gọi phục vụ';
        spoken = table.isEmpty ? 'Có khách gọi phục vụ' : '$table gọi phục vụ';
        break;
      case 'qrpaidconfirm':
        title = 'Khách xác nhận QR';
        spoken = extra.isNotEmpty
            ? extra
            : (table.isEmpty
                ? 'Khách xác nhận đã thanh toán QR. Thu ngân kiểm tra giao dịch.'
                : '$table xác nhận đã thanh toán QR. Thu ngân kiểm tra giao dịch.');
        break;
      case 'tingeepaymentconfirmed':
        playAlertSound = true;
        // Server báo CK thiếu / chưa hoàn tất được đơn → cảnh báo, không báo «Đã thanh toán».
        final lower = extra.toLowerCase();
        paymentProblem = lower.startsWith('chuyển khoản thiếu') ||
            lower.contains('chưa hoàn tất được đơn');
        title = paymentProblem ? 'Cần kiểm tra chuyển khoản' : 'Đã thanh toán';
        spoken = extra.isNotEmpty
            ? extra
            : (table.isEmpty
                ? 'Đã thanh toán chuyển khoản thành công'
                : 'Đã thanh toán chuyển khoản $table');
        break;
      default:
        return;
    }
    final key = '$reason|$orderId|$table';
    final now = DateTime.now();
    if (_lastKey == key &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 8)) {
      return;
    }
    _lastKey = key;
    _lastAt = now;
    unawaited(speak(spoken));
    final isOnlineOrder = reason == 'qronlineorder' ||
        reason == 'qronlinestatus' ||
        table.toLowerCase() == 'online';
    NotificationOverlayManager().show(
      title: title,
      message: spoken,
      type: paymentProblem
          ? NotificationType.warning
          : (reason == 'tingeepaymentconfirmed'
              ? NotificationType.success
              : NotificationType.info),
      duration: const Duration(seconds: 5),
      playSound: playAlertSound,
      onTap: isOnlineOrder || reason == 'tingeepaymentconfirmed'
          ? () {
              if (isOnlineOrder) {
                NavigationNotifier.pendingOpenQrOnlineOrders.value = true;
              }
              NavigationNotifier.posHubTab.value = 2;
              NavigationNotifier.goToModule('PosSell');
            }
          : null,
    );
  }

  Future<void> speak(String text) => speakSequence([text]);

  Future<void> stopSpeaking() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  /// Native speak dùng QUEUE_FLUSH → ghép các phần thành một câu để không cắt nhau.
  Future<void> speakSequence(List<String> parts) async {
    final text = parts
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .join('. ');
    if (text.isEmpty || kIsWeb) return;
    await _loadPrefs();
    try {
      await _channel.invokeMethod('speak', {
        'text': text,
        if (_voiceName != null) 'voice': _voiceName,
        'rate': _nativeRate,
      });
    } catch (e) {
      debugPrint('POS TTS speak: $e');
    }
  }

  Future<void> warmUp() async {
    await _loadPrefs();
    await _applyOptions();
  }
}
