import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Tiếng «tít» rõ khi quét được mã vạch (dùng audioplayers với WAV tạo sẵn trong
/// bộ nhớ — không cần file asset). Lỗi âm thanh thì rung nhẹ thay thế.
class PosScanBeep {
  PosScanBeep._();

  static final AudioPlayer _player = AudioPlayer();
  static Uint8List? _wav;

  static Future<void> play() async {
    try {
      _wav ??= _buildBeepWav();
      await _player.stop();
      await _player.play(BytesSource(_wav!, mimeType: 'audio/wav'), volume: 1.0);
    } catch (_) {
      try {
        await HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }

  /// WAV PCM 16-bit mono: một tiếng bíp ~2700Hz, ~95ms, có vuốt đầu/cuối cho đỡ «tạch».
  static Uint8List _buildBeepWav() {
    const sampleRate = 16000;
    const freq = 2700.0;
    const ms = 95;
    const n = sampleRate * ms ~/ 1000;
    const fade = sampleRate * 4 ~/ 1000; // vuốt 4ms
    const dataSize = n * 2;
    final b = BytesBuilder();
    void u32(int v) =>
        b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
    b.add('RIFF'.codeUnits);
    u32(36 + dataSize);
    b.add('WAVE'.codeUnits);
    b.add('fmt '.codeUnits);
    u32(16); // PCM fmt chunk size
    u16(1); // PCM
    u16(1); // mono
    u32(sampleRate);
    u32(sampleRate * 2); // byte rate
    u16(2); // block align
    u16(16); // bits/sample
    b.add('data'.codeUnits);
    u32(dataSize);
    for (var i = 0; i < n; i++) {
      var amp = 0.75;
      if (i < fade) amp *= i / fade;
      if (i > n - fade) amp *= (n - i) / fade;
      final s = (sin(2 * pi * freq * i / sampleRate) * amp * 32767)
          .round()
          .clamp(-32768, 32767);
      u16(s & 0xFFFF);
    }
    return b.toBytes();
  }
}
