import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hrm.dart';
import '../services/signalr_service.dart';
import '../utils/navigation_notifier.dart';
import '../widgets/notification_overlay.dart';

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

/// Loa POS: đọc món KDS + thông báo QR (không phát QR trên màn KDS).
class PosQrOrderVoiceAlert {
  PosQrOrderVoiceAlert._();
  static final PosQrOrderVoiceAlert instance = PosQrOrderVoiceAlert._();

  static const _voiceNameKey = 'pos_tts_voice_name';
  static const _voiceLocaleKey = 'pos_tts_voice_locale';
  static const _rateKey = 'pos_tts_rate';
  /// Một lần: xóa giọng prefs cũ (thường network/server) khiến A7 không đọc được.
  static const _voiceMigratedKey = 'pos_tts_voice_migrated_v3';

  StreamSubscription<Map<String, dynamic>>? _sub;
  FlutterTts? _tts;
  String? _lastKey;
  DateTime? _lastAt;
  int _kdsForeground = 0;
  String? _voiceName;
  String? _voiceLocale;
  double _rate = 0.45;
  bool _prefsLoaded = false;
  bool _voiceApplied = false;
  /// true = chỉ setLanguage(vi-VN), không setVoice (ổn định nhất trên C20Lite).
  bool _languageOnly = false;
  List<PosTtsVoiceOption>? _cachedVoices;
  int _speakGen = 0;
  bool _speaking = false;
  final List<String> _speakQueue = [];
  bool _drainingSpeak = false;
  Completer<void>? _utteranceDone;

  double get rate => _rate;
  String? get voiceName => _voiceName;

  void enterKds() => _kdsForeground++;
  void leaveKds() {
    if (_kdsForeground > 0) _kdsForeground--;
  }

  bool get _onKds => _kdsForeground > 0;

