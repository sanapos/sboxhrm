import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'ai_chat_stream.dart';

/// Web: XMLHttpRequest báo tiến trình (onprogress) — đọc phần chữ mới mỗi lần; package:http trên web chờ đủ phản hồi.
Stream<String> postTextStream(Uri uri, Map<String, String> headers, String body) {
  final ctrl = StreamController<String>();
  final xhr = web.XMLHttpRequest();
  var seen = 0;
  void pump() {
    final t = xhr.responseText;
    if (t.length > seen) {
      ctrl.add(t.substring(seen));
      seen = t.length;
    }
  }

  xhr.open('POST', uri.toString());
  // Không tear-off được member interop (dart2js báo lỗi) → gọi qua lambda.
  headers.forEach((k, v) => xhr.setRequestHeader(k, v));
  xhr.onprogress = ((web.Event _) => pump()).toJS;
  xhr.onload = ((web.Event _) {
    if (xhr.status != 200) {
      ctrl.addError(AiStreamHttpException(xhr.status));
    } else {
      pump();
    }
    ctrl.close();
  }).toJS;
  xhr.onerror = ((web.Event _) {
    ctrl.addError(AiStreamHttpException(0));
    ctrl.close();
  }).toJS;
  ctrl.onCancel = () {
    if (xhr.readyState != 4) xhr.abort();
  };
  xhr.send(body.toJS);
  return ctrl.stream;
}
