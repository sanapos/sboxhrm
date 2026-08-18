import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Loa POS T1: MethodChannel TTS. Không phát gọi phục vụ / thanh toán trên KDS.
class PosQrOrderVoiceAlert {
  PosQrOrderVoiceAlert._();
  static final PosQrOrderVoiceAlert instance = PosQrOrderVoiceAlert._();

  static const _ch = MethodChannel('com.sboxhrm/tts');
  static const _voiceNameKey = 'pos_tts_voice_name';
  static const _rateKey = 'pos_tts_rate';

  StreamSubscription<Map<String, dynamic>>? _sub;
  String? _lastKey;
  DateTime? _lastAt;
  int _kdsForeground = 0;
  String? _voiceName;
  double _rate = 0.40;
  bool _prefsLoaded = false;
  int _speakSeq = 0;

  double get rate => _rate;
  String? get voiceName => _voiceName;

  void enterKds() => _kdsForeground++;
  void leaveKds() {
    if (_kdsForeground > 0) _kdsForeground--;
  }

  bool get _onKds => _kdsForeground > 0;

  Future<void> start() async {
    if (_sub != null) return;
    await _loadPrefs();
    _sub = SignalRService().onPosFloorChanged.listen(_onFloor);
  }

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _voiceName = p.getString(_voiceNameKey);
      _rate = (p.getDouble(_rateKey) ?? 0.40).clamp(0.25, 0.75);
    } catch (_) {}
  }

  Future<List<PosTtsVoiceOption>> listVoices() async {
    await _loadPrefs();
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('listVoices');
      if (raw == null) return const [];
      final out = <PosTtsVoiceOption>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final name = (e['name'] ?? '').toString();
        final locale = (e['locale'] ?? '').toString();
        if (name.isEmpty) continue;
        out.add(PosTtsVoiceOption(
          name: name,
          locale: locale,
          label: (e['label'] ?? name).toString(),
          score: (e['score'] as num?)?.toInt() ?? 0,
        ));
      }
      out.sort((a, b) => b.score.compareTo(a.score));
      return out;
    } catch (e) {
      debugPrint('TTS listVoices: $e');
      return const [];
    }
  }

  Future<void> setVoice(PosTtsVoiceOption voice) async {
    _voiceName = voice.name;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_voiceNameKey, voice.name);
    } catch (_) {}
    try {
      await _ch.invokeMethod('setOptions', {
        'voice': voice.name,
        'rate': _androidRate,
      });
    } catch (_) {}
  }

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.25, 0.75);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_rateKey, _rate);
    } catch (_) {}
    try {
      await _ch.invokeMethod('setOptions', {
        'voice': _voiceName,
        'rate': _androidRate,
      });
    } catch (_) {}
  }

  double get _androidRate => (0.45 + _rate).clamp(0.50, 1.20);

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
    unawaited(speak(spoken));
    NotificationOverlayManager().show(
      title: title,
      message: spoken,
      type: NotificationType.info,
      duration: const Duration(seconds: 5),
      playSound: playAlertSound,
    );
  }

  Future<void> speak(String text) => speakSequence([text]);

  Future<void> speakSequence(List<String> parts) async {
    final cleaned =
        parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (cleaned.isEmpty) return;
    _speakSeq++;
    final seq = _speakSeq;
    for (final raw in cleaned) {
      if (seq != _speakSeq) return;
      await _speakOne(raw);
      if (seq != _speakSeq) return;
      final wait = (500 + raw.length * 70).clamp(600, 10000);
      await Future<void>.delayed(Duration(milliseconds: wait));
    }
  }

  Future<void> stopSpeaking() async {
    _speakSeq++;
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  Future<void> warmUp() async {
    await _loadPrefs();
  }

  Future<void> _speakOne(String text) async {
    var t = text.trim();
    if (t.isEmpty) return;
    await _loadPrefs();
    try {
      await _ch.invokeMethod('speak', {
        'text': t,
        'voice': _voiceName,
        'rate': _androidRate,
      });
    } catch (e) {
      debugPrint('POS TTS speak: $e');
    }
  }
}