  Future<void> start() async {
    if (_sub != null) return;
    // Không init TTS lúc login — V2s/A7 3GB + engine Google TTS dễ OOM / crash.
    _sub = SignalRService().onPosFloorChanged.listen(_onFloor);
  }

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      if (!(p.getBool(_voiceMigratedKey) ?? false)) {
        await p.remove(_voiceNameKey);
        await p.remove(_voiceLocaleKey);
        await p.setBool(_voiceMigratedKey, true);
      }
      _voiceName = p.getString(_voiceNameKey);
      _voiceLocale = p.getString(_voiceLocaleKey);
      _rate = (p.getDouble(_rateKey) ?? 0.45).clamp(0.25, 0.75);
      if (_isUnreliableVoice(_voiceName)) {
        _voiceName = null;
        _voiceLocale = null;
        await p.remove(_voiceNameKey);
        await p.remove(_voiceLocaleKey);
      }
    } catch (_) {}
  }

  static bool _isUnreliableVoice(String? name) {
    if (name == null || name.isEmpty) return false;
    final n = name.toLowerCase();
    return n.contains('network') ||
        n.contains('server') ||
        n.contains('wavenet') ||
        n.contains('neural') ||
        n.contains('-x-gft-');
  }

  Future<void> _ensureTts() async {
    await _loadPrefs();
    if (_tts != null) {
      if (!_voiceApplied) {
        await _applyVoiceAndRate(_tts!);
        _voiceApplied = true;
      }
      return;
    }
    final tts = FlutterTts();
    try {
      if (!kIsWeb) {
        try {
          final engines = await tts.getEngines;
          final names = engines is List
              ? engines.map((e) => e.toString()).toList()
              : const <String>[];
          if (names.any((e) => e.contains('com.google.android.tts'))) {
            await tts.setEngine('com.google.android.tts');
          }
        } catch (_) {}
      }
      await tts.setLanguage('vi-VN');
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
      if (!kIsWeb) {
        await tts.awaitSpeakCompletion(false);
      }
      await _applyVoiceAndRate(tts);
      _voiceApplied = true;
    } catch (e) {
      debugPrint('QR order TTS init: $e');
    }
    _tts = tts;
  }

  Future<void> _applyVoiceAndRate(FlutterTts tts) async {
    try {
      await tts.setSpeechRate(_rate);
    } catch (_) {}
    try {
      await tts.setLanguage('vi-VN');
    } catch (_) {}

    // A7: setVoice với giọng không cấp cho app → im tiếng.
    // Mặc định chỉ dùng locale; chỉ setVoice khi user chọn giọng local ổn.
    if (_languageOnly ||
        _voiceName == null ||
        _voiceName!.isEmpty ||
        _voiceLocale == null ||
        _voiceLocale!.isEmpty ||
        _isUnreliableVoice(_voiceName)) {
      _languageOnly = true;
      return;
    }

    try {
      final ok = await tts.setVoice({
        'name': _voiceName!,
        'locale': _voiceLocale!,
      });
      // flutter_tts: 1 = success trên Android.
      if (ok == 0 || ok == false) {
        debugPrint('POS TTS setVoice failed → language-only');
        await _fallbackLanguageOnly(tts);
      } else {
        _languageOnly = false;
      }
    } catch (e) {
      debugPrint('POS TTS setVoice error: $e');
      await _fallbackLanguageOnly(tts);
    }
  }

  Future<void> _fallbackLanguageOnly(FlutterTts tts) async {
    _languageOnly = true;
    _voiceName = null;
    _voiceLocale = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_voiceNameKey);
      await p.remove(_voiceLocaleKey);
    } catch (_) {}
    try {
      await tts.setLanguage('vi-VN');
    } catch (_) {}
  }

  static int scoreVoice(String name, String locale) {
    final n = name.toLowerCase();
    final loc = locale.toLowerCase();
    if (!loc.startsWith('vi')) return -100;
    var s = 10;
    // Local ổn định trên A7; network/server dễ «voice not available» / ANR.
    if (n.contains('local') && !n.contains('server')) s += 25;
    if (n.contains('vif') || n.contains('female')) s += 8;
    if (n.contains('wavenet') || n.contains('neural') || n.contains('natural')) {
      s -= 20;
    }
    if (n.contains('network') || n.contains('server') || n.contains('-x-gft-')) {
      s -= 50;
    }
    if (n.contains('vid') || n.contains('male')) s -= 3;
    return s;
  }

  static String labelVoice(String name, String locale) {
    final n = name.toLowerCase();
    final tags = <String>[];
    if (n.contains('wavenet') || n.contains('neural') || n.contains('natural')) {
      tags.add('Mượt');
    } else if (n.contains('network') || n.contains('server')) {
      tags.add('Mạng');
    } else {
      tags.add('Máy');
    }
    if (n.contains('female') || n.contains('vif')) {
      tags.add('Nữ');
    } else if (n.contains('male') || n.contains('vid')) {
      tags.add('Nam');
    }
    var short = name
        .replaceAll(RegExp(r'com\.google\.android\.tts[.:]?', caseSensitive: false), '')
        .replaceAll(RegExp(r'vi[-_]?vn[-_.]?', caseSensitive: false), '');
    if (short.length > 22) short = short.substring(0, 22);
    if (short.isEmpty) short = locale;
    return '${tags.join(' · ')} · $short';
  }

  Future<List<PosTtsVoiceOption>> listVoices() async {
    if (_cachedVoices != null) return _cachedVoices!;
    await _ensureTts();
    try {
      final raw = await _tts?.getVoices;
      if (raw is! List) return const [];
      final out = <PosTtsVoiceOption>[];
      for (final e in raw.whereType<Map>()) {
        final name = (e['name'] ?? '').toString();
        final locale = (e['locale'] ?? '').toString();
        final s = scoreVoice(name, locale);
        if (s < 0) continue;
        out.add(PosTtsVoiceOption(
          name: name,
          locale: locale,
          label: labelVoice(name, locale),
          score: s,
        ));
      }
      out.sort((a, b) => b.score.compareTo(a.score));
      _cachedVoices = out;
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> setVoice(PosTtsVoiceOption voice) async {
    if (_isUnreliableVoice(voice.name)) {
      // User chọn giọng mạng → vẫn cho thử, nhưng đánh dấu không language-only.
      _languageOnly = false;
    } else {
      _languageOnly = false;
    }
    _voiceName = voice.name;
    _voiceLocale = voice.locale;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_voiceNameKey, voice.name);
      await p.setString(_voiceLocaleKey, voice.locale);
    } catch (_) {}
    await _ensureTts();
    try {
      final ok = await _tts?.setVoice({'name': voice.name, 'locale': voice.locale});
      if (ok == 0 || ok == false) {
        await _fallbackLanguageOnly(_tts!);
      } else {
        _voiceApplied = true;
        _languageOnly = false;
      }
    } catch (_) {
      if (_tts != null) await _fallbackLanguageOnly(_tts!);
    }
  }

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.25, 0.75);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_rateKey, _rate);
    } catch (_) {}
    try {
      await _tts?.setSpeechRate(_rate);
    } catch (_) {}
  }

  Future<void> preview() => speak(
        'Xin chào. Đây là giọng đọc. Bàn 5, hai món. Phở bò số lượng 1. Cơm gà số lượng 2.',
      );

  Future<void> showSettingsSheet(BuildContext context) async {
    final voices = await listVoices();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101827),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Giọng đọc',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'A7: nên chọn giọng «Máy» (local). Giọng Mạng dễ mất tiếng.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tốc độ: ${(_rate * 100).round()}%',
                    style: const TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w700),
                  ),
                  Slider(
                    value: _rate,
                    min: 0.25,
                    max: 0.75,
                    divisions: 10,
                    activeColor: const Color(0xFFFF8A3D),
                    onChanged: (v) {
                      setLocal(() => _rate = v);
                    },
                    onChangeEnd: (v) => unawaited(setRate(v)),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (_tts != null) await _fallbackLanguageOnly(_tts!);
                      _voiceApplied = true;
                      if (ctx.mounted) setLocal(() {});
                      unawaited(preview());
                    },
                    child: const Text(
                      'Dùng giọng mặc định (ổn định)',
                      style: TextStyle(color: Color(0xFFFF8A3D)),
                    ),
                  ),
                  if (voices.isEmpty)
                    const Text(
                      'Máy chưa có giọng tiếng Việt. Cài Google Text-to-Speech + gói tiếng Việt offline.',
                      style: TextStyle(color: Colors.white54),
                    )
                  else
                    SizedBox(
                      height: 240,
                      child: ListView.builder(
                        itemCount: voices.length,
                        itemBuilder: (_, i) {
                          final v = voices[i];
                          final on = !_languageOnly && v.name == _voiceName;
                          return ListTile(
                            dense: true,
                            selected: on,
                            selectedTileColor: const Color(0x33FF8A3D),
                            title: Text(
                              v.label,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              v.locale,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                            trailing: on
                                ? const Icon(Icons.check,
                                    color: Color(0xFFFF8A3D))
                                : null,
                            onTap: () async {
                              await setVoice(v);
                              if (ctx.mounted) setLocal(() {});
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => unawaited(preview()),
                    icon: const Icon(Icons.record_voice_over,
                        color: Color(0xFFFF8A3D)),
                    label: const Text(
                      'Nghe thử',
                      style: TextStyle(color: Color(0xFFFF8A3D)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
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
    final orderId =
        (event['orderId'] ?? event['OrderId'] ?? '').toString();
    late final String title;
    late final String spoken;
    var playAlertSound = false;
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
        title = 'Đã nhận chuyển khoản';
        spoken = extra.isNotEmpty
            ? extra
            : (table.isEmpty
                ? 'Đã nhận chuyển khoản thành công'
                : 'Đã nhận chuyển khoản $table');
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
    final isOnlineOrder = reason == 'qronlineorder';
    NotificationOverlayManager().show(
      title: title,
      message: spoken,
      type: NotificationType.info,
      duration: const Duration(seconds: 5),
      playSound: playAlertSound,
      onTap: isOnlineOrder
          ? () {
              NavigationNotifier.pendingOpenQrOnlineOrders.value = true;
              NavigationNotifier.posHubTab.value = 2;
              NavigationNotifier.goToModule('PosSell');
            }
          : null,
    );
  }

  Future<void> speak(String text) => speakSequence([text]);

  Future<void> stopSpeaking() async {
    _speakGen++;
    _speakQueue.clear();
    _speaking = false;
    try {
      if (_utteranceDone != null && !_utteranceDone!.isCompleted) {
        _utteranceDone!.complete();
      }
    } catch (_) {}
    _utteranceDone = null;
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  Future<void> speakSequence(List<String> parts) async {
    final cleaned =
        parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (cleaned.isEmpty) return;
    _speakGen++;
    _speakQueue
      ..clear()
      ..addAll(cleaned);
    if (!_drainingSpeak) unawaited(_drainSpeakQueue());
  }

  Future<void> _drainSpeakQueue() async {
    _drainingSpeak = true;
    try {
      while (_speakQueue.isNotEmpty) {
        final gen = _speakGen;
        final t = _speakQueue.removeAt(0);
        await _speakOne(t, gen);
        if (gen != _speakGen) break;
      }
    } finally {
      _drainingSpeak = false;
      if (_speakQueue.isNotEmpty) unawaited(_drainSpeakQueue());
    }
  }

  Future<void> _speakOne(String text, int gen) async {
    var t = text.trim();
    if (t.isEmpty || gen != _speakGen) return;
    try {
      await _ensureTts();
      if (gen != _speakGen) return;
      final tts = _tts;
      if (tts == null) return;

      try {
        await tts.setLanguage('vi-VN');
        await tts.setSpeechRate(_rate);
        await tts.setVolume(1.0);
      } catch (_) {}

      final done = Completer<void>();
      _utteranceDone = done;
      void finish() {
        if (!done.isCompleted) done.complete();
      }

      tts.setCompletionHandler(finish);
      tts.setCancelHandler(finish);
      tts.setErrorHandler((_) => finish());

      _speaking = true;
      final result = await tts.speak(t);
      if (gen != _speakGen) return;

      if (result == 0 || result == false) {
        debugPrint('POS TTS speak failed ($result) → retry language-only');
        await _fallbackLanguageOnly(tts);
        if (gen != _speakGen) return;
        await tts.setLanguage('vi-VN');
        await tts.speak(t);
      }

      final waitMs = (700 + t.length * 90).clamp(900, 14000);
      await done.future.timeout(
        Duration(milliseconds: waitMs),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('POS TTS speak: $e');
      try {
        final tts = _tts;
        if (tts == null || gen != _speakGen) return;
        await _fallbackLanguageOnly(tts);
        await tts.setLanguage('vi-VN');
        await tts.speak(t);
        await Future<void>.delayed(
          Duration(milliseconds: (700 + t.length * 90).clamp(900, 8000)),
        );
      } catch (e2) {
        debugPrint('POS TTS retry: $e2');
      }
    } finally {
      if (gen == _speakGen) _speaking = false;
    }
  }

  Future<void> warmUp() async {
    try {
      await _ensureTts();
      try {
        await _tts?.setLanguage('vi-VN');
      } catch (_) {}
    } catch (_) {}
  }
}
