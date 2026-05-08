import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import '../screens/main_layout.dart';
import 'notification_overlay.dart';

class _ChatMsg {
  final String role; // 'user' | 'assistant'
  final String content;
  final List<String> actions;
  final List<String> creates;
  _ChatMsg(this.role, this.content, {this.actions = const [], this.creates = const []});
}

class AiAssistantSheet extends StatefulWidget {
  const AiAssistantSheet({super.key});

  @override
  State<AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends State<AiAssistantSheet> {
  final _api = ApiService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _stt = stt.SpeechToText();
  final _tts = FlutterTts();

  final List<_ChatMsg> _messages = [];
  bool _isSending = false;
  bool _sttReady = false;
  bool _isListening = false;
  bool _ttsEnabled = true;
  bool _ttsSpeaking = false;
  String _partialTranscript = '';

  @override
  void initState() {
    super.initState();
    _initTts();
    _initStt();
    _messages.add(_ChatMsg('assistant',
        'Xin chào! Tôi là trợ lý ảo HRM của bạn. Bạn có thể hỏi về phép, chấm công, lương, hoặc nhờ tôi hướng dẫn đăng ký nghỉ / đổi ca / báo quên chấm công. Bấm micro để nói hoặc gõ tin nhắn.'));
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('vi-VN');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
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
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _tts.stop();
    if (_isListening) _stt.stop();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (!_sttReady) {
      NotificationOverlayManager().showWarning(
          title: 'Micro chưa sẵn sàng',
          message: 'Vui lòng cấp quyền micro và thử lại');
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
        setState(() {
          _messages.add(_ChatMsg('assistant', reply, actions: actions, creates: creates));
        });
        _scrollToBottom();
        if (_ttsEnabled && reply.isNotEmpty) {
          await _tts.stop();
          await _tts.speak(reply);
        }
      } else {
        final msg = (result['message'] as String?) ?? 'Lỗi trợ lý AI';
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
    // Close sheet first so navigation target becomes visible
    Navigator.of(context).pop();
    switch (action) {
      case 'nav_leave':
      case 'nav_leave_create':
        NavigationNotifier.goToLeaves();
        break;
      case 'nav_work_schedule':
      case 'nav_shift_change':
        NavigationNotifier.goToWorkSchedule();
        break;
      case 'nav_attendance_correction':
      case 'nav_attendance_correction_create':
        NavigationNotifier.goToAttendanceCorrections();
        break;
      case 'nav_attendance_history':
      case 'nav_attendance':
        NavigationNotifier.goToAttendance();
        break;
      case 'nav_payroll':
      case 'nav_payslip':
        NavigationNotifier.goToPayroll();
        break;
      case 'nav_feedback':
      case 'nav_feedback_create':
        NavigationNotifier.goTo(NavigationNotifier.feedback);
        break;
      case 'nav_communication':
        NavigationNotifier.goToCommunication();
        break;
      case 'nav_advance':
      case 'nav_advance_create':
        NavigationNotifier.goToAdvanceRequests();
        break;
      case 'nav_overtime':
      case 'nav_overtime_create':
        // Overtime is a tab inside attendance approval flow; route to attendance for now
        NavigationNotifier.goTo(NavigationNotifier.attendanceApproval);
        break;
      case 'nav_field_checkin':
      case 'nav_field_checkin_create':
        NavigationNotifier.goTo(NavigationNotifier.fieldCheckIn);
        break;
      case 'nav_meal':
      case 'nav_meal_register':
        NavigationNotifier.goTo(NavigationNotifier.meals);
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
      default:
        NotificationOverlayManager()
            .showInfo(title: 'Thao tác', message: action);
    }
  }

  /// Handle [[CREATE:...]] — parse params and call API directly
  Future<void> _handleCreate(String createTag) async {
    if (_isSending) return;
    try {
      // Parse: "attendance_correction,date=2026-05-07,time=13:00,action=add,reason=quên chấm công"
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
          reasonAccum = '$reasonAccum,$p'; // comma was in reason text
        }
      }
      if (reasonAccum != null) params['reason'] = reasonAccum;

      if (type == 'attendance_correction') {
        final date = params['date'];
        final time = params['time'];
        final reason = params['reason'] ?? 'Quên chấm công';
        final actionStr = params['action'] ?? 'add';
        // CorrectionAction: edit=0, add=1, delete=2
        final actionInt = actionStr == 'edit' ? 0 : actionStr == 'delete' ? 2 : 1;

        if (date == null || time == null) {
          setState(() {
            _messages.add(_ChatMsg('assistant', '⚠️ Thiếu ngày hoặc giờ để tạo phiếu.'));
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
            await _tts.stop();
            await _tts.speak('Đã tạo yêu cầu sửa giờ thành công. Đang chờ duyệt.');
          }
        } else {
          final msg = (result['message'] as String?) ?? 'Lỗi không xác định';
          setState(() {
            _messages.add(_ChatMsg('assistant', '❌ Không tạo được phiếu: $msg'));
          });
        }
      } else {
        setState(() {
          _messages.add(_ChatMsg('assistant', '⚠️ Loại phiếu "$type" chưa được hỗ trợ tạo trực tiếp.'));
        });
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
      // Extract time and date from tag for clearer label
      final params = <String, String>{};
      for (final p in tag.split(',').skip(1)) {
        final idx = p.indexOf('=');
        if (idx > 0) params[p.substring(0, idx).trim()] = p.substring(idx + 1).trim();
      }
      final time = params['time'] ?? '';
      final date = params['date'] != null ? _formatDate(params['date']!) : '';
      return '✅ Xác nhận tạo phiếu sửa giờ${date.isNotEmpty ? " $date" : ""}${time.isNotEmpty ? " lúc $time" : ""}';
    }
    return '✅ Xác nhận tạo';
  }

  (String, IconData) _actionLabelIcon(String action) {
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
        return ('Phiếu thưởng', Icons.workspace_premium_rounded);
      case 'nav_employees':
        return ('Nhân viên', Icons.people_rounded);
      case 'nav_departments':
        return ('Phòng ban', Icons.account_tree_rounded);
      case 'nav_dashboard':
        return ('Tổng quan', Icons.dashboard_rounded);
      default:
        return (action, Icons.open_in_new);
    }
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
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6)),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trợ lý ảo HRM',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text('Hỗ trợ nghỉ phép, lịch làm, chấm công, lương',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            tooltip: _ttsEnabled ? 'Tắt đọc' : 'Bật đọc',
            onPressed: () async {
              if (_ttsEnabled && _ttsSpeaking) await _tts.stop();
              setState(() => _ttsEnabled = !_ttsEnabled);
            },
            icon: Icon(_ttsEnabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded),
          ),
          IconButton(
            tooltip: 'Đóng',
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
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length + (_isSending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _messages.length) return _buildTypingBubble();
        return _buildBubble(_messages[i]);
      },
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
        color: isUser ? const Color(0xFF1E3A5F) : const Color(0xFFF3F4F6),
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
            m.content,
            style: TextStyle(
              color: isUser ? Colors.white : const Color(0xFF18181B),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          if (m.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: m.actions.map((a) {
                final li = _actionLabelIcon(a);
                return ActionChip(
                  avatar: Icon(li.$2, size: 16, color: const Color(0xFF8B5CF6)),
                  label: Text(li.$1,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8B5CF6),
                          fontWeight: FontWeight.w600)),
                  backgroundColor: const Color(0xFFF3E8FF),
                  side: const BorderSide(color: Color(0xFFDDD6FE)),
                  onPressed: () => _handleAction(a),
                );
              }).toList(),
            ),
          ],
          if (m.creates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: m.creates.map((c) {
                final label = _createLabel(c);
                return ActionChip(
                  avatar: const Icon(Icons.check_circle_outline_rounded,
                      size: 16, color: Color(0xFF059669)),
                  label: Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF059669),
                          fontWeight: FontWeight.w600)),
                  backgroundColor: const Color(0xFFECFDF5),
                  side: const BorderSide(color: Color(0xFF6EE7B7)),
                  onPressed: _isSending ? null : () => _handleCreate(c),
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
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Đang suy nghĩ...',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: _isListening ? 'Dừng ghi âm' : 'Nói',
              onPressed: _toggleListening,
              icon: Icon(
                _isListening ? Icons.mic : Icons.mic_none_rounded,
                color: _isListening ? Colors.red : const Color(0xFF8B5CF6),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: _isListening
                      ? 'Đang nghe...'
                      : 'Hỏi trợ lý (VD: "Còn bao nhiêu phép?")',
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
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
                  _isSending ? Colors.grey.shade300 : const Color(0xFF8B5CF6),
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

Future<void> showAiAssistant(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AiAssistantSheet(),
  );
}
