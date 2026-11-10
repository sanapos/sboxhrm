import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import '../config/sbox_app_variant.dart';
import '../utils/vi_speech_text.dart';
import '../utils/ai_voice_commands.dart';
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
import '../utils/ai_export_pdf.dart';
import '../utils/file_saver.dart' as file_saver;
import '../utils/image_compress.dart';
import '../utils/pos_report_export.dart';
import '../utils/landing_guide_url.dart';
import '../utils/landing_usage_guide.dart';
import '../utils/navigation_notifier.dart';
import 'notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_locale.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/ai_chat_stream.dart';
import '../screens/ai_action_log_screen.dart';

import './pos/pos_theme.dart';
import '../theme/sbox_tokens.dart';
import 'sbox_icon_tile.dart';
class _GuideGroup {
  const _GuideGroup(this.id, this.icon, this.title, this.sub, this.prompts);
  final String id;
  final IconData icon;
  final String title;
  final String sub;
  final List<String> prompts;
}

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
  /// Câu hỏi gửi lỗi (mạng / máy chủ) — hiện nút «Gửi lại».
  final String? retryText;
  /// Chuỗi cố định của app (lời chào, thông báo lỗi) → dịch theo ngôn ngữ giao diện. Câu người dùng gõ / AI trả lời
  /// giữ nguyên (AI đã trả lời đúng ngôn ngữ; dịch lại theo mẫu dễ dịch nhầm từng đoạn).
  final bool translate;
  /// Biểu đồ nhỏ minh họa số liệu (từ báo cáo thật).
  final List<_AiChart> charts;
  /// Lệnh giọng nói xử lý ngay trên máy («xác nhận», «bỏ») và lời đáp của nó — không gửi lên AI trong lịch sử.
  final bool local;
  /// Có = câu trả lời từ báo cáo thật và tài khoản có quyền Xuất → hiện nút PNG / Excel / PDF.
  final String? exportId;
  /// Vùng chụp PNG (chữ + biểu đồ, không gồm các nút).
  final GlobalKey captureKey = GlobalKey();

  _ChatMsg(this.role, this.content,
      {this.actions = const [],
      this.creates = const [],
      this.guides = const [],
      this.reports = const [],
      this.pending = const [],
      this.retryText,
      this.translate = false,
      this.charts = const [],
      this.local = false,
      this.exportId});
}

/// Biểu đồ trong câu trả lời: bar (cột) / line (đường) / pie (tròn); [openModule] = màn báo cáo đầy đủ.
class _AiChart {
  _AiChart.fromJson(Map<String, dynamic> j)
      : type = (j['type'] ?? 'bar').toString(),
        title = (j['title'] ?? '').toString(),
        labels = ((j['labels'] as List?) ?? []).map((e) => e.toString()).toList(),
        values = ((j['values'] as List?) ?? []).map((e) => (e as num?)?.toDouble() ?? 0).toList(),
        openModule = j['openModule']?.toString();

  final String type;
  final String title;
  final List<String> labels;
  final List<double> values;
  final String? openModule;
}

/// Cuộc trò chuyện giữ trong phiên đăng nhập: đóng / mở lại trợ lý không mất câu hỏi và thẻ phiếu đang chờ.
/// Xóa khi đăng xuất / đổi cửa hàng ([AiAssistantSheet.resetSession]) hoặc bấm «Cuộc trò chuyện mới».
final List<_ChatMsg> _sessionMessages = [];

/// Chip tạo phiếu đã gửi thành công — ẩn đi, bấm lại sẽ gửi thêm một phiếu trùng.
final Set<String> _sessionDoneCreates = {};

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
        openModule = j['openModule']?.toString(),
        highRisk = j['risk']?.toString() == 'high';

  final String id;
  final String kind;
  final String title;
  final List<(String, String)> lines;
  final List<String> warnings;
  final String? openModule;

  /// Xóa / hủy chứng từ / duyệt hàng loạt: thẻ đỏ, hỏi lại trước khi ghi, không hoàn tác được.
  final bool highRisk;

  /// pending | running | done | failed | discarded | undoing | undone
  String state = 'pending';
  String? result;

  /// Hoàn tác được đến lúc này (null = không hoàn tác được).
  DateTime? undoUntil;

  bool get canUndo => state == 'done' && undoUntil != null && DateTime.now().isBefore(undoUntil!);
}

class AiAssistantSheet extends StatefulWidget {
  const AiAssistantSheet({super.key});

  /// Xóa cuộc trò chuyện đang giữ (đăng xuất / đổi cửa hàng — không để lộ sang tài khoản khác).
  static void resetSession() {
    _sessionMessages.clear();
    _sessionDoneCreates.clear();
  }

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

  List<_ChatMsg> get _messages => _sessionMessages;
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

  /// Rảnh tay: đọc xong câu trả lời thì tự nghe tiếp — nói «xác nhận» để lưu thẻ, «dừng» để tắt.
  static const _kHandsFreeKey = 'ai_assistant_hands_free_v1';
  bool _handsFree = false;

  /// Thế hệ lời đọc đang ở đoạn cuối (giọng máy) — đọc xong đoạn này mới nghe tiếp.
  int _lastChunkGen = -1;

  static const _kAiConsentKey = 'ai_assistant_consent_v1';
  bool _consentChecked = false;
  bool _consentGiven = false;

  // Lời chào ngắn; việc trợ lý làm được nằm trong «Trợ lý AI hỗ trợ được gì?» (nhóm → câu gợi ý).
  static const _welcome =
      'Xin chào! Tôi là Trợ lý ảo của cửa hàng. Bạn cứ hỏi, nói vào micro hoặc nhờ tôi làm giúp việc trong app.';

  // SBOX POS iOS không có chức năng nhân sự (App Store 2.3.1): nhóm nhân sự bị ẩn ở [_guideGroups].
  static const _posWelcome = _welcome;

  /// Mở đầu: false = lời chào + nút «hỗ trợ được gì»; true = nhóm chức năng / câu gợi ý.
  bool _guideOpen = false;
  String? _guideGroup;

  void _addWelcome() => _messages.add(
      _ChatMsg('assistant', SboxAppVariant.iosPosApp ? _posWelcome : _welcome, translate: true));

  /// «Cuộc trò chuyện mới»: xóa lịch sử (câu hỏi sau không bị câu cũ ảnh hưởng, đỡ token gửi AI).
  Future<void> _newConversation() async {
    await _stopSpeaking();
    setState(() {
      _messages.clear();
      _guideOpen = false;
      _guideGroup = null;
      _addWelcome();
    });
  }

