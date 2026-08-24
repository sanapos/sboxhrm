import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/signalr_service.dart';

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

/// Stub TTS cho POS Android 6 (minSdk 23): `flutter_tts` yêu cầu minSdk 24.
/// Giữ API để KDS / bán hàng không vỡ compile; loa đọc no-op trên A6.
class PosQrOrderVoiceAlert {
  PosQrOrderVoiceAlert._();
  static final PosQrOrderVoiceAlert instance = PosQrOrderVoiceAlert._();

  StreamSubscription<Map<String, dynamic>>? _sub;
  int _kdsForeground = 0;
  double _rate = 0.45;
  String? _voiceName;

  double get rate => _rate;
  String? get voiceName => _voiceName;

  void enterKds() => _kdsForeground++;
  void leaveKds() {
    if (_kdsForeground > 0) _kdsForeground--;
  }

  Future<void> start() async {
    if (_sub != null) return;
    _sub = SignalRService().onPosFloorChanged.listen(_onFloor);
  }

  Future<List<PosTtsVoiceOption>> listVoices() async => const [];

  Future<void> setVoice(PosTtsVoiceOption voice) async {
    _voiceName = voice.name;
  }

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.25, 0.75);
  }

  Future<void> preview() => speak('Xin chào');

  Future<void> showSettingsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Text(
            'Loa TTS chưa hỗ trợ trên Android 6 (máy POS A6).\n'
            'Dùng app HRM trên A7 để nghe đọc đơn.',
            style: TextStyle(fontSize: 15, height: 1.4),
          ),
        ),
      ),
    );
  }

  void _onFloor(Map<String, dynamic> event) {
    if (kDebugMode) {
      debugPrint('POS voice stub floor event keys=${event.keys}');
    }
  }

  Future<void> speak(String text) => speakSequence([text]);

  Future<void> stopSpeaking() async {}

  Future<void> speakSequence(List<String> parts) async {
    if (kDebugMode && parts.isNotEmpty) {
      debugPrint('POS TTS stub: ${parts.join(' | ')}');
    }
  }

  Future<void> warmUp() async {}
}
