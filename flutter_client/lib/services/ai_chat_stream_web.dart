import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'ai_chat_stream.dart';

/// Web: XMLHttpRequest báo tiến trình (onprogress) — đọc phần chữ mới mỗi lần; package:http trên web chỉ trả khi xong.
/// Không nhận thêm dữ liệu trong 90 giây (như bản điện thoại) → báo lỗi, không để vòng quay chạy mãi.
Stream<String> postTextStream(Uri uri, Map<String, String> headers, String body) {
  const idleLimit = Duration(seconds: 90);
  final ctrl = StreamController<String>();
  final xhr = web.XMLHttpRequest();
  var seen = 0;
  Timer? idle;
  void finish([Object? error]) {
    idle?.cancel();
    if (ctrl.isClosed) return;
    if (error != null) ctrl.addError(error);
    ctrl.close();
  }

  void armIdle() {
    idle?.cancel();
    idle = Timer(idleLimit, () {
      finish(AiStreamHttpException(0));
      xhr.abort();
    });
  }

  void pump() {
    armIdle();
    if (ctrl.isClosed) return;
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
      finish(AiStreamHttpException(xhr.status));
    } else {
      pump();
      finish();
    }
  }).toJS;
  xhr.onerror = ((web.Event _) {
    finish(AiStreamHttpException(0));
  }).toJS;
  ctrl.onCancel = () {
    idle?.cancel();
    if (xhr.readyState != 4) xhr.abort();
  };
  armIdle();
  xhr.send(body.toJS);
  return ctrl.stream;
}
