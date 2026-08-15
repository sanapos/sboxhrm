import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hrm.dart';
import '../services/signalr_service.dart';
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

  StreamSubscription<Map<String, dynamic>>? _sub;
  FlutterTts? _tts;
  String? _lastKey;
  DateTime? _lastAt;
  int _kdsForeground = 0;
  String? _voiceName;
  String? _voiceLocale;
  double _rate = 0.40;
  bool _prefsLoaded = false;

  double get rate => _rate;
  String? get voiceName => _voiceName;

  void enterKds() => _kdsForeground++;
  void leaveKds() {
    if (_kdsForeground > 0) _kdsForeground--;
  }

  bool get _onKds => _kdsForeground > 0;

  Future<void> start() async {
    if (_sub != null) return;
    await _ensureTts();
    _sub = SignalRService().onPosFloorChanged.listen(_onFloor);
  }

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _voiceName = p.getString(_voiceNameKey);
      _voiceLocale = p.getString(_voiceLocaleKey);
      _rate = (p.getDouble(_rateKey) ?? 0.40).clamp(0.25, 0.75);
    } catch (_) {}
  }

  Future<void> _ensureTts() async {
    await _loadPrefs();
    if (_tts != null) {
      await _applyVoiceAndRate(_tts!);
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
      await tts.setPitch(1.05);
      if (!kIsWeb) {
        await tts.awaitSpeakCompletion(false);
      }
      await _applyVoiceAndRate(tts);
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
      if (_voiceName != null &&
          _voiceName!.isNotEmpty &&
          _voiceLocale != null &&
          _voiceLocale!.isNotEmpty) {
        await tts.setVoice({'name': _voiceName!, 'locale': _voiceLocale!});
        return;
      }
      if (!kIsWeb) await _preferNaturalVi(tts);
    } catch (_) {}
  }

  static int scoreVoice(String name, String locale) {
    final n = name.toLowerCase();
    final loc = locale.toLowerCase();
    if (!loc.startsWith('vi')) return -100;
    var s = 10;
    if (n.contains('wavenet') || n.contains('neural') || n.contains('natural')) {
      s += 12;
    }
    if (n.contains('vif') || n.contains('female')) s += 8;
    if (n.contains('network')) s += 3;
    if (n.contains('local')) s += 2;
    if (n.contains('vid') || n.contains('male')) s -= 3;
    return s;
  }

  static String labelVoice(String name, String locale) {
    final n = name.toLowerCase();
    final tags = <String>[];
    if (n.contains('wavenet') || n.contains('neural') || n.contains('natural')) {
      tags.add('Mượt');
    } else if (n.contains('network')) {
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

  Future<void> _preferNaturalVi(FlutterTts tts) async {
    final list = await listVoices();
    if (list.isEmpty) return;
    final pick = list.first;
    await tts.setVoice({'name': pick.name, 'locale': pick.locale});
  }

  Future<List<PosTtsVoiceOption>> listVoices() async {
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
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> setVoice(PosTtsVoiceOption voice) async {
    _voiceName = voice.name;
    _voiceLocale = voice.locale;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_voiceNameKey, voice.name);
      await p.setString(_voiceLocaleKey, voice.locale);
    } catch (_) {}
    await _ensureTts();
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
        'Xin chào. Đây là giọng đọc. Khu vực sảnh, bàn 5, tổng số 2 món. '
        'Món 1: phở bò, số lượng 1. Món 2: cơm gà, số lượng 2.',
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
                    'Chọn giọng mượt (Nữ / Mạng) và chỉnh tốc độ.',
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
                  if (voices.isEmpty)
                    const Text(
                      'Máy chưa có giọng tiếng Việt. Cài Google Text-to-Speech.',
                      style: TextStyle(color: Colors.white54),
                    )
                  else
                    SizedBox(
                      height: 280,
                      child: ListView.builder(
                        itemCount: voices.length,
                        itemBuilder: (_, i) {
                          final v = voices[i];
                          final on = v.name == _voiceName;
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
    switch (reason) {
      case 'qrorder':
        title = 'QR order tại bàn';
        spoken = table.isEmpty
            ? 'Có khách đặt món tại bàn'
            : 'Có khách đặt món $table';
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
    unawaited(_speak(spoken));
    NotificationOverlayManager().show(
      title: title,
      message: spoken,
      type: NotificationType.info,
      duration: const Duration(seconds: 5),
      playSound: false,
    );
  }

  Future<void> speak(String text) => _speak(text);

  Future<void> _speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      await _ensureTts();
      await _tts?.stop();
      await _tts?.speak(t);
    } catch (e) {
      debugPrint('POS TTS speak: $e');
    }
  }
}
