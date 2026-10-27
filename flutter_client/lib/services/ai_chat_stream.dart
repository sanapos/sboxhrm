import 'dart:async';
import 'dart:convert';

import 'ai_chat_stream_io.dart' if (dart.library.html) 'ai_chat_stream_web.dart' as impl;
import 'api_service.dart';

/// Một sự kiện từ /api/ai/assistant/chat/stream: `status` (đang xem báo cáo…), `delta` (đoạn chữ mới),
/// `reset` (bỏ chữ tạm), `done` (phản hồi cuối — giống hệt /chat: `{status, body}`).
class AiStreamEvent {
  AiStreamEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  String get text => (data['text'] ?? '').toString();
}

/// Lỗi HTTP khi mở luồng (máy chủ cũ chưa có /chat/stream → 404, mất mạng → 0) — nơi gọi chuyển sang /chat thường.
class AiStreamHttpException implements Exception {
  AiStreamHttpException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'AI stream HTTP $statusCode';
}

/// Trợ lý trả lời dần: gửi [body] như /chat, nhận các sự kiện Server-Sent Events.
/// Điện thoại đọc luồng HTTP; web đọc dần qua XMLHttpRequest (fetch của package:http trên web gom cả phản hồi).
Stream<AiStreamEvent> aiChatStream(Map<String, dynamic> body) async* {
  final api = ApiService();
  final headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
    ...?api.imageAuthHeaders,
  };
  final branch = ApiService.currentBranchId;
  if (branch != null && branch.isNotEmpty) headers['X-Branch-Id'] = branch;
  final uri = Uri.parse('${ApiService.baseUrl}/api/ai/assistant/chat/stream');

  var buffer = '';
  await for (final chunk in impl.postTextStream(uri, headers, jsonEncode(body))) {
    buffer += chunk.replaceAll('\r\n', '\n');
    while (true) {
      final end = buffer.indexOf('\n\n');
      if (end < 0) break;
      final block = buffer.substring(0, end);
      buffer = buffer.substring(end + 2);
      final ev = _parseBlock(block);
      if (ev != null) yield ev;
    }
  }
  final tail = _parseBlock(buffer.trim());
  if (tail != null) yield tail;
}

AiStreamEvent? _parseBlock(String block) {
  if (block.trim().isEmpty) return null;
  var type = 'message';
  final data = StringBuffer();
  for (final line in block.split('\n')) {
    if (line.startsWith('event:')) {
      type = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (data.isNotEmpty) data.write('\n');
      data.write(line.substring(5).trimLeft());
    }
  }
  if (data.isEmpty) return null;
  try {
    final d = jsonDecode(data.toString());
    return AiStreamEvent(type, d is Map<String, dynamic> ? d : {'value': d});
  } catch (_) {
    return null;
  }
}
