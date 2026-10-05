import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../utils/vi_speech_text.dart';
import '../utils/permission_navigation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../utils/store_role_helper.dart';
import '../screens/landing_guide_screen.dart';
import '../screens/settings_hub_screen.dart';
import '../services/api_service.dart';
import '../utils/ai_assistant_permissions.dart';
import '../utils/landing_guide_url.dart';
import '../utils/landing_usage_guide.dart';
import '../utils/navigation_notifier.dart';
import '../utils/settings_hub_catalog.dart';
import 'notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import './pos/pos_theme.dart';
import '../theme/sbox_tokens.dart';
class _ChatMsg {
  final String role; // 'user' | 'assistant'
  final String content;
  final List<String> actions;
  final List<String> creates;
  final List<String> guides;
  /// Báo cáo trợ lý đã xem để trả lời (tên hiển thị).
  final List<String> reports;
  /// Phiếu trợ lý đã dựng sẵn — chờ người dùng bấm Xác nhận.
  final List<_PendingAction> pending;

  _ChatMsg(this.role, this.content,
      {this.actions = const [],
      this.creates = const [],
      this.guides = const [],
      this.reports = const [],
      this.pending = const []});
}

class _PendingAction {
  _PendingAction.fromJson(Map<String, dynamic> j)
      : id = (j['id'] ?? '').toString(),
        kind = (j['kind'] ?? '').toString(),
        title = (j['title'] ?? 'Phiếu').toString(),
        lines = ((j['lines'] as List?) ?? [])
            .whereType<Map>()
            .map((l) => ((l['label'] ?? '').toString(), (l['value'] ?? '').toString()))
            .toList(),
        warnings = ((j['warnings'] as List?) ?? []).map((e) => e.toString()).toList(),
        openModule = j['openModule']?.toString();

  final String id;
  final String kind;
  final String title;
  final List<(String, String)> lines;
  final List<String> warnings;
  final String? openModule;

  /// pending | running | done | failed | discarded
  String state = 'pending';
  String? result;
}

class AiAssistantSheet extends StatefulWidget {
  const AiAssistantSheet({super.key});

