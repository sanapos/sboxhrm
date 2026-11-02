import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/ai_voice_commands.dart';
import '../../utils/store_role_helper.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';

/// Trợ lý ảo trên app POS (máy bán hàng): hỏi số liệu, ra lệnh bằng chữ hoặc giọng nói — cùng máy chủ với app SBOX:
/// trợ lý dựng thẻ, bấm / nói «xác nhận» mới ghi. Bản gọn cho máy Android 6: ghi âm → Gemini chép lời,
/// đọc trả lời bằng giọng Gemini (không cần nhận dạng / đọc của Google trên máy).
bool canUsePosAiAssistant(BuildContext context) {
  final user = Provider.of<AuthProvider>(context, listen: false).user;
  if (user == null) return false;
  if (StoreRoleHelper.bypassesPackageFilter(user.role)) return true;
  return (user.allowedModules ?? const <String>[]).any((m) => m.toLowerCase() == 'aiassistant');
}

Future<void> showPosAiAssistant(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => const PosAiAssistantSheet(),
    );

class _Card {
  _Card.fromJson(Map<String, dynamic> j)
      : id = (j['id'] ?? '').toString(),
        title = (j['title'] ?? 'Phiếu').toString(),
        lines = ((j['lines'] as List?) ?? [])
            .whereType<Map>()
            .map((l) => ((l['label'] ?? '').toString(), (l['value'] ?? '').toString()))
            .toList(),
        warnings = ((j['warnings'] as List?) ?? []).map((e) => e.toString()).toList(),
        highRisk = j['risk']?.toString() == 'high';

  final String id;
  final String title;
  final List<(String, String)> lines;
  final List<String> warnings;
  final bool highRisk;

  /// pending | running | done | failed | discarded | undoing | undone
  String state = 'pending';
  String? result;
  DateTime? undoUntil;

  bool get open => state == 'pending' || state == 'failed';
  bool get canUndo => state == 'done' && undoUntil != null && DateTime.now().isBefore(undoUntil!);
}

class _Msg {
  _Msg(this.role, this.text, {this.cards = const [], this.local = false});
  final String role;
  final String text;
  final List<_Card> cards;

  /// Lệnh ngắn xử lý trên máy («xác nhận», «bỏ») — không gửi lên AI.
  final bool local;
}

/// Giữ cuộc trò chuyện trong phiên (đóng / mở lại không mất thẻ đang chờ).
final List<_Msg> _session = [];

class PosAiAssistantSheet extends StatefulWidget {
  const PosAiAssistantSheet({super.key});

  static void resetSession() => _session.clear();

  @override
  State<PosAiAssistantSheet> createState() => _PosAiAssistantSheetState();
}

class _PosAiAssistantSheetState extends State<PosAiAssistantSheet> {
  static const _kConsentKey = 'ai_assistant_consent_v1';
  static const _kSpeakKey = 'pos_ai_speak_v1';
  static const _kHandsFreeKey = 'pos_ai_hands_free_v1';

  final _api = ApiService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  bool _sending = false;
  bool _consent = false;
  bool _speak = true;
  bool _handsFree = false;
  bool _speaking = false;
  bool _voiceUnavailable = false;

  // Ghi âm PCM 16 kHz → WAV → Gemini chép lời. Nói xong im ~1,8 giây là tự gửi.
  StreamSubscription<Uint8List>? _recSub;
  final _recBuf = BytesBuilder(copy: false);
  Timer? _recTimer;
  int _recSecs = 0;
  bool _recording = false;
  bool _transcribing = false;
  DateTime? _recStart;
  DateTime? _lastLoud;
  bool _heard = false;
  double? _noise;

  String get _lang => AppLocale.languageCode;

  static const _suggestions = [
    'Doanh thu hôm nay',
    'Món nào bán chạy tuần này?',
    'Hàng nào sắp hết?',
    'Chốt ca, két có 2 triệu',
    'Đặt bàn 5 tối nay 7 giờ cho anh Nam, 4 người',
  ];

