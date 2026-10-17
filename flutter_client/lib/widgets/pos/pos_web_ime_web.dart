import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Chiều cao bàn phím ảo của trình duyệt (CSS px = logical px của Flutter).
/// Chrome / Edge (Windows cảm ứng, Android) và Safari iOS vẽ bàn phím ĐÈ lên trang mà không báo viewInsets
/// cho Flutter → ô nhập ở nửa dưới (ghi chú, tiền khách đưa, tìm khách…) bị che. Giá trị này cho
/// [PosKeyboardLift] biết để dịch giao diện lên.
final ValueNotifier<double> posWebKeyboardInset = ValueNotifier<double>(0);

var _kbWatching = false;

/// Bắt đầu theo dõi bàn phím ảo: Virtual Keyboard API (Chromium) → visualViewport (Safari iOS, trình duyệt khác).
void posStartWebKeyboardWatch() {
  if (_kbWatching) return;
  _kbWatching = true;
  try {
    // Móc kiểm thử / hỗ trợ: window.__sboxKb(px) đặt chiều cao bàn phím giả lập.
    globalContext['__sboxKb'] = ((JSNumber h) {
      posWebKeyboardInset.value = h.toDartDouble;
    }).toJS;
  } catch (_) {}

  var vkOk = false;
  try {
    final nav = web.window.navigator as JSObject;
    final vk = nav['virtualKeyboard'];
    if (vk != null && vk.isDefinedAndNotNull) {
      final o = vk as JSObject;
      o['overlaysContent'] = true.toJS; // bàn phím đè lên trang, không co layout → tự dịch giao diện
      o.callMethod(
        'addEventListener'.toJS,
        'geometrychange'.toJS,
        ((JSAny _) {
          try {
            final r = o['boundingRect'] as JSObject;
            posWebKeyboardInset.value = (r['height'] as JSNumber).toDartDouble;
          } catch (_) {}
        }).toJS,
      );
      vkOk = true;
    }
  } catch (_) {}

  if (!vkOk) {
    try {
      final vv = web.window.visualViewport;
      if (vv != null) {
        void update(web.Event _) {
          final hidden = web.window.innerHeight - vv.height - vv.offsetTop;
          // Ngưỡng 80px: bỏ qua thanh địa chỉ co giãn của trình duyệt di động.
          posWebKeyboardInset.value = hidden > 80 ? hidden : 0;
        }

        vv.addEventListener('resize', update.toJS);
        vv.addEventListener('scroll', update.toJS);
      }
    } catch (_) {}
  }
}

const _trapId = 'sbox-pos-ime-trap';

bool posWebHasTouchPoints() {
  try {
    return web.window.navigator.maxTouchPoints > 0;
  } catch (_) {
    return false;
  }
}

void _focusNoScroll(web.HTMLElement el) {
  try {
    el.focus(web.FocusOptions(preventScroll: true));
  } catch (_) {
    el.focus();
  }
}

void _styleImeTrap(web.HTMLTextAreaElement el) {
  final s = el.style;
  // Ô 1×16 góc trên — không đặt full-width đáy (Chrome sẽ scroll cả trang lên OSK).
  s.position = 'fixed';
  s.left = '0';
  s.top = '0';
  s.width = '1px';
  s.height = '16px';
  s.opacity = '0.01';
  s.border = '0';
  s.padding = '0';
  s.margin = '0';
  s.fontSize = '16px';
  s.zIndex = '2147483646';
  s.setProperty('caret-color', 'transparent');
  s.setProperty('pointer-events', 'none');
}

web.HTMLTextAreaElement _ensureImeTrap() {
  final existing = web.document.getElementById(_trapId);
  if (existing != null) {
    final el = existing as web.HTMLTextAreaElement;
    _styleImeTrap(el);
    return el;
  }
  final el = web.document.createElement('textarea') as web.HTMLTextAreaElement;
  el.id = _trapId;
  el.setAttribute('autocomplete', 'off');
  el.setAttribute('autocorrect', 'off');
  el.setAttribute('autocapitalize', 'none');
  el.setAttribute('spellcheck', 'false');
  el.setAttribute('inputmode', 'text');
  el.setAttribute('aria-hidden', 'true');
  _styleImeTrap(el);
  web.document.body?.appendChild(el);
  return el;
}

web.HTMLElement? _flutterEditing() {
  final doc = web.document;
  final el = doc.querySelector('textarea.flt-text-editing') ??
      doc.querySelector('input.flt-text-editing') ??
      doc.querySelector('.flt-text-editing');
  return el is web.HTMLElement ? el : null;
}

void _revealForOsk(web.HTMLElement el) {
  final s = el.style;
  s.opacity = '0.01';
  s.fontSize = '16px';
  s.setProperty('pointer-events', 'auto');
}

/// Gọi đồng bộ trong pointerdown — Chrome/Safari chỉ mở OSK nếu focus input còn trong cử chỉ.
void posArmWebImeForGesture() {
  try {
    _focusNoScroll(_ensureImeTrap());
    _followFlutterEditing();
  } catch (_) {}
}

void posFocusWebEditingElement() {
  try {
    final flutterEl = _flutterEditing();
    if (flutterEl != null) {
      _revealForOsk(flutterEl);
      _focusNoScroll(flutterEl);
      return;
    }
    _focusNoScroll(_ensureImeTrap());
    _followFlutterEditing();
  } catch (_) {}
}

var _followArmed = false;

void _followFlutterEditing() {
  if (_followArmed) return;
  _followArmed = true;
  var n = 0;
  Timer.periodic(const Duration(milliseconds: 16), (t) {
    n++;
    try {
      final el = _flutterEditing();
      if (el != null) {
        _revealForOsk(el);
        _focusNoScroll(el);
        t.cancel();
        _followArmed = false;
        return;
      }
    } catch (_) {}
    if (n >= 24) {
      t.cancel();
      _followArmed = false;
    }
  });
}