  @override
  State<AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends State<AiAssistantSheet> {
  final _api = ApiService();
  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  final _stt = stt.SpeechToText();
  final _tts = FlutterTts();

  final List<_ChatMsg> _messages = [];
  bool _isSending = false;
  bool _sttReady = false;
  bool _isListening = false;
  bool _ttsEnabled = true;
  bool _ttsSpeaking = false;
  int _speakGen = 0;
  String _partialTranscript = '';

  // Giọng nói bằng AI (Gemini): ghi âm → chép lời có từ vựng cửa hàng; đọc bằng giọng người thật.
  static const _kAiVoiceKey = 'ai_assistant_ai_voice_v1';
  static const _kVoiceNameKey = 'ai_assistant_voice_name_v1';
  static const _voices = [
    ('Aoede', 'Nữ — nhẹ nhàng, tự nhiên'),
    ('Kore', 'Nữ — rõ ràng, chắc'),
    ('Leda', 'Nữ — trẻ trung'),
    ('Sulafat', 'Nữ — ấm áp'),
    ('Charon', 'Nam — trầm, điềm đạm'),
    ('Puck', 'Nam — vui vẻ'),
    ('Orus', 'Nam — chắc chắn'),
    ('Iapetus', 'Nam — rõ ràng'),
  ];
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  StreamSubscription<Uint8List>? _recSub;
  final _recBuf = BytesBuilder(copy: false);
  Timer? _recTimer;
  int _recSecs = 0;
  bool _recording = false;
  bool _transcribing = false;
  bool _aiVoice = true;
  String _voiceName = 'Aoede';

  static const _kAiConsentKey = 'ai_assistant_consent_v1';
  bool _consentChecked = false;
  bool _consentGiven = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initStt();
    _loadVoicePrefs();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _ttsSpeaking = false);
    });
    _messages.add(_ChatMsg('assistant',
        'Xin chào! Tôi là Trợ lý ảo của cửa hàng. Tôi đọc báo cáo bán hàng và nhân sự (theo quyền của bạn) để trả lời và phân tích: doanh thu, lợi nhuận, hàng bán chạy, tồn kho, công nợ, chấm công, đi trễ, nghỉ phép, lương… Tôi cũng lập / sửa phiếu theo lời bạn (phiếu thu chi, phạt, thưởng, ứng lương, tăng ca, bổ sung chấm công, hóa đơn bán) — bạn chỉ cần kiểm tra rồi bấm Xác nhận. Bấm micro, gõ câu hỏi hoặc chọn gợi ý bên dưới.'));
    if (!kIsWeb) {
      _checkAiConsent();
    } else {
      _consentChecked = true;
      _consentGiven = true;
    }
  }

  Future<void> _checkAiConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final given = prefs.getBool(_kAiConsentKey) ?? false;
    if (mounted) {
      setState(() {
        _consentGiven = given;
        _consentChecked = true;
      });
      if (!given) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showConsentDialog());
      }
    }
  }

  Future<void> _showConsentDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Trợ lý ảo – Thông tin quyền riêng tư')),
        content: Text(
          tr('Khi sử dụng trợ lý AI, nội dung câu hỏi và dữ liệu nhân sự liên quan (ca làm việc, phép, chấm công) '
          'sẽ được gửi đến máy chủ của chúng tôi và xử lý bằng Google Gemini AI để tạo phản hồi.\n\n'
          'Dữ liệu sinh trắc học (khuôn mặt, vân tay) không được gửi đến AI.\n\n'
          'Bạn đồng ý để tiếp tục sử dụng tính năng này không?'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) Navigator.of(context).pop(); // close sheet
            },
            child: Text(tr('Không đồng ý')),
          ),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(_kAiConsentKey, true);
              if (mounted) setState(() => _consentGiven = true);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(tr('Đồng ý')),
          ),
        ],
      ),
    );
  }

  Future<void> _loadVoicePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _aiVoice = prefs.getBool(_kAiVoiceKey) ?? true;
        _voiceName = prefs.getString(_kVoiceNameKey) ?? 'Aoede';
      });
    } catch (_) {}
  }

  Future<void> _saveVoicePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAiVoiceKey, _aiVoice);
      await prefs.setString(_kVoiceNameKey, _voiceName);
    } catch (_) {}
  }

  /// Ghi âm PCM 16 kHz (chạy cả web lẫn điện thoại) → WAV gửi Gemini chép lời.
  Future<bool> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) return false;
      _recBuf.clear();
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ));
      _recSub = stream.listen(_recBuf.add);
      _recSecs = 0;
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _recSecs++);
        if (_recSecs >= 60) _stopRecordingAndTranscribe();
      });
      setState(() => _recording = true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Uint8List _wav(Uint8List pcm, int rate) {
    final b = ByteData(44);
    void str(int o, String v) {
      for (var i = 0; i < v.length; i++) {
        b.setUint8(o + i, v.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + pcm.length, Endian.little);
    str(8, 'WAVEfmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, rate, Endian.little);
    b.setUint32(28, rate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, pcm.length, Endian.little);
    return Uint8List.fromList([...b.buffer.asUint8List(), ...pcm]);
  }

  Future<void> _stopRecordingAndTranscribe() async {
    if (!_recording) return;
    _recTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    await _recSub?.cancel();
    _recSub = null;
    final pcm = _recBuf.takeBytes();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _transcribing = true;
    });
    // < 0,4 giây = bấm nhầm.
    if (pcm.length < 16000 * 2 * 0.4) {
      setState(() => _transcribing = false);
      return;
    }
    final text = await _api.aiTranscribe(_wav(pcm, 16000), 'audio/wav');
    if (!mounted) return;
    setState(() => _transcribing = false);
    if (text == null) {
      // AI chưa bật / hết lượt — lần sau dùng nhận dạng của máy.
      setState(() => _aiVoice = false);
      NotificationOverlayManager().showWarning(
        title: 'Chưa nhận được giọng nói qua AI',
        message: tr('Chuyển sang nhận dạng giọng nói của máy — bấm micro và nói lại.'),
      );
      return;
    }
    if (text.trim().isEmpty) {
      NotificationOverlayManager().showWarning(
          title: 'Chưa nghe rõ', message: tr('Bạn nói lại gần micro hơn nhé.'));
      return;
    }
    _inputCtrl.text = text.trim();
    _send();
  }

  Future<void> _stopSpeaking() async {
    _speakGen++;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    if (mounted) setState(() => _ttsSpeaking = false);
  }

  Future<void> _initTts() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          final engines = await _tts.getEngines;
          final names = engines is List
              ? engines.map((e) => e.toString()).toList()
              : const <String>[];
          if (names.any((e) => e.contains('com.google.android.tts'))) {
            await _tts.setEngine('com.google.android.tts');
          }
        } catch (_) {}
      }
      await _tts.setLanguage('vi-VN');
      // Tốc độ / cao độ tự nhiên: iOS 0.5 = bình thường, Android / web 1.0 = bình thường (hơi chậm cho dễ nghe).
      final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      await _tts.setSpeechRate(kIsWeb ? 0.95 : (ios ? 0.5 : 0.92));
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      if (!kIsWeb) {
        await _tts.awaitSpeakCompletion(true);
        try {
          await _tts.setSharedInstance(true);
        } catch (_) {}
      }
      await _preferVietnameseVoice();
      _tts.setStartHandler(() {
        if (mounted) setState(() => _ttsSpeaking = true);
      });
      _tts.setCompletionHandler(() {
        if (mounted) setState(() => _ttsSpeaking = false);
      });
      _tts.setErrorHandler((_) {
        if (mounted) setState(() => _ttsSpeaking = false);
      });
    } catch (_) {}
  }

  Future<void> _preferVietnameseVoice() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return;
      var bestName = '';
      var bestLocale = 'vi-VN';
      var bestScore = -1;
      for (final e in raw.whereType<Map>()) {
        final name = (e['name'] ?? '').toString();
        final locale = (e['locale'] ?? '').toString();
        final loc = locale.toLowerCase();
        if (!loc.startsWith('vi')) continue;
        final n = name.toLowerCase();
        final q = (e['quality'] ?? '').toString().toLowerCase();
        // Ưu tiên giọng chất lượng cao (iOS Premium / Enhanced, giọng neural / mạng của Google) — đọc có ngữ điệu;
        // giọng nén «compact» / cài sẵn cơ bản đọc đều như robot. Giọng mạng cần Internet (trợ lý vốn đã cần).
        var s = 10;
        if (n.contains('premium') || q.contains('premium')) s += 60;
        if (n.contains('enhanced') || q.contains('enhanced')) s += 45;
        if (n.contains('neural') || n.contains('natural') || n.contains('wavenet')) s += 35;
        if (n.contains('network')) s += 25;
        if (n.contains('local')) s += 10;
        if (n.contains('compact')) s -= 10;
        if (n.contains('-x-gft-')) s -= 20;
        if (n.contains('vif') || n.contains('female') || n.contains('nữ') || n.contains('linh')) s += 8;
        if (s > bestScore) {
          bestScore = s;
          bestName = name;
          bestLocale = locale.isEmpty ? 'vi-VN' : locale;
        }
      }
      if (bestName.isEmpty) return;
      final ok = await _tts.setVoice({'name': bestName, 'locale': bestLocale});
      if (ok == 0 || ok == false) {
        await _tts.setLanguage('vi-VN');
      }
    } catch (_) {
      try {
        await _tts.setLanguage('vi-VN');
      } catch (_) {}
    }
  }

  void _dismissKeyboard() {
    _inputFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  String _plainForSpeech(String raw) {
    var t = raw
        .replaceAll(RegExp(r'\[\[(?:ACTION|CREATE|GUIDE):[^\]]*\]\]'), ' ')
        .replaceAll(RegExp(r'[*#_`]'), ' ')
        .replaceAll(RegExp(r'[🎂🎉🎁⚠️❌✅📅🕐📝📖•·]'), ' ')
        .replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Tiền, giờ, ngày, %, chữ viết tắt → chữ đọc tự nhiên (không đọc «một chấm năm trăm…», «en vê»).
    return ViSpeechText.normalize(t);
  }

  List<String> _splitForSpeech(String raw) {
    final plain = _plainForSpeech(raw);
    if (plain.isEmpty) return const [];
    final parts = plain
        .split(RegExp(r'(?<=[.!?…])\s+|\n+|•\s*'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return [plain];
    final out = <String>[];
    for (final p in parts) {
      if (p.length <= 220) {
        out.add(p);
        continue;
      }
      // Câu rất dài: chia ở dấu phẩy / chấm phẩy, gom lại đến ~200 ký tự.
      var buf = StringBuffer();
      for (final seg in p.split(RegExp(r'(?<=[,;])\s+'))) {
        if (buf.length + seg.length > 200 && buf.isNotEmpty) {
          out.add(buf.toString().trim());
          buf = StringBuffer();
        }
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(seg);
      }
      final rest = buf.toString().trim();
      if (rest.isNotEmpty) out.add(rest);
    }
    return out;
  }

  // Nghỉ ngắn giữa các câu (giọng máy đã tự ngắt ở dấu phẩy) — nghỉ dài làm câu rời rạc.
  int _pauseMs(String chunk) {
    if (chunk.endsWith('?') || chunk.endsWith('!')) return 260;
    if (chunk.endsWith('.') || chunk.endsWith('…')) return 200;
    return 140;
  }

  Future<void> _speakReply(String raw) async {
    if (!_ttsEnabled) return;
    final chunks = _splitForSpeech(raw);
    if (chunks.isEmpty) return;
    final gen = ++_speakGen;
    if (_aiVoice) {
      // Giọng Gemini: đọc liền mạch, có ngữ điệu. Lỗi / hết lượt → giọng của máy bên dưới.
      var text = chunks.join(' ');
      if (text.length > 1200) text = '${text.substring(0, 1200)}…';
      final wav = await _api.aiSpeak(text, voice: _voiceName);
      if (!mounted || gen != _speakGen || !_ttsEnabled) return;
      if (wav != null) {
        try {
          await _player.stop();
          setState(() => _ttsSpeaking = true);
          await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
          return;
        } catch (_) {
          if (mounted) setState(() => _ttsSpeaking = false);
        }
      }
    }
    try {
      await _tts.stop();
    } catch (_) {}
    for (var i = 0; i < chunks.length; i++) {
      if (!mounted || gen != _speakGen || !_ttsEnabled) return;
      try {
        await _tts.speak(chunks[i]);
      } catch (_) {
        break;
      }
      if (i < chunks.length - 1) {
        await Future.delayed(Duration(milliseconds: _pauseMs(chunks[i])));
      }
    }
  }

  Future<void> _initStt() async {
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) return;
      final ok = await _stt.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (e) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (mounted) setState(() => _sttReady = ok);
    } catch (_) {}
  }

  @override
  void dispose() {
    _speakGen++;
    _inputFocus.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _tts.stop();
    if (_isListening) _stt.stop();
    _recTimer?.cancel();
    _recSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_transcribing) return;
    if (_ttsSpeaking) await _stopSpeaking();
    if (_recording) {
      await _stopRecordingAndTranscribe();
      return;
    }
    if (_aiVoice && !_isListening && await _startRecording()) return;
    if (!_sttReady) {
      NotificationOverlayManager().showWarning(
          title: 'Micro chưa sẵn sàng',
          message: tr('Vui lòng cấp quyền micro và thử lại'));
      await _initStt();
      return;
    }
    if (_isListening) {
      await _stt.stop();
      if (_partialTranscript.trim().isNotEmpty) {
        _inputCtrl.text = _partialTranscript.trim();
      }
      setState(() => _isListening = false);
      return;
    }
    setState(() {
      _isListening = true;
      _partialTranscript = '';
    });

    // Chọn locale tốt nhất: ưu tiên vi-VN từ thiết bị, fallback vi_VN
    String? bestLocale;
    try {
      final locales = await _stt.locales();
      final vi = locales.firstWhere(
        (l) => l.localeId.toLowerCase().startsWith('vi'),
        orElse: () => stt.LocaleName('vi_VN', 'Vietnamese'),
      );
      bestLocale = vi.localeId;
    } catch (_) {
      bestLocale = 'vi_VN';
    }

    await _stt.listen(
      localeId: bestLocale,
      // Tăng pauseFor để không cắt câu giữa chừng khi người dùng ngập ngừng
      pauseFor: const Duration(seconds: 4),
      // Tổng thời gian tối đa 1 lượt nói
      listenFor: const Duration(seconds: 60),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        // false = dùng nhận dạng đám mây của Google → chính xác hơn nhiều cho tiếng Việt
        onDevice: false,
        // dictation → cho phép câu dài, không bị ép thành lệnh ngắn
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (r) {
        setState(() {
          _partialTranscript = r.recognizedWords;
          _inputCtrl.text = _partialTranscript;
          _inputCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputCtrl.text.length),
          );
        });
        if (r.finalResult) {
          setState(() => _isListening = false);
          // Tự động gửi sau khi nói xong (nếu có nội dung)
          if (_partialTranscript.trim().length >= 2) {
            _send();
          }
        }
      },
    );
  }

  Future<void> _send() async {
    _dismissKeyboard();
    // On mobile, require consent before sending any data to AI
    if (!kIsWeb && !_consentGiven) {
      _showConsentDialog();
      return;
    }
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() {
      _messages.add(_ChatMsg('user', text));
      _inputCtrl.clear();
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final history = _messages
          .where((m) => m.content.trim().isNotEmpty)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
      final result = await _api.aiAssistantChat(messages: history);
      if (!mounted) return;
      if (result['isSuccess'] == true) {
        final data = result['data'] as Map<String, dynamic>?;
        final reply = (data?['reply'] as String?)?.trim() ?? '';
        final actions = ((data?['actions'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        final creates = ((data?['creates'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        final guides = ((data?['guides'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        final reports = ((data?['reports'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        final pending = ((data?['pendingActions'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => _PendingAction.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        setState(() {
          _messages.add(_ChatMsg('assistant', reply,
              actions: actions, creates: creates, guides: guides, reports: reports, pending: pending));
        });
        _scrollToBottom();
        // Không chờ đọc xong — tắt «Đang suy nghĩ…» ngay, giọng đọc tải song song.
        if (_ttsEnabled && reply.isNotEmpty) unawaited(_speakReply(reply));
      } else {
        final msg = (result['message'] as String?) ?? 'Lỗi trợ lý ảo';
        setState(() {
          _messages.add(_ChatMsg('assistant', '⚠️ $msg'));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMsg('assistant', '⚠️ Lỗi: $e'));
        });
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleAction(String action) {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (action.startsWith('open:')) {
      final code = action.substring(5);
      if (!perm.canView(code)) {
        NotificationOverlayManager().showError(title: 'Không có quyền', message: 'Tài khoản không có quyền xem mục này.');
        return;
      }
      Navigator.of(context).pop();
      NavigationNotifier.goToModule(code);
      return;
    }
    if (!AiAssistantPermissions.canAction(action, perm)) {
      NotificationOverlayManager().showError(
        title: 'Không có quyền',
        message: AiAssistantPermissions.deniedMessageForAction(action),
      );
      return;
    }

    // Close sheet first so navigation target becomes visible
    Navigator.of(context).pop();
    switch (action) {
      case 'nav_leave':
        NavigationNotifier.goToLeaves();
        break;
      case 'nav_leave_create':
        NavigationNotifier.goToLeaveCreate();
        break;
      case 'nav_work_schedule':
        NavigationNotifier.goToWorkSchedule();
        break;
      case 'nav_shift_change':
        NavigationNotifier.goToShiftSwapCreate();
        break;
      case 'nav_attendance_correction':
        NavigationNotifier.goToAttendanceCorrections();
        break;
      case 'nav_attendance_correction_create':
        NavigationNotifier.goToAttendanceCorrectionCreate();
        break;
      case 'nav_attendance_history':
      case 'nav_attendance':
        NavigationNotifier.goToAttendance();
        break;
      case 'nav_payroll':
        NavigationNotifier.goToPayModule(preferPayslip: false);
        break;
      case 'nav_payslip':
        NavigationNotifier.goToPayslip();
        break;
      case 'nav_feedback':
        NavigationNotifier.goToModule('Feedback');
        break;
      case 'nav_feedback_create':
        NavigationNotifier.goToFeedbackCreate();
        break;
      case 'nav_communication':
        NavigationNotifier.goToCommunication();
        break;
      case 'nav_advance':
        NavigationNotifier.goToAdvanceRequests();
        break;
      case 'nav_advance_create':
        NavigationNotifier.goToAdvanceCreate();
        break;
      case 'nav_overtime':
        NavigationNotifier.goToOvertime();
        break;
      case 'nav_overtime_create':
        NavigationNotifier.goToOvertime(openCreate: true);
        break;
      case 'nav_field_checkin':
      case 'nav_field_checkin_create':
        NavigationNotifier.goToModule('FieldCheckIn');
        break;
      case 'nav_meal':
        NavigationNotifier.goToModule('Meal');
        break;
      case 'nav_meal_register':
        NavigationNotifier.goToMealRegister();
        break;
      case 'nav_business_trip':
        NavigationNotifier.goToModule('BusinessTripExpense');
        break;
      case 'nav_business_trip_create':
        NavigationNotifier.goToBusinessTripCreate();
        break;
      case 'nav_penalty':
        NavigationNotifier.goToPenaltyTicketsNav();
        break;
      case 'nav_kpi':
        NavigationNotifier.goToKpi();
        break;
      case 'nav_tasks':
        NavigationNotifier.goToTaskManagement();
        break;
      case 'nav_assets':
        NavigationNotifier.goToAssetManagement();
        break;
      case 'nav_cash':
        NavigationNotifier.goToCashTransaction();
        break;
      case 'nav_bonus_penalty':
        NavigationNotifier.goToBonusPenalty();
        break;
      case 'nav_employees':
        NavigationNotifier.goToEmployees();
        break;
      case 'nav_departments':
        NavigationNotifier.goToDepartments();
        break;
      case 'nav_dashboard':
        NavigationNotifier.goTo(NavigationNotifier.dashboard);
        break;
      case 'nav_production':
        NavigationNotifier.goToModule('Production');
        break;
      case 'nav_mobile_attendance':
        NavigationNotifier.goToMobileAttendance();
        break;
      case 'nav_schedule_approval':
        NavigationNotifier.goToScheduleApproval();
        break;
      case 'nav_leave_report':
        NavigationNotifier.goToModule('LeaveReport');
        break;
      case 'nav_cash_report':
        NavigationNotifier.goToModule('CashReport');
        break;
      case 'nav_advance_report':
        NavigationNotifier.goToModule('AdvanceReport');
        break;
      case 'nav_business_trip_report':
        NavigationNotifier.goToModule('BusinessTripReport');
        break;
      case 'nav_attendance_summary':
        NavigationNotifier.goToModule('AttendanceSummary');
        break;
      case 'nav_penalty_report':
        NavigationNotifier.goToModule('PenaltyReport');
        break;
      case 'nav_pos_sell':
        NavigationNotifier.goToModule('PosSell');
        break;
      case 'nav_pos_reports':
        NavigationNotifier.goToModule('PosSalesReport');
        break;
      case 'nav_pos_products':
        NavigationNotifier.goToModule('PosProducts');
        break;
      case 'nav_pos_printers':
        SettingsHubScreen.openCode('printers');
        NavigationNotifier.goToModule('SettingsHub');
        break;
      default:
        NotificationOverlayManager()
            .showInfo(title: 'Thao tác', message: action);
    }
  }

  void _handleGuide(String guideTag) {
    final parts = guideTag.split('/');
    if (parts.length != 2) {
      NotificationOverlayManager()
          .showInfo(title: 'Hướng dẫn', message: guideTag);
      return;
    }
    final mode = parts[0].trim().toLowerCase();
    final stepId = parts[1].trim();
    if (!LandingGuideData.isKnownSection(mode) || stepId.isEmpty) {
      NotificationOverlayManager()
          .showInfo(title: 'Hướng dẫn', message: guideTag);
      return;
    }
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LandingGuideScreen(
          initialLink: GuideDeepLink(section: mode, stepId: stepId),
        ),
      ),
    );
  }

  /// Handle [[CREATE:...]] — API trực tiếp hoặc mở form tạo tương ứng.
  Future<void> _handleCreate(String createTag) async {
    if (_isSending) return;
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!AiAssistantPermissions.canCreate(createTag, perm)) {
      NotificationOverlayManager().showError(
        title: 'Không có quyền',
        message: AiAssistantPermissions.deniedMessageForCreate(createTag),
      );
      return;
    }

    try {
      final parts = createTag.split(',');
      final type = parts[0].trim();
      final params = <String, String>{};
      String? reasonAccum;
      for (final p in parts.skip(1)) {
        final idx = p.indexOf('=');
        if (idx > 0) {
          final key = p.substring(0, idx).trim();
          final val = p.substring(idx + 1).trim();
          if (key == 'reason') {
            reasonAccum = val;
          } else {
            params[key] = val;
          }
        } else if (reasonAccum != null) {
          reasonAccum = '$reasonAccum,$p';
        }
      }
      if (reasonAccum != null) params['reason'] = reasonAccum;

      if (type == 'attendance_correction') {
        final date = params['date'];
        final time = params['time'];
        final reason = params['reason'] ?? 'Quên chấm công';
        final actionStr = params['action'] ?? 'add';
        // CorrectionAction trên server: Add = 0, Edit = 1, Delete = 2.
        final actionInt = actionStr == 'edit'
            ? 1
            : actionStr == 'delete'
                ? 2
                : 0;

        if (date == null || time == null) {
          setState(() {
            _messages.add(
                _ChatMsg('assistant', '⚠️ Thiếu ngày hoặc giờ để tạo phiếu.'));
          });
          _scrollToBottom();
          return;
        }

        setState(() => _isSending = true);
        _scrollToBottom();

        final result = await _api.createAttendanceCorrection(
          action: actionInt,
          newDate: date,
          newTime: time,
          reason: reason,
        );
        if (!mounted) return;

        if (result['isSuccess'] == true) {
          final reply = '✅ Đã tạo yêu cầu sửa giờ thành công!\n'
              '📅 Ngày: ${_formatDate(date)}\n'
              '🕐 Giờ: $time\n'
              '📝 Lý do: $reason\n'
              'Trạng thái: Đang chờ duyệt.';
          setState(() {
            _messages.add(_ChatMsg('assistant', reply));
          });
          if (_ttsEnabled) {
            await _speakReply(
                'Đã tạo yêu cầu sửa giờ thành công. Đang chờ duyệt.');
          }
        } else {
          final msg = (result['message'] as String?) ?? 'Lỗi không xác định';
          setState(() {
            _messages
                .add(_ChatMsg('assistant', '❌ Không tạo được phiếu: $msg'));
          });
        }
        return;
      }

      // Các loại khác: mở form tạo đúng màn hình (prefill nếu có).
      Navigator.of(context).pop();
      switch (type) {
        case 'leave':
          NavigationNotifier.goToLeaveCreate();
          break;
        case 'advance':
          NavigationNotifier.goToAdvanceCreate();
          break;
        case 'feedback':
          NavigationNotifier.goToFeedbackCreate();
          break;
        case 'meal':
          NavigationNotifier.goToMealRegister();
          break;
        case 'overtime':
          NavigationNotifier.goToOvertime(openCreate: true);
          break;
        case 'shift_swap':
          NavigationNotifier.goToShiftSwapCreate();
          break;
        case 'field_assignment':
          NavigationNotifier.goToModule('FieldCheckIn');
          break;
        case 'business_trip':
          NavigationNotifier.goToBusinessTripCreate();
          break;
        default:
          NotificationOverlayManager().showInfo(
            title: 'Thông báo',
            message: tr('Loại phiếu "$type" chưa hỗ trợ tạo từ trợ lý.'),
          );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMsg('assistant', '❌ Lỗi: $e'));
        });
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  String _formatDate(String isoDate) {
    try {
      final d = DateTime.parse(isoDate);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return isoDate;
    }
  }

  String _createLabel(String tag) {
    if (tag.startsWith('attendance_correction')) {
      final params = <String, String>{};
      for (final p in tag.split(',').skip(1)) {
        final idx = p.indexOf('=');
        if (idx > 0) {
          params[p.substring(0, idx).trim()] = p.substring(idx + 1).trim();
        }
      }
      final time = params['time'] ?? '';
      final date = params['date'] != null ? _formatDate(params['date']!) : '';
      return '✅ Xác nhận tạo phiếu sửa giờ${date.isNotEmpty ? " $date" : ""}${time.isNotEmpty ? " lúc $time" : ""}';
    }
    final type = tag.split(',').first.trim();
    return switch (type) {
      'leave' => '✅ Mở form xin nghỉ phép',
      'advance' => '✅ Mở form ứng lương',
      'feedback' => '✅ Mở form phản ánh',
      'meal' => '✅ Mở đăng ký ăn',
      'overtime' => '✅ Mở form tăng ca',
      'shift_swap' => '✅ Mở form đổi ca',
      'business_trip' => '✅ Mở hồ sơ công tác mới',
      'field_assignment' => '✅ Mở bản đồ / công tác',
      _ => '✅ Xác nhận tạo',
    };
  }

  (String, IconData) _actionLabelIcon(String action) {
    if (action.startsWith('open:')) {
      return ('Mở ${PermissionNavigation.label(action.substring(5))}', Icons.open_in_new_rounded);
    }
    switch (action) {
      case 'nav_leave':
        return ('Xem nghỉ phép', Icons.beach_access_rounded);
      case 'nav_leave_create':
        return ('+ Thêm phiếu nghỉ', Icons.beach_access_rounded);
      case 'nav_work_schedule':
        return ('Lịch làm việc', Icons.calendar_month_rounded);
      case 'nav_shift_change':
        return ('+ Đổi ca', Icons.swap_horiz_rounded);
      case 'nav_attendance_correction':
        return ('Phiếu sửa giờ', Icons.edit_calendar_rounded);
      case 'nav_attendance_correction_create':
        return ('+ Sửa giờ / Quên chấm', Icons.edit_calendar_rounded);
      case 'nav_attendance_history':
      case 'nav_attendance':
        return ('Lịch sử chấm công', Icons.history_rounded);
      case 'nav_payroll':
      case 'nav_payslip':
        return ('Phiếu lương', Icons.payments_rounded);
      case 'nav_feedback':
        return ('Phản ánh / Ý kiến', Icons.feedback_rounded);
      case 'nav_feedback_create':
        return ('+ Gửi phản ánh', Icons.feedback_rounded);
      case 'nav_communication':
        return ('Bảng tin', Icons.campaign_rounded);
      case 'nav_advance':
        return ('Ứng lương', Icons.account_balance_wallet_rounded);
      case 'nav_advance_create':
        return ('+ Thêm phiếu ứng lương', Icons.account_balance_wallet_rounded);
      case 'nav_overtime':
        return ('Tăng ca / OT', Icons.access_time_rounded);
      case 'nav_overtime_create':
        return ('+ Đăng ký tăng ca', Icons.access_time_rounded);
      case 'nav_field_checkin':
        return ('Đi công tác', Icons.location_on_rounded);
      case 'nav_field_checkin_create':
        return ('+ Tạo phiếu công tác', Icons.location_on_rounded);
      case 'nav_meal':
      case 'nav_meal_register':
        return ('Đăng ký ăn', Icons.restaurant_rounded);
      case 'nav_kpi':
        return ('KPI cá nhân', Icons.flag_rounded);
      case 'nav_tasks':
        return ('Công việc', Icons.task_alt_rounded);
      case 'nav_assets':
        return ('Tài sản', Icons.inventory_2_rounded);
      case 'nav_cash':
        return ('Giao dịch quỹ', Icons.account_balance_rounded);
      case 'nav_bonus_penalty':
        return ('Thưởng phạt', Icons.workspace_premium_rounded);
      case 'nav_employees':
        return ('Nhân viên', Icons.people_rounded);
      case 'nav_departments':
        return ('Phòng ban', Icons.account_tree_rounded);
      case 'nav_dashboard':
        return ('Tổng quan', Icons.dashboard_rounded);
      case 'nav_business_trip':
        return ('Công tác phí', Icons.flight_takeoff_rounded);
      case 'nav_business_trip_create':
        return ('+ Hồ sơ công tác', Icons.flight_takeoff_rounded);
      case 'nav_penalty':
        return ('Phiếu phạt', Icons.gavel_rounded);
      case 'nav_production':
        return ('Sản lượng', Icons.precision_manufacturing_rounded);
      case 'nav_mobile_attendance':
        return ('Chấm công Mobile', Icons.phone_android_rounded);
      case 'nav_schedule_approval':
        return ('Duyệt lịch làm việc', Icons.fact_check_rounded);
      case 'nav_leave_report':
        return ('BC nghỉ phép', Icons.bar_chart_rounded);
      case 'nav_cash_report':
        return ('BC thu chi', Icons.bar_chart_rounded);
      case 'nav_advance_report':
        return ('BC ứng lương', Icons.bar_chart_rounded);
      case 'nav_business_trip_report':
        return ('BC công tác phí', Icons.bar_chart_rounded);
      case 'nav_attendance_summary':
        return ('Tổng hợp chấm công', Icons.summarize_rounded);
      case 'nav_penalty_report':
        return ('BC phạt', Icons.bar_chart_rounded);
      case 'nav_pos_sell':
        return ('Bán hàng POS', Icons.point_of_sale_rounded);
      case 'nav_pos_reports':
        return ('Báo cáo POS', Icons.analytics_rounded);
      case 'nav_pos_products':
        return ('Hàng hóa', Icons.inventory_2_rounded);
      case 'nav_pos_printers':
        return ('Máy in POS', Icons.print_rounded);
      default:
        return (action, Icons.open_in_new);
    }
  }

  String _guideLabel(String tag) {
    final parts = tag.split('/');
    if (parts.length != 2) return 'Xem hướng dẫn';
    final mode = parts[0].trim().toLowerCase();
    final stepId = parts[1].trim();
    final steps = LandingGuideData.defaults.stepsAt(
      LandingGuideData.indexForKey(mode),
    );
    for (final s in steps) {
      if (s.id == stepId) return '📖 ${s.title}';
    }
    return '📖 Hướng dẫn: $stepId';
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: viewInsets),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildMessages()),
                _buildInputBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: SboxColors.slate200),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: SboxColors.violet,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Icon(Icons.auto_awesome, color: SboxColors.violet),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Trợ lý ảo'),
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text(tr('Phân tích bán hàng, nhân sự từ dữ liệu cửa hàng'),
                    style: TextStyle(fontSize: 11, color: SboxColors.slate500)),
              ],
            ),
          ),
          if (_ttsSpeaking)
            IconButton(
              tooltip: tr('Dừng đọc'),
              onPressed: _stopSpeaking,
              icon: const Icon(Icons.stop_circle_outlined, color: SboxColors.violet),
            ),
          IconButton(
            tooltip: tr(_ttsEnabled ? 'Tắt đọc' : 'Bật đọc'),
            onPressed: () async {
              if (_ttsEnabled) await _stopSpeaking();
              setState(() => _ttsEnabled = !_ttsEnabled);
            },
            icon: Icon(_ttsEnabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: tr('Giọng nói'),
            icon: const Icon(Icons.record_voice_over_outlined),
            onSelected: (v) async {
              if (v == 'ai') {
                setState(() => _aiVoice = !_aiVoice);
              } else {
                setState(() {
                  _voiceName = v;
                  _aiVoice = true;
                  _ttsEnabled = true;
                });
                unawaited(_speakReply('Xin chào, tôi là trợ lý ảo của cửa hàng.'));
              }
              await _saveVoicePrefs();
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'ai',
                checked: _aiVoice,
                child: Text(tr('Giọng AI tự nhiên (nghe & đọc)')),
              ),
              const PopupMenuDivider(),
              for (final v in _voices)
                CheckedPopupMenuItem(
                  value: v.$1,
                  checked: _aiVoice && _voiceName == v.$1,
                  child: Text(tr(v.$2)),
                ),
            ],
          ),
          IconButton(
            tooltip: tr('Đóng'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollCtrl,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length + (_isSending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _messages.length) return _buildTypingBubble();
        // Mới mở: lời chào + câu hỏi gợi ý theo quyền.
        if (i == 0 && _messages.length == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_buildBubble(_messages[0]), _buildSuggestions()],
          );
        }
        return _buildBubble(_messages[i]);
      },
    );
  }

  /// Câu hỏi mẫu — chỉ hiện nhóm người dùng có quyền xem báo cáo.
  List<String> _suggestionList() {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final out = <String>[];
    if (perm.canView('PosSalesReport') || perm.canView('PosReportRevenue')) {
      out.addAll([
        'Phân tích doanh thu tháng này so với tháng trước',
        'Ngày nào trong tuần bán được nhiều nhất?',
      ]);
    }
    if (perm.canView('PosReportSoldGoods')) out.add('Top 10 món bán chạy 7 ngày qua');
    if (perm.canView('PosReportProfit')) out.add('Nhóm hàng nào lãi nhiều nhất tháng này?');
    if (perm.canView('PosProducts')) out.add('Hàng nào tồn lâu không bán được?');
    if (perm.canView('PosReportDebt')) out.add('Khách nào đang nợ nhiều nhất?');
    if (perm.canView('AttendanceReport') || perm.canView('Attendance')) {
      out.add('Ai đi trễ nhiều nhất tháng này?');
    }
    if (perm.canView('LeaveReport')) out.add('Tình hình nghỉ phép tháng này');
    if (perm.canView('Payslip')) out.add('Tổng quỹ lương tháng trước theo phòng ban');
    final analytics = out.length;
    // Thao tác thêm / sửa bằng lời (trợ lý dựng phiếu, người dùng bấm Xác nhận).
    if (perm.canCreate('CashTransaction')) out.add('Tạo phiếu chi 350k tiền điện');
    if (perm.canCreate('PenaltyTickets')) out.add('Phạt An 50k vì đi trễ hôm nay');
    if (perm.canCreate('PosSell')) out.add('Bán 2 Coca cho khách lẻ, trả tiền mặt');
    if (perm.canCreate('AdvanceRequests')) out.add('Ứng lương 2 triệu tiền viện phí');
    if (out.isEmpty) {
      out.addAll(['Tôi còn bao nhiêu ngày phép?', 'Hôm nay tôi chấm công chưa?']);
    }
    // 4 câu phân tích + tối đa 3 câu ra lệnh (để người dùng biết trợ lý lập phiếu được).
    return [...out.take(analytics).take(4), ...out.skip(analytics).take(3)];
  }

  Widget _buildSuggestions() {
    final items = _suggestionList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final q in items)
            ActionChip(
              avatar: const Icon(Icons.insights_rounded, size: 16, color: SboxColors.violet),
              label: Text(tr(q), style: const TextStyle(fontSize: 12)),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFDDD6FE)),
              onPressed: _isSending
                  ? null
                  : () {
                      _inputCtrl.text = q;
                      _send();
                    },
            ),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatMsg m) {
    final isUser = m.role == 'user';
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
      decoration: BoxDecoration(
        color: isUser ? PosTheme.kiotBlue : SboxColors.slate100,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(isUser ? 14 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            tr(m.content),
            style: TextStyle(
              color: isUser ? Colors.white : SboxColors.slate900,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          if (m.reports.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bar_chart_rounded, size: 14, color: SboxColors.slate500),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${tr('Đã xem báo cáo')}: ${m.reports.map(tr).join(', ')}',
                    style: const TextStyle(fontSize: 11, color: SboxColors.slate500),
                  ),
                ),
              ],
            ),
          ],
          for (final a in m.pending) ...[
            const SizedBox(height: 10),
            _actionCard(a),
          ],
          if (m.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Builder(builder: (ctx) {
              final perm =
                  Provider.of<PermissionProvider>(ctx, listen: false);
              final allowed = m.actions
                  .where((a) => AiAssistantPermissions.canAction(a, perm))
                  .toList();
              if (allowed.isEmpty) return const SizedBox.shrink();
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: allowed.map((a) {
                  final li = _actionLabelIcon(a);
                  return ActionChip(
                    avatar:
                        Icon(li.$2, size: 16, color: SboxColors.violet),
                    label: Text(tr(li.$1),
                        style: const TextStyle(
                            fontSize: 12,
                            color: SboxColors.violet,
                            fontWeight: FontWeight.w600)),
                    backgroundColor: const Color(0xFFF3E8FF),
                    side: const BorderSide(color: Color(0xFFDDD6FE)),
                    onPressed: () => _handleAction(a),
                  );
                }).toList(),
              );
            }),
          ],
          if (m.creates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Builder(builder: (ctx) {
              final perm =
                  Provider.of<PermissionProvider>(ctx, listen: false);
              final allowed = m.creates
                  .where((c) => AiAssistantPermissions.canCreate(c, perm))
                  .toList();
              if (allowed.isEmpty) return const SizedBox.shrink();
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: allowed.map((c) {
                  final label = _createLabel(c);
                  return ActionChip(
                    avatar: const Icon(Icons.check_circle_outline_rounded,
                        size: 16, color: SboxColors.success),
                    label: Text(tr(label),
                        style: const TextStyle(
                            fontSize: 12,
                            color: SboxColors.success,
                            fontWeight: FontWeight.w600)),
                    backgroundColor: SboxColors.successSoft,
                    side: const BorderSide(color: Color(0xFF6EE7B7)),
                    onPressed: _isSending ? null : () => _handleCreate(c),
                  );
                }).toList(),
              );
            }),
          ],
          if (m.guides.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: m.guides.map((g) {
                return ActionChip(
                  avatar: const Icon(Icons.menu_book_rounded,
                      size: 16, color: Color(0xFF0369A1)),
                  label: Text(tr(_guideLabel(g)),
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0369A1),
                          fontWeight: FontWeight.w600)),
                  backgroundColor: const Color(0xFFE0F2FE),
                  side: const BorderSide(color: Color(0xFF7DD3FC)),
                  onPressed: () => _handleGuide(g),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
  }

  Widget _buildTypingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: SboxColors.slate100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(tr('Đang suy nghĩ...'),
                style: TextStyle(color: SboxColors.slate500, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAction(_PendingAction a) async {
    setState(() => a.state = 'running');
    final res = await _api.confirmAiAction(a.id);
    if (!mounted) return;
    final ok = res['isSuccess'] == true;
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : const <String, dynamic>{};
    setState(() {
      a.state = ok ? 'done' : 'failed';
      a.result = ok
          ? (data['message']?.toString() ?? 'Đã lưu')
          : (res['message']?.toString() ?? 'Không thực hiện được');
    });
    if (ok && _ttsEnabled) unawaited(_speakReply(a.result!));
  }

  Widget _actionCard(_PendingAction a) {
    final (Color tone, IconData icon) = switch (a.kind) {
      'penalty' || 'update_penalty' => (SboxColors.danger, Icons.gavel_rounded),
      'reward' || 'update_reward' => (SboxColors.success, Icons.emoji_events_outlined),
      'advance' => (const Color(0xFFB45309), Icons.payments_outlined),
      'cash' || 'update_cash' => (const Color(0xFF0369A1), Icons.account_balance_wallet_outlined),
      'sale' => (PosTheme.kiotBlue, Icons.receipt_long_outlined),
      'overtime' => (SboxColors.violet, Icons.more_time_rounded),
      _ => (SboxColors.violet, Icons.fact_check_outlined),
    };
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 6),
          Expanded(
            child: Text(tr(a.title),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tone)),
          ),
          if (a.state == 'pending')
            Text(tr('Chờ xác nhận'), style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
        ]),
        const SizedBox(height: 6),
        for (final (label, value) in a.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 108,
                child: Text(tr(label), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              ),
              Expanded(
                child: Text(tr(value),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SboxColors.slate900)),
              ),
            ]),
          ),
        for (final w in a.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFB45309)),
              const SizedBox(width: 4),
              Expanded(child: Text(tr(w), style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)))),
            ]),
          ),
        const SizedBox(height: 8),
        switch (a.state) {
          'running' => const Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Đang lưu…', style: TextStyle(fontSize: 12)),
            ]),
          'done' => Row(children: [
              const Icon(Icons.check_circle, size: 18, color: SboxColors.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr(a.result ?? 'Đã lưu'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SboxColors.success)),
              ),
              if (a.openModule != null)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    NavigationNotifier.goToModule(a.openModule!);
                  },
                  child: Text(tr('Mở')),
                ),
            ]),
          'discarded' => Text(tr('Đã bỏ phiếu này'),
              style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
          _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (a.state == 'failed')
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('❌ ${tr(a.result ?? '')}',
                      style: const TextStyle(fontSize: 12, color: SboxColors.danger)),
                ),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _confirmAction(a),
                    style: FilledButton.styleFrom(backgroundColor: tone),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(tr(a.state == 'failed' ? 'Thử lại' : 'Xác nhận')),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    unawaited(_api.discardAiAction(a.id));
                    setState(() => a.state = 'discarded');
                  },
                  child: Text(tr('Bỏ')),
                ),
              ]),
            ]),
        },
      ]),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: SboxColors.slate200)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: tr(_isListening || _recording ? 'Dừng & gửi' : 'Nói'),
              onPressed: _transcribing ? null : _toggleListening,
              icon: _transcribing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(
                      _isListening || _recording ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                      color: _isListening || _recording ? Colors.red : SboxColors.violet,
                    ),
            ),
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                focusNode: _inputFocus,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                onTapOutside: (_) => _dismissKeyboard(),
                decoration: InputDecoration(
                  hintText: tr(_recording
                      ? 'Đang nghe ${_recSecs}s — nói xong bấm ■ để gửi'
                      : _transcribing
                          ? 'Đang chép lời…'
                          : _isListening
                              ? 'Đang nghe...'
                              : 'Hỏi hoặc ra lệnh (VD: "Phạt An 50k đi trễ")'),
                  filled: true,
                  fillColor: SboxColors.slate50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Material(
              color:
                  _isSending ? SboxColors.slate300 : SboxColors.violet,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _isSending ? null : _send,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child:
                      Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gói dịch vụ có «Trợ lý AI» (Super Admin / đại lý luôn có).
bool canUseAiAssistant(BuildContext context) {
  final user = Provider.of<AuthProvider>(context, listen: false).user;
  if (user == null) return false;
  if (StoreRoleHelper.bypassesPackageFilter(user.role)) return true;
  final mods = user.allowedModules ?? const <String>[];
  return mods.any((m) => m.toLowerCase() == 'aiassistant');
}

Future<void> showAiAssistant(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AiAssistantSheet(),
  );
}