  @override
  void initState() {
    super.initState();
    if (_session.isEmpty) _addWelcome();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _speaking = false);
      _afterSpeech();
    });
    _loadPrefs();
    _toBottom();
  }

  void _addWelcome() => _session.add(_Msg('assistant',
      tr('Xin chào! Hỏi tôi doanh thu, tồn kho, công nợ… hoặc ra lệnh: bán hàng, nhập kho, chốt ca, đặt bàn, báo giá. '
          'Tôi dựng phiếu sẵn — bạn bấm hoặc nói «xác nhận» mới lưu. Bấm micro để nói.'),
      local: true));

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final consent = p.getBool(_kConsentKey) ?? false;
      if (!mounted) return;
      setState(() {
        _consent = consent;
        _speak = p.getBool(_kSpeakKey) ?? true;
        _handsFree = p.getBool(_kHandsFreeKey) ?? false;
      });
      if (!consent) WidgetsBinding.instance.addPostFrameCallback((_) => _askConsent());
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kSpeakKey, _speak);
      await p.setBool(_kHandsFreeKey, _handsFree);
    } catch (_) {}
  }

  Future<void> _askConsent() async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Trợ lý ảo – Thông tin quyền riêng tư')),
        content: SingleChildScrollView(
          child: Text(tr('Khi sử dụng trợ lý AI, nội dung câu hỏi và dữ liệu cửa hàng liên quan sẽ được gửi đến máy chủ '
              'của chúng tôi và xử lý bằng Google Gemini AI để tạo phản hồi. Khi bạn nói bằng micro, đoạn ghi âm cũng được '
              'gửi để chép thành chữ (không lưu lại sau khi chép).\n\nBạn đồng ý để tiếp tục sử dụng tính năng này không?')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không đồng ý'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Đồng ý'))),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) {
      Navigator.of(context).pop();
      return;
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kConsentKey, true);
    } catch (_) {}
    if (mounted) setState(() => _consent = true);
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _recSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  // ── Gửi câu hỏi ──

  Future<void> _send([String? preset]) async {
    if (!_consent) {
      await _askConsent();
      if (!_consent) return;
    }
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    if (await _handleCommand(text)) return;
    setState(() {
      _session.add(_Msg('user', text));
      _input.clear();
      _sending = true;
    });
    _toBottom();
    try {
      final history = _session
          .where((m) => !m.local && m.text.trim().isNotEmpty)
          .map((m) => {'role': m.role, 'content': m.text})
          .toList();
      final res = await _api.aiAssistantChat(messages: history.length > 14 ? history.sublist(history.length - 14) : history,
          language: _lang);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : const <String, dynamic>{};
        final reply = _plain((data['reply'] ?? '').toString());
        final cards = ((data['pendingActions'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => _Card.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        setState(() => _session.add(_Msg('assistant', reply, cards: cards)));
        unawaited(_say(reply));
      } else {
        setState(() => _session.add(_Msg('assistant', '⚠️ ${tr((res['message'] ?? 'Lỗi trợ lý ảo').toString())}', local: true)));
      }
    } catch (e) {
      if (mounted) setState(() => _session.add(_Msg('assistant', '⚠️ ${tr('Lỗi')}: $e', local: true)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _toBottom();
    }
  }

  /// Bỏ dấu Markdown (máy chủ đã lọc thẻ [[…]]).
  static String _plain(String s) => s
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAllMapped(RegExp(r'(^|\n)\s*#+\s*'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'(^|\n)(\s*)[*-]\s+'), (m) => '${m[1]}${m[2]}• ')
      .trim();

  // ── Lệnh ngắn: xác nhận / bỏ / hoàn tác / dừng ──

  List<_Card> _openCards() {
    for (final m in _session.reversed) {
      if (m.role == 'assistant' && m.cards.isNotEmpty) return m.cards.where((c) => c.open).toList();
    }
    return const [];
  }

  void _local(String said, String reply) {
    setState(() {
      _session.add(_Msg('user', said, local: true));
      _session.add(_Msg('assistant', reply, local: true));
      _input.clear();
    });
    _toBottom();
  }

  Future<bool> _handleCommand(String text) async {
    final cmd = AiVoiceCommand.parse(text);
    if (cmd == null) return false;
    switch (cmd.kind) {
      case AiVoiceCommandKind.confirm:
      case AiVoiceCommandKind.discard:
        final open = _openCards();
        if (open.isEmpty) return false;
        final i = cmd.index;
        if (i != null && i > open.length) {
          final msg = tr('Chỉ có ${open.length} phiếu đang chờ.');
          _local(text, msg);
          unawaited(_say(msg));
          return true;
        }
        final targets = i == null ? open : [open[i - 1]];
        if (cmd.kind == AiVoiceCommandKind.discard) {
          for (final c in targets) {
            unawaited(_api.discardAiAction(c.id));
            c.state = 'discarded';
          }
          final msg = targets.length == 1 ? tr('Đã bỏ phiếu.') : tr('Đã bỏ ${targets.length} phiếu.');
          _local(text, msg);
          unawaited(_say(msg));
          return true;
        }
        final risky = targets.where((c) => c.highRisk && !cmd.sure).toList();
        final riskMsg = tr('Phiếu xóa / hủy không hoàn tác được — nói «chắc chắn xác nhận» hoặc bấm nút trên thẻ.');
        _local(text, risky.isEmpty ? tr('Đang lưu…') : riskMsg);
        if (risky.length == targets.length) {
          unawaited(_say(riskMsg));
          return true;
        }
        for (final c in targets.where((c) => !risky.contains(c))) {
          await _confirm(c, spokenSure: cmd.sure);
          if (!mounted) return true;
        }
        return true;
      case AiVoiceCommandKind.undo:
        _Card? last;
        for (final m in _session.reversed) {
          final hit = m.cards.where((c) => c.canUndo);
          if (hit.isNotEmpty) {
            last = hit.last;
            break;
          }
        }
        if (last == null) return false;
        _local(text, tr('Đang hoàn tác…'));
        await _undo(last);
        return true;
      case AiVoiceCommandKind.stop:
        if (!_handsFree) return false;
        await _setHandsFree(false);
        _local(text, tr('Đã tắt chế độ rảnh tay.'));
        return true;
    }
  }

  Future<void> _confirm(_Card c, {bool spokenSure = false}) async {
    if (c.highRisk && !spokenSure) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(c.title)),
          content: Text(tr('Thao tác này không hoàn tác được. Bạn chắc chắn muốn thực hiện?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Đồng ý')),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }
    setState(() => c.state = 'running');
    final res = await _api.confirmAiAction(c.id, acknowledged: c.highRisk);
    if (!mounted) return;
    final ok = res['isSuccess'] == true;
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : const <String, dynamic>{};
    final undoSecs = (data['undoSeconds'] as num?)?.toInt() ?? 0;
    setState(() {
      c.state = ok ? 'done' : 'failed';
      c.result = ok ? (data['message']?.toString() ?? 'Đã lưu') : (res['message']?.toString() ?? 'Không thực hiện được');
      c.undoUntil = ok && data['canUndo'] == true && undoSecs > 0 ? DateTime.now().add(Duration(seconds: undoSecs)) : null;
    });
    unawaited(_say(ok ? c.result! : '${tr('Không lưu được')}: ${c.result}'));
  }

  Future<void> _undo(_Card c) async {
    setState(() => c.state = 'undoing');
    final res = await _api.undoAiAction(c.id);
    if (!mounted) return;
    final ok = res['isSuccess'] == true;
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : const <String, dynamic>{};
    setState(() {
      if (ok) {
        c.state = 'undone';
        c.result = data['message']?.toString() ?? 'Đã hoàn tác';
      } else {
        c.state = 'done';
        c.undoUntil = null;
      }
    });
    unawaited(_say(ok ? c.result! : '${tr('Không hoàn tác được')}: ${res['message'] ?? ''}'));
  }

  // ── Đọc to (giọng Gemini) + rảnh tay ──

  Future<void> _say(String text) async {
    if (!_speak || _voiceUnavailable || text.trim().isEmpty) {
      _afterSpeech();
      return;
    }
    var t = text.replaceAll(RegExp(r'[•⚠️✅❌]'), ' ').trim();
    if (t.length > 700) t = '${t.substring(0, 700)}…';
    final res = await _api.aiSpeakEx(t, language: _lang);
    if (res.status == 409) _voiceUnavailable = true;
    if (!mounted || !_speak) return;
    final wav = res.audio;
    if (wav == null) {
      _afterSpeech();
      return;
    }
    try {
      await _player.stop();
      setState(() => _speaking = true);
      await _player.play(BytesSource(wav));
    } catch (_) {
      if (mounted) setState(() => _speaking = false);
      _afterSpeech();
    }
  }

  Future<void> _stopSpeaking() async {
    try {
      await _player.stop();
    } catch (_) {}
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _setHandsFree(bool on) async {
    setState(() {
      _handsFree = on;
      if (on) _speak = true;
    });
    await _savePrefs();
    if (on) {
      unawaited(_say(tr('Đã bật rảnh tay. Bạn cứ nói, tôi nghe.')));
    } else {
      await _stopSpeaking();
      await _cancelRecording();
    }
  }

  void _afterSpeech() {
    if (!_handsFree) return;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || !_handsFree || !_consent || _sending || _recording || _transcribing || _speaking) return;
      unawaited(_startRecording());
    });
  }

  // ── Ghi âm ──

  Future<void> _toggleMic() async {
    if (_transcribing) return;
    if (!_consent) {
      await _askConsent();
      if (!_consent) return;
    }
    if (_speaking) await _stopSpeaking();
    if (_recording) {
      await _stopAndTranscribe();
      return;
    }
    if (!await _startRecording()) {
      NotificationOverlayManager().showWarning(
          title: tr('Micro chưa sẵn sàng'), message: tr('Vui lòng cấp quyền micro cho ứng dụng và thử lại'));
    }
  }

  Future<bool> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) return false;
      _recBuf.clear();
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      _recStart = DateTime.now();
      _heard = false;
      _lastLoud = null;
      _noise = null;
      _recSub = stream.listen((chunk) {
        _recBuf.add(chunk);
        _onChunk(chunk);
      });
      _recSecs = 0;
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recSecs++);
        if (_recSecs >= 60) _stopAndTranscribe();
        // Rảnh tay mà 8 giây không nói gì → tắt micro (hết vòng, không ghi mãi).
        if (_recSecs >= 8 && !_heard) _cancelRecording();
      });
      setState(() => _recording = true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recording) return;
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

  void _onChunk(Uint8List chunk) {
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
    if (now.difference(_recStart ?? now) < const Duration(milliseconds: 500)) {
      _noise = _noise == null ? rms : (_noise! * 0.7 + rms * 0.3);
      return;
    }
    if (rms >= math.max(450.0, (_noise ?? 0) * 2.5)) {
      _heard = true;
      _lastLoud = now;
    } else if (_heard && _lastLoud != null && now.difference(_lastLoud!) >= const Duration(milliseconds: 1800)) {
      _stopAndTranscribe();
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

  Future<void> _stopAndTranscribe() async {
    if (!_recording) return;
    _recording = false;
    _recTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    await _recSub?.cancel();
    _recSub = null;
    final pcm = _recBuf.takeBytes();
    if (!mounted) return;
    if (pcm.length < 16000 * 2 * 0.4 || !_heard) {
      setState(() {});
      return;
    }
    setState(() => _transcribing = true);
    final res = await _api.aiTranscribeEx(_wav(pcm, 16000), 'audio/wav', language: _lang);
    if (!mounted) return;
    setState(() => _transcribing = false);
    final text = res.text?.trim();
    if (text == null) {
      NotificationOverlayManager().showWarning(
        title: tr(res.status == 409 ? 'Cửa hàng chưa bật AI' : 'AI đang bận'),
        message: tr(res.status == 409
            ? 'Nhờ chủ cửa hàng thêm khóa ở Thiết lập SBOX › Trợ lý AI, hoặc gõ câu hỏi.'
            : 'Chưa chép được lời — bấm micro nói lại sau vài giây.'),
      );
      return;
    }
    if (text.isEmpty) {
      NotificationOverlayManager().showWarning(title: tr('Chưa nghe rõ'), message: tr('Bạn nói lại gần micro hơn nhé.'));
      return;
    }
    _input.text = text;
    await _send();
  }

  // ── Giao diện ──

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: h * 0.9,
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(children: [
          _header(),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: _session.length + (_sending ? 1 : 0),
              itemBuilder: (_, i) => i == _session.length ? _thinking() : _bubble(_session[i]),
            ),
          ),
          if (_session.length <= 1) _suggestionRow(),
          _inputBar(),
        ]),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
        child: Row(children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr('Trợ lý ảo'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            tooltip: tr('Cuộc trò chuyện mới'),
            onPressed: _sending
                ? null
                : () {
                    _stopSpeaking();
                    setState(() {
                      _session.clear();
                      _addWelcome();
                    });
                  },
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: tr(_speak ? 'Tắt đọc' : 'Bật đọc'),
            onPressed: () async {
              if (_speak) await _stopSpeaking();
              setState(() => _speak = !_speak);
              await _savePrefs();
            },
            icon: Icon(_speak ? Icons.volume_up_rounded : Icons.volume_off_rounded),
          ),
          IconButton(
            tooltip: tr('Rảnh tay (tự nghe sau khi đọc)'),
            onPressed: () => _setHandsFree(!_handsFree),
            icon: Icon(Icons.record_voice_over_rounded, color: _handsFree ? const Color(0xFF7C3AED) : null),
          ),
          IconButton(
            tooltip: tr('Đóng'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ]),
      );

  Widget _thinking() => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(tr('Đang suy nghĩ…'), style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          ]),
        ),
      );

  Widget _bubble(_Msg m) {
    final me = m.role == 'user';
    return Column(crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: me ? PosTheme.kiotBlue : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: me ? null : Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: SelectableText(m.text,
            style: TextStyle(fontSize: 14, height: 1.35, color: me ? Colors.white : const Color(0xFF0F172A))),
      ),
      for (var i = 0; i < m.cards.length; i++)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: _card(m.cards[i], m.cards.length > 1 ? i + 1 : null)),
    ]);
  }

  Widget _card(_Card c, int? no) {
    final tone = c.highRisk ? Colors.red.shade600 : PosTheme.kiotBlue;
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.highRisk ? const Color(0xFFFFF5F5) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withOpacity(0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${no != null ? '$no. ' : ''}${tr(c.title)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: tone)),
        const SizedBox(height: 6),
        for (final (label, value) in c.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 104, child: Text(tr(label), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
              Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            ]),
          ),
        for (final w in c.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('⚠ $w', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
          ),
        const SizedBox(height: 8),
        switch (c.state) {
          'running' || 'undoing' => Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text(tr(c.state == 'undoing' ? 'Đang hoàn tác…' : 'Đang lưu…')),
            ]),
          'done' => Row(children: [
              const Icon(Icons.check_circle, size: 18, color: Color(0xFF16A34A)),
              const SizedBox(width: 6),
              Expanded(child: Text(tr(c.result ?? 'Đã lưu'), style: const TextStyle(color: Color(0xFF16A34A)))),
              if (c.canUndo) TextButton(onPressed: () => _undo(c), child: Text(tr('Hoàn tác'))),
            ]),
          'undone' => Text(tr(c.result ?? 'Đã hoàn tác'), style: const TextStyle(color: Color(0xFF64748B))),
          'discarded' => Text(tr('Đã bỏ phiếu này'), style: const TextStyle(color: Color(0xFF64748B))),
          _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (c.state == 'failed')
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('❌ ${c.result ?? ''}', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                ),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: tone),
                    onPressed: () => _confirm(c),
                    icon: Icon(c.highRisk ? Icons.warning_amber_rounded : Icons.check, size: 18),
                    label: Text(tr(c.state == 'failed' ? 'Thử lại' : 'Xác nhận')),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    unawaited(_api.discardAiAction(c.id));
                    setState(() => c.state = 'discarded');
                  },
                  child: Text(tr('Bỏ')),
                ),
              ]),
            ]),
        },
      ]),
    );
  }

  Widget _suggestionRow() => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          children: [
            for (final s in _suggestions)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(label: Text(tr(s)), onPressed: _sending ? null : () => _send(tr(s))),
              ),
          ],
        ),
      );

  Widget _inputBar() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              tooltip: tr(_recording ? 'Dừng & gửi' : 'Nói'),
              onPressed: _transcribing ? null : _toggleMic,
              icon: _transcribing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_recording ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                      color: _recording ? Colors.red : const Color(0xFF7C3AED)),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: tr(_recording
                      ? 'Đang nghe ${_recSecs}s — nói xong bấm ■ để gửi'
                      : _transcribing
                          ? 'Đang chép lời…'
                          : _handsFree
                              ? 'Rảnh tay: nói lệnh — «xác nhận» để lưu, «dừng» để tắt'
                              : 'Hỏi hoặc ra lệnh (VD: "Phạt An 50k đi trễ")'),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ]),
        ),
      );
}