  @override
  void initState() {
    super.initState();
    _initTts();
    _initStt();
    _loadVoicePrefs();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _ttsSpeaking = false);
      _afterSpeech();
    });
    if (_messages.isEmpty) {
      _addWelcome();
    } else {
      // Mở lại trợ lý: giữ cuộc trò chuyện cũ, cuộn xuống tin mới nhất.
      _scrollToBottom();
    }
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
          SboxAppVariant.iosPosApp
              ? tr('Khi sử dụng trợ lý AI, nội dung câu hỏi, ảnh bạn gửi và số liệu bán hàng liên quan '
                  'sẽ được gửi đến máy chủ của chúng tôi và xử lý bằng Google Gemini AI để tạo phản hồi.\n\n'
                  'Khi bạn nói bằng micro, đoạn ghi âm giọng nói cũng được gửi để chép thành chữ (không lưu lại sau khi chép).\n\n'
                  'Bạn đồng ý để tiếp tục sử dụng tính năng này không?')
              : tr('Khi sử dụng trợ lý AI, nội dung câu hỏi và dữ liệu nhân sự liên quan (ca làm việc, phép, chấm công) '
          'sẽ được gửi đến máy chủ của chúng tôi và xử lý bằng Google Gemini AI để tạo phản hồi.\n\n'
          'Khi bạn nói bằng micro, đoạn ghi âm giọng nói cũng được gửi để chép thành chữ (không lưu lại sau khi chép).\n\n'
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
        _handsFree = prefs.getBool(_kHandsFreeKey) ?? false;
      });
    } catch (_) {}
  }

  Future<void> _saveVoicePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAiVoiceKey, _aiVoice);
      await prefs.setString(_kVoiceNameKey, _voiceName);
      await prefs.setBool(_kHandsFreeKey, _handsFree);
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
      _recStartedAt = DateTime.now();
      _heardSpeech = false;
      _lastLoudAt = null;
      _noiseFloor = null;
      _recSub = stream.listen((chunk) {
        _recBuf.add(chunk);
        _onPcmChunk(chunk);
      });
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

  // ── Phát hiện nói xong (ghi âm AI) ──
  DateTime? _recStartedAt;
  DateTime? _lastLoudAt;
  bool _heardSpeech = false;
  double? _noiseFloor;

  /// Im lặng bao lâu sau khi đã nói thì tự dừng & gửi.
  static const _silenceStop = Duration(milliseconds: 1800);

  /// Micro mở mà không nghe thấy lời trong khoảng này → tự dừng.
  static const _noSpeechStop = Duration(seconds: 8);

  /// Đủ lớn để chắc là tiếng nói ngay trong 0,5 giây đầu (khi chưa đo được mức ồn).
  static const _loudSpeech = 1500.0;

  /// Đo độ lớn từng đoạn PCM 16-bit: 0,5 giây đầu làm mức ồn nền; vượt ngưỡng = đang nói.
  /// Đã nói rồi im ~1,8 giây → tự dừng (trước đây phải bấm ■, quên bấm là ghi đủ 60 giây).
  void _onPcmChunk(Uint8List chunk) {
    if (!_recording || chunk.length < 2) return;
    final data = ByteData.sublistView(chunk);
    var sum = 0.0;
    final n = chunk.length ~/ 2;
    for (var i = 0; i < n; i++) {
      final v = data.getInt16(i * 2, Endian.little).toDouble();
      sum += v * v;
    }
    final rms = math.sqrt(sum / n);
    final now = DateTime.now();
    final sinceStart = now.difference(_recStartedAt ?? now);
    if (sinceStart < const Duration(milliseconds: 500)) {
      // Lấy mức thấp nhất làm nền: nói ngay khi micro vừa mở (rảnh tay) không bị coi là tiếng ồn.
      _noiseFloor = _noiseFloor == null ? rms : math.min(_noiseFloor!, rms);
      if (rms >= _loudSpeech) {
        _heardSpeech = true;
        _lastLoudAt = now;
      }
      return;
    }
    final threshold = math.max(450.0, (_noiseFloor ?? 0) * 2.5);
    if (rms >= threshold) {
      _heardSpeech = true;
      _lastLoudAt = now;
    } else if (_heardSpeech && _lastLoudAt != null && now.difference(_lastLoudAt!) >= _silenceStop) {
      _stopRecordingAndTranscribe();
    } else if (!_heardSpeech && sinceStart >= _noSpeechStop) {
      // Không ai nói → dừng sớm, không ghi đủ 60 giây rồi mới báo.
      _stopRecordingAndTranscribe();
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
    // Đánh dấu ngay (đồng bộ) — bấm ■ trùng lúc tự dừng / hết 60 giây không chép lời hai lần.
    _recording = false;
    _recTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    await _recSub?.cancel();
    _recSub = null;
    final pcm = _recBuf.takeBytes();
    if (!mounted) return;
    setState(() => _transcribing = true);
    // < 0,4 giây = bấm nhầm; không có đoạn nào đủ lớn = toàn tiếng ồn / im lặng → không gửi AI (đỡ lượt, tránh chép bịa).
    if (pcm.length < 16000 * 2 * 0.4 || !_heardSpeech) {
      setState(() => _transcribing = false);
      if (pcm.length >= 16000 * 2 * 0.4) {
        NotificationOverlayManager().showWarning(
            title: 'Chưa nghe rõ', message: tr('Bạn nói lại gần micro hơn nhé.'));
        unawaited(_reportVoiceIssue(tr('Tôi chưa nghe rõ, bạn nói lại nhé.')));
      }
      return;
    }
    final res = await _api.aiTranscribeEx(_wav(pcm, 16000), 'audio/wav', language: _lang);
    if (!mounted) return;
    setState(() => _transcribing = false);
    final text = res.text;
    if (text == null) {
      if (res.status == 409) {
        // Cửa hàng chưa bật AI — lần sau dùng nhận dạng của máy.
        setState(() => _aiVoice = false);
        NotificationOverlayManager().showWarning(
          title: 'Chưa nhận được giọng nói qua AI',
          message: tr('Chuyển sang nhận dạng giọng nói của máy — bấm micro và nói lại.'),
        );
      } else {
        // Hết lượt tạm thời / mạng chậm — giữ chế độ AI, chỉ báo nói lại.
        final (title, message) = switch (res.status) {
          0 => ('Mất kết nối', tr('Chưa gửi được ghi âm — kiểm tra mạng rồi nói lại.')),
          401 => ('Phiên đăng nhập hết hạn', tr('Bạn đăng nhập lại rồi nói lại nhé.')),
          _ => ('AI đang bận', tr('Chưa chép được lời — bạn bấm micro nói lại sau vài giây.')),
        };
        NotificationOverlayManager().showWarning(title: title, message: message);
        unawaited(_reportVoiceIssue(message));
      }
      return;
    }
    if (text.trim().isEmpty) {
      NotificationOverlayManager().showWarning(
          title: 'Chưa nghe rõ', message: tr('Bạn nói lại gần micro hơn nhé.'));
      unawaited(_reportVoiceIssue(tr('Tôi chưa nghe rõ, bạn nói lại nhé.')));
      return;
    }
    _voiceFails = 0;
    _inputCtrl.text = text.trim();
    _send();
  }

  int _voiceFails = 0;

  /// Rảnh tay không nhìn màn hình → lỗi phải nói thành tiếng. Lỗi liền hai lần thì tắt rảnh tay, không lặp mic mãi.
  Future<void> _reportVoiceIssue(String message) async {
    if (!mounted) return;
    if (_handsFree && ++_voiceFails >= 2) {
      _voiceFails = 0;
      await _setHandsFree(false);
      if (mounted) unawaited(_speakReply('$message ${tr('Đã tắt rảnh tay, bấm micro khi cần.')}'));
      return;
    }
    unawaited(_speakReply(message));
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
      await _tts.setLanguage(_speechLocale);
      // Tốc độ tự nhiên: iOS 0.5 = bình thường; Android plugin flutter_tts tự nhân ×2 (0.5 → 1.0 của Android —
      // trước đây đặt 0.92 nên đọc nhanh gần gấp đôi); web 1.0 = bình thường (0.95 hơi chậm cho dễ nghe).
      await _tts.setSpeechRate(kIsWeb ? 0.95 : 0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      // Web cũng chờ đọc xong từng đoạn: plugin bỏ qua lệnh đọc khi đang đọc — trước đây chỉ đọc được câu đầu.
      await _tts.awaitSpeakCompletion(true);
      if (!kIsWeb) {
        try {
          await _tts.setSharedInstance(true);
        } catch (_) {}
      }
      await _preferVoice();
      _tts.setStartHandler(() {
        if (mounted) setState(() => _ttsSpeaking = true);
      });
      _tts.setCompletionHandler(() {
        if (mounted) setState(() => _ttsSpeaking = false);
        if (_lastChunkGen == _speakGen) {
          _lastChunkGen = -1;
          _afterSpeech();
        }
      });
      _tts.setErrorHandler((_) {
        if (mounted) setState(() => _ttsSpeaking = false);
      });
    } catch (_) {}
  }

  /// Ngôn ngữ giao diện = ngôn ngữ trợ lý nghe, đọc và trả lời.
  String get _lang => AppLocale.languageCode;

  static const _speechLocales = {'vi': 'vi-VN', 'en': 'en-US', 'ko': 'ko-KR', 'ja': 'ja-JP', 'zh': 'zh-CN'};

  String get _speechLocale => _speechLocales[_lang] ?? 'vi-VN';

  /// Chọn giọng máy tốt nhất cho ngôn ngữ đang dùng (giọng chất lượng cao trước).
  Future<void> _preferVoice() async {
    final wanted = _speechLocale;
    // Tiếng Trung: giọng phổ thông (zh-CN / cmn), không lấy giọng Quảng Đông (yue / zh-HK).
    bool matches(String loc) => _lang == 'zh'
        ? (loc.startsWith('zh-cn') || loc.startsWith('zh_cn') || loc.startsWith('cmn'))
        : loc.startsWith(_lang);
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return;
      var bestName = '';
      var bestLocale = wanted;
      var bestScore = -1;
      for (final e in raw.whereType<Map>()) {
        final name = (e['name'] ?? '').toString();
        final locale = (e['locale'] ?? '').toString();
        final loc = locale.toLowerCase();
        if (!matches(loc)) continue;
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
          bestLocale = locale.isEmpty ? wanted : locale;
        }
      }
      if (bestName.isEmpty) return;
      final ok = await _tts.setVoice({'name': bestName, 'locale': bestLocale});
      if (ok == 0 || ok == false) {
        await _tts.setLanguage(wanted);
      }
    } catch (_) {
      try {
        await _tts.setLanguage(wanted);
      } catch (_) {}
    }
  }

  void _dismissKeyboard() {
    _inputFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  String _plainForSpeech(String raw) {
    var t = raw
        .replaceAll(RegExp(r'\[\[[^\]]*\]\]'), ' ')
        .replaceAll(RegExp(r'\[\[[^\]]*$'), ' ')
        .replaceAll(RegExp(r'[*#_`|>]'), ' ')
        .replaceAll(RegExp(r'(^|\n)\s*[-•·]\s+'), r'$1')
        // Emoji / ký hiệu (cả cặp surrogate, biến thể FE0F, nối 200D) — trước đây regex không unicode làm vỡ ký tự.
        .replaceAll(
            RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}•·]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_lang == 'vi') {
      // Tiền, giờ, ngày, %, chữ viết tắt → chữ đọc tự nhiên (không đọc «một chấm năm trăm…», «en vê»).
      return ViSpeechText.normalize(t);
    }
    // Ngôn ngữ khác: bỏ dấu chấm ngăn nghìn kiểu Việt (1.234.567đ → 1234567 VND) để giọng máy đọc đúng số.
    return t
        .replaceAllMapped(RegExp(r'(\d)\.(?=\d{3}(\D|$))'), (m) => m[1]!)
        .replaceAllMapped(RegExp(r'(\d)\s?đ\b'), (m) => '${m[1]} VND');
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
    if (!_ttsEnabled) {
      _afterSpeech();
      return;
    }
    final chunks = _splitForSpeech(raw);
    if (chunks.isEmpty) {
      _afterSpeech();
      return;
    }
    final gen = ++_speakGen;
    if (_aiVoice && !_aiSpeakUnavailable) {
      // Giọng Gemini: đọc liền mạch, có ngữ điệu. Lỗi / hết lượt → giọng của máy bên dưới.
      // Giới hạn ~900 ký tự (≈1 phút nghe): chờ tạo âm thanh ngắn hơn, đỡ hạn mức TTS.
      var text = chunks.join(' ');
      if (text.length > 900) text = '${text.substring(0, 900)}…';
      final res = await _api.aiSpeakEx(text, voice: _voiceName, language: _lang);
      // Cửa hàng chưa bật AI → cả phiên đọc bằng giọng máy, không gọi thử (và chờ) mỗi câu nữa.
      if (res.status == 409) _aiSpeakUnavailable = true;
      final wav = res.audio;
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
      if (i == chunks.length - 1) _lastChunkGen = gen;
      try {
        // Chrome đôi khi không báo đọc xong — không để treo cả vòng rảnh tay.
        await _tts.speak(chunks[i]).timeout(const Duration(seconds: 30));
      } catch (_) {
        break;
      }
      if (i < chunks.length - 1) {
        await Future.delayed(Duration(milliseconds: _pauseMs(chunks[i])));
      }
    }
  }

  bool _aiSpeakUnavailable = false;
  bool _micDeniedShown = false;

  /// [ask] = người dùng vừa bấm micro → mới xin quyền (không bật hộp xin quyền ngay khi mở trợ lý).
  Future<void> _initStt({bool ask = false}) async {
    try {
      var mic = await Permission.microphone.status;
      if (!mic.isGranted && ask) mic = await Permission.microphone.request();
      if (mic.isPermanentlyDenied && ask) {
        _micDeniedShown = true;
        NotificationOverlayManager().showWarning(
            title: 'Chưa có quyền micro',
            message: kIsWeb
                ? tr('Bấm biểu tượng ổ khóa trên thanh địa chỉ → cho phép Micro.')
                : tr('Mở Cài đặt của máy → cấp quyền Micro cho ứng dụng.'));
        if (!kIsWeb) await openAppSettings();
        return;
      }
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
    // Hủy hẳn (kể cả đang chờ kết quả cuối) — kết quả đến sau khi đóng không gọi setState / gửi câu hỏi.
    _stt.cancel();
    _recTimer?.cancel();
    _recSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    // Đang chờ trợ lý trả lời: lời chép xong sẽ nằm lại ô nhập, không gửi được.
    if (_transcribing || (_isSending && !_recording && !_isListening)) return;
    // Giọng nói cũng gửi lên AI (ghi âm) — cần đồng ý quyền riêng tư như khi gõ.
    if (!kIsWeb && !_consentGiven) {
      _showConsentDialog();
      return;
    }
    // Luôn dừng, kể cả khi còn đang chờ tạo âm thanh: âm phát đè lên bản ghi sẽ lọt vào micro.
    await _stopSpeaking();
    if (_recording) {
      await _stopRecordingAndTranscribe();
      return;
    }
    if (_aiVoice && !_isListening && await _startRecording()) return;
    if (!_sttReady) {
      await _initStt(ask: true);
      if (!_sttReady) {
        if (!_micDeniedShown) {
          NotificationOverlayManager().showWarning(
              title: 'Micro chưa sẵn sàng', message: tr('Vui lòng cấp quyền micro và thử lại'));
        }
        _micDeniedShown = false;
        return;
      }
    }
    if (_isListening) {
      await _stt.stop();
      // Kết quả cuối đã tự gửi thì _partialTranscript đã xóa — không điền lại chữ cũ vào ô nhập.
      if (_partialTranscript.trim().isNotEmpty && !_isSending) {
        _inputCtrl.text = _partialTranscript.trim();
      }
      if (mounted) setState(() => _isListening = false);
      return;
    }
    setState(() {
      _isListening = true;
      _partialTranscript = '';
    });

    // Nhận dạng theo ngôn ngữ giao diện (vi / en / ko / ja / zh), thiết bị không có thì dùng mã chuẩn.
    String? bestLocale;
    final fallback = _speechLocale.replaceAll('-', '_');
    try {
      final locales = await _stt.locales();
      final hit = locales.firstWhere(
        (l) => l.localeId.toLowerCase().replaceAll('-', '_') == fallback.toLowerCase(),
        orElse: () => locales.firstWhere(
          (l) => l.localeId.toLowerCase().startsWith(_lang),
          orElse: () => stt.LocaleName(fallback, _lang),
        ),
      );
      bestLocale = hit.localeId;
    } catch (_) {
      bestLocale = fallback;
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
        if (!mounted) return;
        setState(() {
          _partialTranscript = r.recognizedWords;
          _inputCtrl.text = _partialTranscript;
          _inputCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputCtrl.text.length),
          );
        });
        if (r.finalResult) {
          final spoken = _partialTranscript.trim();
          setState(() {
            _isListening = false;
            _partialTranscript = '';
          });
          // Tự động gửi sau khi nói xong (nếu có nội dung)
          if (spoken.isNotEmpty) {
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
    if (_attachments.isNotEmpty) {
      if (!_isSending) await _sendOrderFiles(text);
      return;
    }
    if (text.isEmpty || _isSending) return;
    if (await _handleVoiceCommand(text)) return;
    setState(() {
      _messages.add(_ChatMsg('user', text));
      _inputCtrl.clear();
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final result = await _chatWithStream(_historyForAi());
      _showChatResult(result, retryText: text);
    } catch (e) {
      final msg = '${tr('Lỗi')}: $e';
      _messages.add(_ChatMsg('assistant', '⚠️ $msg', retryText: text));
      if (mounted) {
        setState(() {});
        unawaited(_reportVoiceIssue(msg));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Lịch sử gửi AI: bỏ câu hỏi đã lỗi (AI thấy hai lượt liền nhau có thể làm lại lệnh cũ), kèm trạng thái từng thẻ — bấm
  /// Xác nhận / Bỏ không đi qua AI, thiếu ghi chú này AI tưởng thẻ còn chờ và lập lại phiếu đã lưu.
  List<Map<String, String>> _historyForAi() {
    final out = <Map<String, String>>[];
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.local || m.retryText != null) continue;
      if (m.role == 'user' && i + 1 < _messages.length && _messages[i + 1].retryText != null) continue;
      var content = m.content.trim();
      if (m.pending.isNotEmpty) {
        final notes = m.pending.map((a) => '«${a.title}»: ${_cardStateNote(a.state)}').join('; ');
        content = '$content\n(Ghi chú hệ thống về thẻ: $notes)'.trim();
      }
      if (content.isNotEmpty) out.add({'role': m.role, 'content': content});
    }
    return out;
  }

  static String _cardStateNote(String state) => switch (state) {
        'done' => 'đã lưu',
        'discarded' => 'đã bỏ',
        'undone' => 'đã hoàn tác',
        'failed' => 'lưu lỗi',
        'running' || 'undoing' => 'đang xử lý',
        _ => 'đang chờ xác nhận',
      };

  /// Câu đọc khi có thẻ: nghe đủ nội dung trước khi nói «xác nhận» — rảnh tay không nhìn màn hình.
  String _speechWithCards(String reply, List<_PendingAction> cards) {
    if (cards.isEmpty) return reply;
    final b = StringBuffer(reply.length > 250 ? '${reply.substring(0, 250)}…' : reply);
    for (final a in cards) {
      b.write('\n${tr(a.title)}.');
      for (final (label, value) in a.lines.take(5)) {
        b.write(' $label: $value.');
      }
      for (final w in a.warnings.take(2)) {
        b.write(' $w.');
      }
    }
    b.write(cards.any((a) => a.highRisk)
        ? '\n${tr('Nói chắc chắn xác nhận để lưu, hoặc nói bỏ.')}'
        : '\n${tr('Nói xác nhận để lưu, hoặc nói bỏ.')}');
    return b.toString();
  }

  /// Hiện phản hồi của trợ lý: câu trả lời, thẻ xác nhận, biểu đồ — hoặc thông báo lỗi.
  /// Đóng trợ lý giữa chừng vẫn lưu vào phiên: mở lại thấy câu trả lời và thẻ.
  void _showChatResult(Map<String, dynamic> result, {String? retryText}) {
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
      final charts = ((data?['charts'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => _AiChart.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.values.length >= 2)
          .toList();
      _messages.add(_ChatMsg('assistant', reply,
          actions: actions, creates: creates, guides: guides, reports: reports, pending: pending, charts: charts,
          exportId: data?['exportId'] as String?));
      if (!mounted) return;
      _voiceFails = 0;
      setState(() {});
      _scrollToBottom();
      // «Mở phiếu lương» → mở luôn, không cần bấm chip.
      final autoOpen = data?['autoOpen'] as String?;
      if (autoOpen != null && autoOpen.isNotEmpty) {
        _handleAction('open:$autoOpen');
        return;
      }
      // Không chờ đọc xong — tắt «Đang suy nghĩ…» ngay, giọng đọc tải song song (tắt đọc: rảnh tay nghe tiếp luôn).
      unawaited(_speakReply(_speechWithCards(reply, pending)));
    } else {
      final msg = (result['message'] as String?) ?? 'Lỗi trợ lý ảo';
      _messages.add(_ChatMsg('assistant', '⚠️ ${tr(msg)}', retryText: retryText));
      if (!mounted) return;
      setState(() {});
      unawaited(_reportVoiceIssue(tr(msg)));
    }
  }

  // ── Đọc / dịch đơn hàng từ ảnh, PDF, Excel ──
  static const _maxAttachments = 8;

  /// Ảnh / file đang chờ gửi; giữ lại khi gửi lỗi để bấm gửi lại không phải chọn lại.
  final List<({Uint8List bytes, String name})> _attachments = [];
  bool _preparingAttachment = false;

  Future<void> _pickAttachments() async {
    _dismissKeyboard();
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(tr('Chụp ảnh đơn hàng')),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('Chọn ảnh đơn hàng')),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(tr('Chọn file PDF / Excel')),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    var picked = <({Uint8List bytes, String name, bool image})>[];
    if (source == 'camera') {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2200, maxHeight: 2200, imageQuality: 85);
      if (photo != null) picked = [(bytes: await photo.readAsBytes(), name: photo.name, image: false)];
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: source == 'image' ? FileType.image : FileType.custom,
        allowedExtensions: source == 'image' ? null : const ['pdf', 'xlsx', 'xlsm', 'csv', 'tsv', 'txt'],
        allowMultiple: true,
        withData: true,
      );
      picked = [
        for (final f in result?.files ?? const <PlatformFile>[])
          if (f.bytes != null) (bytes: f.bytes!, name: f.name, image: source == 'image'),
      ];
    }
    if (picked.isEmpty || !mounted) return;
    setState(() => _preparingAttachment = true);
    final ready = <({Uint8List bytes, String name})>[];
    for (final f in picked) {
      // Chữ trên đơn cần độ phân giải cao hơn ảnh sản phẩm; HEIC không nén được thì gửi nguyên file.
      if (f.image && !looksLikeHeic(f.bytes)) {
        final out = await prepareImageForUpload(f.bytes, maxEdge: 2200, jpegQuality: 85);
        ready.add((bytes: out.bytes, name: out.decoded ? jpegFileName(f.name) : f.name));
      } else {
        ready.add((bytes: f.bytes, name: f.name));
      }
    }
    if (!mounted) return;
    final room = _maxAttachments - _attachments.length;
    setState(() {
      _attachments.addAll(ready.take(room));
      _preparingAttachment = false;
    });
    if (ready.length > room) {
      NotificationOverlayManager().showWarning(
        title: tr('Tối đa $_maxAttachments ảnh / file mỗi lần'),
        message: tr('Đã bỏ ${ready.length - room} ảnh / file — gửi phần này trước rồi gửi tiếp.'),
      );
    }
  }

  Future<void> _sendOrderFiles(String note) async {
    final names = _attachments.map((a) => a.name).join(', ');
    setState(() {
      _messages.add(_ChatMsg('user', note.isEmpty ? '📎 $names' : '📎 $names\n$note'));
      _inputCtrl.clear();
      _isSending = true;
      _liveStatus = tr('Đang đọc đơn hàng…');
    });
    _scrollToBottom();
    try {
      final result = await _api.aiReadOrder(
          _attachments.map((a) => (bytes: a.bytes as List<int>, name: a.name)).toList(), note: note);
      if (!mounted) return;
      if (result['isSuccess'] == true) _attachments.clear();
      _showChatResult(result);
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add(_ChatMsg('assistant', '⚠️ ${tr('Lỗi')}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _liveStatus = null;
        });
      }
    }
  }

  // ── Xuất câu trả lời ra PNG / Excel / PDF ──
  /// Câu trả lời đang xuất — tránh bấm hai lần, hiện vòng chờ trên đúng nút.
  String? _exporting;

  Widget _exportButtons(_ChatMsg m) {
    Widget button(String kind, IconData icon, Future<void> Function() run) {
      final busy = _exporting == '${m.exportId}/$kind';
      return ActionChip(
        avatar: busy
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 16, color: SboxColors.violet),
        label: Text(kind, style: const TextStyle(fontSize: 12, color: SboxColors.violet, fontWeight: FontWeight.w600)),
        tooltip: tr('Xuất câu trả lời ra $kind'),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFDDD6FE)),
        onPressed: _exporting != null
            ? null
            : () async {
                setState(() => _exporting = '${m.exportId}/$kind');
                try {
                  await run();
                } catch (e) {
                  NotificationOverlayManager().showError(title: tr('Xuất file'), message: tr('Không xuất được file: $e'));
                } finally {
                  if (mounted) setState(() => _exporting = null);
                }
              },
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        button('PNG', Icons.image_outlined, () async {
          await PosReportExport.png(context: context, key: m.captureKey, filePrefix: 'TroLyAo');
        }),
        button('Excel', Icons.table_view_outlined, () async {
          await PosReportExport.serverExcel(
            context: context,
            fetch: () => _api.exportAiAnswerExcel(m.exportId!),
            filePrefix: 'TroLyAo',
          );
        }),
        button('PDF', Icons.picture_as_pdf_outlined, () => _exportPdf(m)),
      ],
    );
  }

  Future<void> _exportPdf(_ChatMsg m) async {
    final res = await _api.getAiExportData(m.exportId!);
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      NotificationOverlayManager().showError(
        title: tr('Xuất file'),
        message: tr('${res['message'] ?? 'Không xuất được file'}'),
      );
      return;
    }
    final bytes = await buildAiExportPdf(Map<String, dynamic>.from(res['data'] as Map));
    final name = 'TroLyAo_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    await file_saver.saveAndOpenFileBytes(bytes, name, 'application/pdf');
    NotificationOverlayManager().showSuccess(title: tr('Xuất file'), message: tr('Đã xuất PDF'));
  }

  Widget _buildAttachmentChips() {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        children: [
          for (final a in _attachments)
            InputChip(
              avatar: Icon(a.name.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_outlined : Icons.attach_file, size: 16),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              visualDensity: VisualDensity.compact,
              onDeleted: _isSending ? null : () => setState(() => _attachments.remove(a)),
            ),
        ],
      ),
    );
  }

  // ── Trả lời dần (stream) ──
  /// Việc trợ lý đang làm (đang xem báo cáo «Doanh thu»…) — hiện trong bong bóng chờ.
  String? _liveStatus;

  /// Chữ đang chạy dần của câu trả lời (chưa lọc thẻ) — thay bằng câu trả lời chính thức khi xong.
  String _liveText = '';

  /// Gửi qua /chat/stream (thấy trạng thái + chữ chạy dần). Máy chủ cũ / lỗi trước khi có dữ liệu → /chat thường.
  Future<Map<String, dynamic>> _chatWithStream(List<Map<String, String>> history) async {
    final body = <String, dynamic>{'messages': history, 'language': _lang};
    var gotAny = false;
    setState(() {
      _liveStatus = null;
      _liveText = '';
    });
    try {
      // Đóng trợ lý giữa chừng vẫn đọc tiếp: hủy luồng sẽ mất câu trả lời đã tốn lượt AI và thẻ vừa lập.
      await for (final ev in aiChatStream(body)) {
        gotAny = true;
        switch (ev.type) {
          case 'status':
            if (mounted) setState(() => _liveStatus = ev.text);
          case 'delta':
            if (mounted) {
              setState(() {
                _liveText += ev.text;
                _liveStatus = null;
              });
              _scrollToBottom();
            }
          case 'reset':
            if (mounted) setState(() => _liveText = '');
          case 'done':
            final res = ev.data['body'];
            if (res is Map) return Map<String, dynamic>.from(res);
            return {'isSuccess': false, 'message': 'Lỗi trợ lý ảo'};
        }
      }
    } catch (e) {
      // Đã nhận một phần mà đứt giữa chừng → không hỏi lại AI lần nữa (đỡ lượt); báo lỗi, có nút Gửi lại.
      if (gotAny) return {'isSuccess': false, 'message': 'Mất kết nối khi trợ lý đang trả lời — bấm Gửi lại.'};
    } finally {
      if (mounted) {
        setState(() {
          _liveStatus = null;
          _liveText = '';
        });
      }
    }
    if (gotAny) return {'isSuccess': false, 'message': 'Mất kết nối khi trợ lý đang trả lời — bấm Gửi lại.'};
    return _api.aiAssistantChat(messages: history, language: _lang);
  }

  /// Chữ đang chạy: bỏ thẻ [[…]] (kể cả thẻ chưa đóng), dấu Markdown — bản chính thức do máy chủ lọc.
  static String _cleanLive(String raw) => raw
      .replaceAll(RegExp(r'\[\[[^\]]*\]\]'), '')
      .replaceAll(RegExp(r'\[\[[^\]]*$'), '')
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAllMapped(RegExp(r'(^|\n)\s*#+\s*'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'(^|\n)(\s*)[*-]\s+'), (m) => '${m[1]}${m[2]}• ')
      .trimLeft();

  /// Gửi lại câu hỏi bị lỗi: bỏ câu hỏi + thông báo lỗi cũ khỏi lịch sử rồi gửi lại như mới.
  void _retry(_ChatMsg failed) {
    if (_isSending || failed.retryText == null) return;
    final i = _messages.indexOf(failed);
    setState(() {
      if (i > 0 && _messages[i - 1].role == 'user' && _messages[i - 1].content == failed.retryText) {
        _messages.removeRange(i - 1, i + 1);
      } else if (i >= 0) {
        _messages.removeAt(i);
      }
      _inputCtrl.text = failed.retryText!;
    });
    _send();
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
          _sessionDoneCreates.add(createTag);
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
                Text(tr('Hỏi số liệu, lập / duyệt / sửa phiếu theo quyền của bạn'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: SboxColors.slate500)),
              ],
            ),
          ),
          if (_messages.length > 1)
            IconButton(
              tooltip: tr('Cuộc trò chuyện mới'),
              onPressed: _isSending ? null : _newConversation,
              icon: const Icon(Icons.add_comment_outlined),
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
            tooltip: tr('Thêm'),
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              if (v == 'log') {
                await Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const AiActionLogScreen()));
                return;
              }
              if (v == 'handsfree') {
                await _setHandsFree(!_handsFree);
                return;
              }
              if (v == 'ai') {
                setState(() => _aiVoice = !_aiVoice);
              } else {
                setState(() {
                  _voiceName = v;
                  _aiVoice = true;
                  _ttsEnabled = true;
                });
                unawaited(_speakReply(tr('Xin chào, tôi là trợ lý ảo của cửa hàng.')));
              }
              await _saveVoicePrefs();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'log',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded),
                  title: Text(tr('Nhật ký thao tác AI')),
                ),
              ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: 'handsfree',
                checked: _handsFree,
                child: Text(tr('Rảnh tay (tự nghe sau khi đọc)')),
              ),
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
            children: [_buildBubble(_messages[0]), _buildGuide()],
          );
        }
        return _buildBubble(_messages[i]);
      },
    );
  }

  /// Nhóm việc trợ lý làm được — chỉ nhóm / câu người dùng có quyền. Mỗi nhóm có câu hỏi số liệu,
  /// câu nhờ làm (trợ lý dựng phiếu, người dùng bấm Xác nhận) và câu hỏi cách dùng app.
  List<_GuideGroup> _guideGroups() {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final hr = !SboxAppVariant.iosPosApp;
    final groups = <_GuideGroup>[];
    void add(String id, IconData icon, String title, String sub, List<String> prompts) {
      if (prompts.isNotEmpty) groups.add(_GuideGroup(id, icon, title, sub, prompts));
    }

    final sales = perm.canView('PosSalesReport') || perm.canView('PosReportRevenue');
    add('sales', Icons.trending_up_rounded, 'Doanh thu & báo cáo', 'Phân tích bán hàng, lãi lỗ', [
      if (sales) 'Phân tích doanh thu tháng này so với tháng trước',
      if (sales) 'Ngày nào trong tuần bán được nhiều nhất?',
      if (perm.canView('PosReportSoldGoods')) 'Top 10 món bán chạy 7 ngày qua',
      if (perm.canView('PosReportProfit')) 'Nhóm hàng nào lãi nhiều nhất tháng này?',
      if (sales) 'Cách xem báo cáo doanh thu?',
    ]);
    add('sell', Icons.point_of_sale_rounded, 'Bán hàng & khuyến mãi', 'Lập đơn, tạo khuyến mãi bằng lời', [
      if (perm.canCreate('PosSell')) 'Bán 2 Coca cho khách lẻ, trả tiền mặt',
      if (perm.canCreate('PosPromotions')) 'Khuyến mãi giảm 10% hóa đơn từ 500k cuối tuần',
      if (perm.canCreate('PosSell')) 'Cách hủy một hóa đơn đã bán?',
    ]);
    final stock = perm.canView('PosReportStock') || perm.canView('PosProducts');
    add('stock', Icons.inventory_2_rounded, 'Hàng hóa & kho', 'Tồn kho, nhập hàng, đổi giá', [
      if (perm.canView('PosProducts')) 'Hàng nào tồn lâu không bán được?',
      if (perm.canView('PosReportStock') && perm.canEdit('PosPurchaseReceipts'))
        'Hàng nào cần nhập tuần này? Lập sẵn phiếu nhập',
      if (perm.canEdit('PosPurchaseReceipts')) 'Nhập 24 lon Coca giá 9 nghìn',
      if (perm.canEdit('PosProducts')) 'Đổi giá bán Coca thành 12 nghìn',
      if (stock) 'Cách thêm hàng hóa mới?',
    ]);
    add('money', Icons.account_balance_wallet_rounded, 'Thu chi & công nợ', 'Sổ quỹ, phiếu thu chi, khách nợ', [
      if (perm.canView('PosReportDebt')) 'Khách nào đang nợ nhiều nhất?',
      if (perm.canCreate('CashTransaction')) 'Tạo phiếu chi 350k tiền điện',
      if (perm.canCreate('CashTransaction')) 'Cách xem sổ quỹ hôm nay?',
    ]);
    if (hr) {
      final att = perm.canView('AttendanceReport') || perm.canView('Attendance');
      final approve = perm.canApprove('Leave') || perm.canApprove('AdvanceRequests') || perm.canApprove('Overtime');
      add('attendance', Icons.fingerprint_rounded, 'Chấm công & nghỉ phép', 'Đi trễ, đơn nghỉ, duyệt đơn', [
        if (att) 'Ai đi trễ nhiều nhất tháng này?',
        if (perm.canView('LeaveReport')) 'Tình hình nghỉ phép tháng này',
        if (approve) 'Có đơn nào đang chờ tôi duyệt?',
        'Hôm nay tôi chấm công chưa?',
        'Tôi còn bao nhiêu ngày phép?',
        'Cách xin nghỉ phép?',
      ]);
      add('payroll', Icons.payments_rounded, 'Lương & thưởng phạt', 'Quỹ lương, ứng lương, phiếu phạt', [
        if (perm.canView('Payslip')) 'Tổng quỹ lương tháng trước theo phòng ban',
        if (perm.canCreate('AdvanceRequests')) 'Ứng lương 2 triệu tiền viện phí',
        if (perm.canCreate('PenaltyTickets')) 'Phạt An 50k vì đi trễ hôm nay',
        if (perm.canCreate('PenaltyTickets')) 'Phạt tất cả ai đi trễ hôm nay theo nội quy',
        'Cách xem phiếu lương của tôi?',
      ]);
    }
    add('help', Icons.help_outline_rounded, 'Cách dùng trợ lý', 'Micro, xác nhận thao tác', [
      'Trợ lý làm thay tôi được những việc gì?',
      'Khi nhờ lập phiếu, trợ lý có tự lưu luôn không?',
      'Cách dùng micro để hỏi bằng giọng nói?',
    ]);
    return groups;
  }

  void _ask(String q) {
    if (_isSending) return;
    _inputCtrl.text = tr(q);
    _send();
  }

  /// Mở đầu gọn: lời chào + một nút; bấm → nhóm chức năng; chọn nhóm → câu gợi ý, bấm là hỏi.
  Widget _buildGuide() {
    if (!_guideOpen) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ActionChip(
          avatar: const Icon(Icons.auto_awesome, size: 16, color: SboxColors.violet),
          label: Text(tr('Trợ lý AI hỗ trợ được gì?'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          backgroundColor: Colors.white,
          side: BorderSide(color: SboxColors.violet.withValues(alpha: 0.35)),
          onPressed: () => setState(() => _guideOpen = true),
        ),
      );
    }

    final groups = _guideGroups();
    final group = groups.where((g) => g.id == _guideGroup).firstOrNull;
    if (group == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Text(tr('Chọn nhóm việc bạn cần:'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SboxColors.slate700)),
          ),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 520 ? 3 : 2;
            final w = (c.maxWidth - 8 * (cols - 1)) / cols;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final g in groups) SizedBox(width: w, child: _guideGroupCard(g)),
            ]);
          }),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () => setState(() => _guideGroup = null),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.arrow_back_rounded, size: 20, color: SboxColors.slate500),
                ),
                Icon(group.icon, size: 20, color: SboxColors.violet),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr(group.title), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                Text(tr('Nhóm khác'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              ]),
            ),
          ),
          const Divider(height: 1),
          for (final q in group.prompts)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(q.startsWith('Cách') ? Icons.menu_book_rounded : Icons.chat_bubble_outline_rounded,
                  size: 18, color: SboxColors.violet),
              title: Text(tr(q), style: const TextStyle(fontSize: 13.5)),
              trailing: const Icon(Icons.north_east_rounded, size: 16, color: SboxColors.slate400),
              onTap: _isSending ? null : () => _ask(q),
            ),
        ]),
      ),
    );
  }

  Widget _guideGroupCard(_GuideGroup g) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _guideGroup = g.id),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SboxColors.slate200),
            ),
            child: Row(children: [
              SboxIconTile(g.icon, size: 34, iconSize: 18, radius: 10),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(g.title),
                      maxLines: 2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2)),
                  const SizedBox(height: 2),
                  Text(tr(g.sub),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: SboxColors.slate500, height: 1.2)),
                ]),
              ),
            ]),
          ),
        ),
      );

  Widget _buildBubble(_ChatMsg m) {
    final isUser = m.role == 'user';
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      // Theo bề ngang khung chat (đã giới hạn trên web / máy tính bảng) — dòng quá dài khó đọc.
      constraints: BoxConstraints(
          maxWidth: (MediaQuery.of(context).size.width.clamp(0, _kMaxSheetWidth) as double) * (isUser ? 0.8 : 0.9)),
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
          RepaintBoundary(
            key: m.captureKey,
            child: ColoredBox(
              // Ảnh xuất không để nền trong suốt (chữ tối trên nền đen khi mở bằng trình xem ảnh).
              color: isUser ? PosTheme.kiotBlue : SboxColors.slate100,
              child: Padding(
                // Ảnh xuất có viền nhỏ, chữ không sát mép.
                padding: const EdgeInsets.all(2),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(
                    m.translate ? tr(m.content) : m.content,
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
                  for (final c in m.charts) ...[
                    const SizedBox(height: 10),
                    _chartCard(c),
                  ],
                ],
                ),
              ),
            ),
          ),
          if (m.exportId != null) ...[
            const SizedBox(height: 8),
            _exportButtons(m),
          ],
          if (m.retryText != null) ...[
            const SizedBox(height: 6),
            ActionChip(
              avatar: const Icon(Icons.refresh_rounded, size: 16, color: SboxColors.violet),
              label: Text(tr('Gửi lại'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.violet, fontWeight: FontWeight.w600)),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFDDD6FE)),
              onPressed: _isSending ? null : () => _retry(m),
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
                  .where((c) => AiAssistantPermissions.canCreate(c, perm) && !_sessionDoneCreates.contains(c))
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
          // SBOX POS iOS: trang hướng dẫn chung có đăng ký, chấm công, tải app nền tảng khác.
          if (m.guides.isNotEmpty && !SboxAppVariant.iosStoreApp) ...[
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

  static const _chartColors = [
    Color(0xFF7C3AED), (SboxColors.posApp ? SboxColors.brand600 : Color(0xFF2563EB)), (SboxColors.posApp ? SboxColors.brand600 : Color(0xFF059669)), Color(0xFFD97706),
    Color(0xFFDB2777), (SboxColors.posApp ? SboxColors.brand600 : Color(0xFF0891B2)), Color(0xFF65A30D), Color(0xFFDC2626),
  ];

  /// 1250000 → 1.250.000 (đầy đủ, trong chú thích chạm).
  static String _fmtNum(double v) {
    final s = v.round().abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    return v < 0 ? '-$s' : s;
  }

  /// 1250000 → 1,3tr (gọn, trên trục).
  static String _compactNum(double v) {
    final a = v.abs();
    String f(double x, double unit, String u) => '${(x / unit).toStringAsFixed(a >= unit * 10 ? 0 : 1)}$u';
    if (a >= 1e9) return f(v, 1e9, 'tỷ');
    if (a >= 1e6) return f(v, 1e6, 'tr');
    if (a >= 1e3) return f(v, 1e3, 'k');
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  static String _shortLabel(String s) => s.length <= 8 ? s : '${s.substring(0, 7)}…';

  /// Biểu đồ nhỏ trong câu trả lời (cột / đường / tròn) + nút mở báo cáo đầy đủ.
  Widget _chartCard(_AiChart c) {
    final values = c.values;
    final maxV = values.reduce(math.max);
    final minV = math.min(0.0, values.reduce(math.min));
    final top = maxV <= 0 ? 1.0 : maxV * 1.15;
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canOpen = c.openModule != null && perm.canView(c.openModule!);
    const axisStyle = TextStyle(fontSize: 9, color: SboxColors.slate500);
    final titles = FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          getTitlesWidget: (v, meta) =>
              v == meta.max ? const SizedBox.shrink() : Text(_compactNum(v), style: axisStyle),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 20,
          interval: 1,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= c.labels.length || v != i.toDouble()) return const SizedBox.shrink();
            // Nhiều điểm: chỉ hiện nhãn cách quãng cho khỏi chồng chữ.
            if (c.labels.length > 7 && i % 2 == 1) return const SizedBox.shrink();
            return Text(_shortLabel(c.labels[i]), style: axisStyle);
          },
        ),
      ),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
    final grid = FlGridData(show: true, drawVerticalLine: false, horizontalInterval: top / 4 > 0 ? top / 4 : null);
    const tipStyle = TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600);

    Widget chart;
    if (c.type == 'pie') {
      final total = values.fold<double>(0, (s, v) => s + (v > 0 ? v : 0));
      chart = Row(children: [
        SizedBox(
          width: 140,
          height: 140,
          child: PieChart(PieChartData(
            centerSpaceRadius: 26,
            sectionsSpace: 1,
            sections: [
              for (var i = 0; i < values.length; i++)
                if (values[i] > 0)
                  PieChartSectionData(
                    value: values[i],
                    color: _chartColors[i % _chartColors.length],
                    radius: 44,
                    title: total > 0 && values[i] / total >= 0.08 ? '${(values[i] / total * 100).round()}%' : '',
                    titleStyle: tipStyle,
                  ),
            ],
          )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(direction: Axis.vertical, spacing: 4, children: [
            for (var i = 0; i < values.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, color: _chartColors[i % _chartColors.length]),
                const SizedBox(width: 6),
                Text('${_shortLabel(c.labels[i])}: ${_compactNum(values[i])}',
                    style: const TextStyle(fontSize: 11, color: SboxColors.slate700)),
              ]),
          ]),
        ),
      ]);
    } else if (c.type == 'line') {
      chart = SizedBox(
        height: 170,
        child: LineChart(LineChartData(
          minY: minV,
          maxY: top,
          gridData: grid,
          borderData: FlBorderData(show: false),
          titlesData: titles,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem('${c.labels[s.x.toInt()]}\n${_fmtNum(s.y)}', tipStyle))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
              isCurved: true,
              preventCurveOverShooting: true,
              color: SboxColors.violet,
              barWidth: 3,
              dotData: FlDotData(show: values.length <= 12),
              belowBarData: BarAreaData(show: true, color: SboxColors.violet.withValues(alpha: 0.12)),
            ),
          ],
        )),
      );
    } else {
      chart = SizedBox(
        height: 170,
        child: BarChart(BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: minV,
          maxY: top,
          gridData: grid,
          borderData: FlBorderData(show: false),
          titlesData: titles,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (g, _, rod, __) => BarTooltipItem('${c.labels[g.x]}\n${_fmtNum(rod.toY)}', tipStyle),
            ),
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: values[i] == maxV ? SboxColors.violet : SboxColors.violet.withValues(alpha: 0.55),
                  width: values.length <= 6 ? 18 : 10,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ]),
          ],
        )),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SboxColors.slate200),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.insert_chart_outlined_rounded, size: 16, color: SboxColors.violet),
          const SizedBox(width: 6),
          Expanded(
            child: Text(c.title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
          ),
          if (canOpen)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () {
                Navigator.of(context).pop();
                NavigationNotifier.goToModule(c.openModule!);
              },
              child: Text(tr('Mở báo cáo')),
            ),
        ]),
        const SizedBox(height: 6),
        chart,
      ]),
    );
  }

  Widget _buildTypingBubble() {
    final live = _cleanLive(_liveText);
    if (live.isNotEmpty) {
      // Chữ đang chạy dần — con trỏ nhấp nháy ở cuối cho biết trợ lý còn đang viết.
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
              maxWidth: (MediaQuery.of(context).size.width.clamp(0, _kMaxSheetWidth) as double) * 0.9),
          decoration: BoxDecoration(
            color: SboxColors.slate100,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(14),
            ),
          ),
          child: Text('$live ▍', style: const TextStyle(color: SboxColors.slate900, fontSize: 14, height: 1.45)),
        ),
      );
    }
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
            Flexible(
              child: Text(tr(_liveStatus ?? 'Đang suy nghĩ...'),
                  style: TextStyle(color: SboxColors.slate500, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  /// [spokenSure] = người dùng đã nói «chắc chắn xác nhận» — thay cho hộp hỏi lại của thẻ rủi ro cao.
  Future<void> _confirmAction(_PendingAction a, {bool spokenSure = false}) async {
    // Xóa / hủy / duyệt hàng loạt: hỏi lại một lần nữa — không hoàn tác được.
    if (a.highRisk && !spokenSure) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: SboxColors.danger, size: 32),
          title: Text(tr(a.title)),
          content: Text(tr('Thao tác này không hoàn tác được. Bạn chắc chắn muốn thực hiện?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Đồng ý')),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }
    setState(() => a.state = 'running');
    final res = await _api.confirmAiAction(a.id, acknowledged: a.highRisk);
    if (!mounted) return;
    final ok = res['isSuccess'] == true;
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : const <String, dynamic>{};
    final undoSecs = (data['undoSeconds'] as num?)?.toInt() ?? 0;
    setState(() {
      a.state = ok ? 'done' : 'failed';
      a.result = ok
          ? (data['message']?.toString() ?? 'Đã lưu')
          // Mất kết nối: máy chủ có thể đã ghi xong. Bấm Thử lại không tạo trùng — máy chủ trả lại kết quả đã có.
          : res.containsKey('errorKind')
              ? tr('Mất kết nối, chưa rõ đã lưu chưa — bấm Thử lại để kiểm tra.')
              : (res['message']?.toString() ?? 'Không thực hiện được');
      a.undoUntil = ok && data['canUndo'] == true && undoSecs > 0
          ? DateTime.now().add(Duration(seconds: undoSecs))
          : null;
    });
    unawaited(_speakReply(ok ? a.result! : '${tr('Không lưu được')}: ${a.result}'));
  }

  // ── Lệnh giọng nói ngắn + rảnh tay ──

  /// Thẻ của câu trả lời mới nhất. Tin mới nhất không có thẻ → không có gì để điều khiển: «có» khi AI vừa hỏi «xem chi
  /// tiết không?» là trả lời AI, không được lưu thẻ cũ phía trên.
  List<_PendingAction> _latestCards() {
    for (final m in _messages.reversed) {
      if (m.role != 'assistant' || m.local || m.retryText != null) continue;
      return m.pending;
    }
    return const [];
  }

  static bool _isOpen(_PendingAction a) => a.state == 'pending' || a.state == 'failed';

  void _localReply(String said, String reply) {
    setState(() {
      _messages.add(_ChatMsg('user', said, local: true));
      _messages.add(_ChatMsg('assistant', reply, local: true));
      _inputCtrl.clear();
    });
    _scrollToBottom();
  }

  /// «Xác nhận» / «bỏ» / «hoàn tác» / «dừng» nói hoặc gõ khi có thẻ đang chờ → làm ngay, không gửi AI.
  /// true = đã xử lý.
  Future<bool> _handleVoiceCommand(String text) async {
    final cmd = AiVoiceCommand.parse(text);
    if (cmd == null) return false;
    switch (cmd.kind) {
      case AiVoiceCommandKind.confirm:
      case AiVoiceCommandKind.discard:
        final cards = _latestCards();
        final open = cards.where(_isOpen).toList();
        if (open.isEmpty) return false;
        // Số thẻ theo đúng thứ tự trên màn hình — thẻ 1 đã xong thì «thẻ hai» vẫn là thẻ thứ hai.
        final i = cmd.index;
        if (i != null && (i > cards.length || !_isOpen(cards[i - 1]))) {
          final msg = i > cards.length ? tr('Chỉ có ${cards.length} phiếu.') : tr('Phiếu số $i đã xử lý rồi.');
          _localReply(text, msg);
          unawaited(_speakReply(msg));
          return true;
        }
        final targets = i == null ? open : [cards[i - 1]];
        if (cmd.kind == AiVoiceCommandKind.discard) {
          for (final a in targets) {
            unawaited(_api.discardAiAction(a.id));
            a.state = 'discarded';
          }
          final msg = targets.length == 1 ? tr('Đã bỏ phiếu.') : tr('Đã bỏ ${targets.length} phiếu.');
          _localReply(text, msg);
          unawaited(_speakReply(msg));
          return true;
        }
        final risky = targets.where((a) => a.highRisk && !cmd.sure).toList();
        if (risky.length == targets.length) {
          final msg = tr('Phiếu xóa / hủy không hoàn tác được — nói «chắc chắn xác nhận» hoặc bấm nút trên thẻ.');
          _localReply(text, msg);
          unawaited(_speakReply(msg));
          return true;
        }
        _localReply(
            text,
            risky.isEmpty
                ? tr('Đang lưu…')
                : tr('Phiếu xóa / hủy không hoàn tác được — nói «chắc chắn xác nhận» hoặc bấm nút trên thẻ.'));
        for (final a in targets.where((a) => !risky.contains(a))) {
          await _confirmAction(a, spokenSure: cmd.sure);
          if (!mounted) return true;
        }
        return true;
      case AiVoiceCommandKind.undo:
        _PendingAction? last;
        for (final m in _messages.reversed) {
          last = m.pending.where((a) => a.canUndo).lastOrNull;
          if (last != null) break;
        }
        if (last == null) return false;
        _localReply(text, tr('Đang hoàn tác…'));
        await _undoAction(last);
        if (mounted) {
          unawaited(_speakReply(last.state == 'undone' ? last.result ?? tr('Đã hoàn tác') : tr('Chưa hoàn tác được.')));
        }
        return true;
      case AiVoiceCommandKind.repeat:
        for (final m in _messages.reversed) {
          if (m.role != 'assistant' || m.local || m.retryText != null) continue;
          _localReply(text, tr('Đọc lại câu trả lời vừa rồi.'));
          unawaited(_speakReply(_speechWithCards(m.content, m.pending.where(_isOpen).toList())));
          return true;
        }
        return false;
      case AiVoiceCommandKind.stop:
        if (!_handsFree) return false;
        await _setHandsFree(false);
        _localReply(text, tr('Đã tắt chế độ rảnh tay.'));
        return true;
    }
  }

  Future<void> _setHandsFree(bool on) async {
    setState(() {
      _handsFree = on;
      if (on) _ttsEnabled = true;
    });
    await _saveVoicePrefs();
    if (on) {
      unawaited(_speakReply(tr('Đã bật rảnh tay. Bạn cứ nói, tôi nghe.')));
      return;
    }
    await _stopSpeaking();
    if (_recording) {
      _recording = false;
      _recTimer?.cancel();
      try {
        await _recorder.stop();
      } catch (_) {}
      await _recSub?.cancel();
      _recSub = null;
      _recBuf.clear();
      if (mounted) setState(() {});
    }
    if (_isListening) {
      await _stt.cancel();
      if (mounted) setState(() => _isListening = false);
    }
  }

  /// Rảnh tay: đọc xong (hoặc không đọc) → tự bật micro nghe câu tiếp theo. Không nói gì → micro tự tắt, hết vòng.
  void _afterSpeech() {
    if (!_handsFree) return;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || !_handsFree || _isSending || _recording || _isListening || _transcribing || _ttsSpeaking) return;
      if (!kIsWeb && !_consentGiven) return;
      unawaited(_toggleListening());
    });
  }

  Future<void> _undoAction(_PendingAction a) async {
    setState(() => a.state = 'undoing');
    final res = await _api.undoAiAction(a.id);
    if (!mounted) return;
    final ok = res['isSuccess'] == true;
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : const <String, dynamic>{};
    setState(() {
      if (ok) {
        a.state = 'undone';
        a.result = data['message']?.toString() ?? 'Đã hoàn tác';
      } else {
        a.state = 'done';
        // Lỗi mạng: máy chủ chưa từ chối, còn hạn thì giữ nút để bấm lại.
        if (!res.containsKey('errorKind')) a.undoUntil = null;
        NotificationOverlayManager().showError(
            title: 'Không hoàn tác được', message: res['message']?.toString() ?? 'Thử lại trên màn chứng từ.');
      }
    });
  }

  Widget _actionCard(_PendingAction a) {
    final (Color baseTone, IconData baseIcon) = switch (a.kind) {
      'penalty' || 'update_penalty' => (SboxColors.danger, Icons.gavel_rounded),
      'reward' || 'update_reward' => (SboxColors.success, Icons.emoji_events_outlined),
      'advance' => (const Color(0xFFB45309), Icons.payments_outlined),
      'cash' || 'update_cash' => (const Color(0xFF0369A1), Icons.account_balance_wallet_outlined),
      'sale' => (PosTheme.kiotBlue, Icons.receipt_long_outlined),
      'overtime' => (SboxColors.violet, Icons.more_time_rounded),
      'product' => (PosTheme.kiotBlue, Icons.inventory_2_outlined),
      'purchase_receipt' => ((SboxColors.posApp ? SboxColors.brand600 : Color(0xFF0F766E)), Icons.move_to_inbox_outlined),
      'stock_count' => (const Color(0xFF0369A1), Icons.fact_check_outlined),
      'damage_issue' => (SboxColors.danger, Icons.delete_sweep_outlined),
      'internal_use' => (const Color(0xFFB45309), Icons.outbox_outlined),
      'customer_return' || 'purchase_return' => (const Color(0xFFC2410C), Icons.assignment_return_outlined),
      'voucher' => (SboxColors.violet, Icons.confirmation_number_outlined),
      'promotion' => (const Color(0xFFDB2777), Icons.local_offer_outlined),
      'review_approve' => (SboxColors.success, Icons.task_alt_rounded),
      'review_reject' => (const Color(0xFFB45309), Icons.block_rounded),
      'update_product' || 'update_customer' || 'update_supplier' => (PosTheme.kiotBlue, Icons.edit_note_rounded),
      'deactivate_customer' || 'deactivate_supplier' => (SboxColors.slate500, Icons.person_off_outlined),
      'assign_shift' => (const Color(0xFF0369A1), Icons.calendar_month_outlined),
      'shift_swap_request' || 'shift_swap' => (const Color(0xFF0369A1), Icons.swap_horiz_rounded),
      'stock_transfer' => ((SboxColors.posApp ? SboxColors.brand600 : Color(0xFF0F766E)), Icons.local_shipping_outlined),
      'collect_debt' => (SboxColors.success, Icons.request_quote_outlined),
      'announcement' => (SboxColors.violet, Icons.campaign_outlined),
      'task' => (PosTheme.kiotBlue, Icons.assignment_turned_in_outlined),
      'close_cashier_shift' => (const Color(0xFFB45309), Icons.point_of_sale_outlined),
      'penalty_batch' => (SboxColors.danger, Icons.gavel_rounded),
      'leave' => (const Color(0xFF0369A1), Icons.beach_access_outlined),
      'quote' => (PosTheme.kiotBlue, Icons.request_page_outlined),
      'reservation' => ((SboxColors.posApp ? SboxColors.brand600 : Color(0xFF0F766E)), Icons.event_seat_outlined),
      'employee' => (SboxColors.violet, Icons.person_add_alt_1_outlined),
      _ => (SboxColors.violet, Icons.fact_check_outlined),
    };
    // Rủi ro cao (xóa / hủy / duyệt hàng loạt): thẻ đỏ.
    final tone = a.highRisk ? SboxColors.danger : baseTone;
    final icon = a.highRisk && (a.kind.startsWith('delete') || a.kind.startsWith('cancel'))
        ? Icons.delete_forever_outlined
        : baseIcon;
    return Container(
      decoration: BoxDecoration(
        color: a.highRisk ? const Color(0xFFFFF5F5) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: a.highRisk ? 0.6 : 0.35)),
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
            Text(tr(a.highRisk ? 'Rủi ro cao' : 'Chờ xác nhận'),
                style: TextStyle(
                    fontSize: 11,
                    color: a.highRisk ? SboxColors.danger : SboxColors.slate500,
                    fontWeight: a.highRisk ? FontWeight.w700 : FontWeight.normal)),
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
          'running' || 'undoing' => Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text(tr(a.state == 'undoing' ? 'Đang hoàn tác…' : 'Đang lưu…'), style: const TextStyle(fontSize: 12)),
            ]),
          'undone' => Row(children: [
              const Icon(Icons.undo_rounded, size: 18, color: SboxColors.slate500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr(a.result ?? 'Đã hoàn tác'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SboxColors.slate500)),
              ),
            ]),
          'done' => Row(children: [
              const Icon(Icons.check_circle, size: 18, color: SboxColors.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr(a.result ?? 'Đã lưu'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SboxColors.success)),
              ),
              if (a.canUndo)
                TextButton.icon(
                  onPressed: () => _undoAction(a),
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: Text(tr('Hoàn tác')),
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
                    icon: Icon(a.highRisk ? Icons.warning_amber_rounded : Icons.check, size: 18),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_attachments.isNotEmpty) _buildAttachmentChips(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: tr('Gửi ảnh / file đơn hàng'),
                  onPressed: _isSending || _preparingAttachment ? null : _pickAttachments,
                  icon: _preparingAttachment
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.attach_file_rounded, color: SboxColors.violet),
                ),
                IconButton(
                  tooltip: tr(_isListening || _recording ? 'Dừng & gửi' : 'Nói'),
                  onPressed: _transcribing || (_isSending && !_recording && !_isListening) ? null : _toggleListening,
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
                      hintText: tr(_attachments.isNotEmpty
                          ? 'Ghi chú thêm (VD: "nhập hàng", "chỉ dịch") rồi bấm gửi'
                          : _recording
                          ? 'Đang nghe ${_recSecs}s — nói xong bấm ■ để gửi'
                          : _transcribing
                              ? 'Đang chép lời…'
                              : _isListening
                                  ? 'Đang nghe...'
                                  : _handsFree
                                      ? 'Rảnh tay: nói lệnh — «xác nhận» để lưu, «dừng» để tắt'
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

/// Bề ngang tối đa khung chat — web / máy tính bảng không kéo dài bong bóng hết màn hình.
const double _kMaxSheetWidth = 760;

Future<void> showAiAssistant(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: _kMaxSheetWidth),
    builder: (_) => const AiAssistantSheet(),
  );
}
