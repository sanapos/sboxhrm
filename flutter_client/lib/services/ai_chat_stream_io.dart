import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_chat_stream.dart';

/// Điện thoại / máy tính: đọc thân phản hồi theo từng đoạn ngay khi máy chủ gửi.
Stream<String> postTextStream(Uri uri, Map<String, String> headers, String body) async* {
  final client = http.Client();
  try {
    final req = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = body;
    final res = await client.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw AiStreamHttpException(res.statusCode);
    // Không giới hạn tổng thời gian: trợ lý có thể gọi nhiều báo cáo; mỗi đoạn chờ tối đa 90 giây.
    yield* res.stream.transform(utf8.decoder).timeout(const Duration(seconds: 90));
  } finally {
    client.close();
  }
}
