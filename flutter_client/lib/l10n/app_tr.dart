import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'app_locale.dart';
import 'en_ui_map.g.dart';

/// Phrases long enough to be unambiguous UI copy (never a person/place name).
const int _kPhraseMinLen = 10;

/// Letters (incl. Vietnamese) — used to keep replacements on word boundaries so a
/// fragment is never substituted inside a longer word. Digits are deliberately not
/// word characters here: no Vietnamese word contains one, so a digit next to a
/// fragment is a real boundary. That matters because an interpolation often abuts
/// a word, as in 'chấm công$punch', which renders as "chấm công08:00".
final RegExp _wordChar = RegExp(r'\p{L}', unicode: true);

/// Any letter carrying a Vietnamese diacritic, plus đ/Đ.
final RegExp _vietnameseLetter = RegExp(
    r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ'
    r'ÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]');

/// The đồng currency symbol ("1.000đ", "500 đ") stays as-is in every language.
final RegExp _dongSymbol =
    RegExp(r'(?<!\p{L})đ(?!\p{L})', unicode: true, caseSensitive: false);

final RegExp _hole = RegExp(r'\{(\d+)\}');

/// A source sentence built by interpolation, e.g. 'Đã xóa {0} nhân viên'.
/// Matched against the runtime string so the target can reorder the values.
class _Template {
  _Template(String vi, this.target)
      : anchor = vi
            .split(_hole)
            .fold('', (a, b) => b.length > a.length ? b : a),
        staticLength = vi.replaceAll(_hole, '').length,
        re = RegExp(
          '^${vi.split(_hole).map(RegExp.escape).join('(.+?)')}\$',
          dotAll: true,
        ),
        _order = _hole.allMatches(vi).map((m) => int.parse(m[1]!)).toList();

  final String anchor;
  final int staticLength;
  final RegExp re;
  final String target;
  final List<int> _order;

  String? apply(String s, String Function(String) value) {
    if (!s.contains(anchor)) return null;
    final m = re.firstMatch(s);
    if (m == null) return null;
    final values = <int, String>{};
    for (var g = 0; g < _order.length; g++) {
      values[_order[g]] = value(m[g + 1]!);
    }
    return target.replaceAllMapped(
        _hole, (h) => values[int.parse(h[1]!)] ?? h[0]!);
  }
}

/// Vietnamese → one target language.
class _LangPack {
  _LangPack(this.map, this.templates, {this.fallback});

  final Map<String, String> map;
  final List<_Template> templates;

  /// Consulted when this pack has no answer (ko/ja/zh fall back to English,
  /// which reads better than Vietnamese to those users).
  final _LangPack? fallback;

  List<MapEntry<String, String>>? _phrases;
  List<MapEntry<String, String>>? _fragments;

  List<MapEntry<String, String>> get _longPhrases {
    return _phrases ??= (map.entries
        .where((e) => e.key.length >= _kPhraseMinLen)
        .toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length)));
  }

  /// Every Vietnamese entry usable as a fragment inside a dynamic string, longest
  /// first. Keys must carry a diacritic so ASCII terms (PIN, OK, ID) are left be,
  /// and values must be free of Vietnamese so a substitution always makes progress.
  List<MapEntry<String, String>> get _fragmentEntries {
    return _fragments ??= (map.entries
        .where((e) =>
            e.key.length >= 2 &&
            _vietnameseLetter.hasMatch(e.key) &&
            !_vietnameseLetter.hasMatch(e.value))
        .toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length)));
  }

  String? lookup(String s) => map[s] ?? fallback?.lookup(s);

  /// Translation of [s], or null when this pack (and its fallback) know nothing.
  String? translate(String s) => _translate(s) ?? fallback?.translate(s);

  String? _translate(String s) {
    final direct = map[s];
    if (direct != null) return direct;

    final trimmed = s.trim();
    if (trimmed != s) {
      final t = map[trimmed];
      if (t != null) return s.replaceFirst(trimmed, t);
    }

    for (final suffix in const [':', '...', '…', '.', '!', '?', ' *', '*']) {
      if (trimmed.endsWith(suffix)) {
        final core =
            trimmed.substring(0, trimmed.length - suffix.length).trimRight();
        final t = map[core];
        if (t != null) return '$t$suffix';
      }
    }

    // ALL-CAPS labels ('MÃ CỬA HÀNG') reuse the sentence-case entry.
    if (trimmed.length > 1 &&
        trimmed == trimmed.toUpperCase() &&
        trimmed != trimmed.toLowerCase()) {
      final lower = trimmed.toLowerCase();
      final t = map['${lower[0].toUpperCase()}${lower.substring(1)}'] ??
          map[lower];
      if (t != null) return s.replaceFirst(trimmed, t.toUpperCase());
    }

    // Interpolated source sentences ('Đã xóa $n nhân viên'): whole-sentence
    // templates keep the target's word order; the values pass through unchanged
    // unless they are themselves known UI strings.
    if (templates.isNotEmpty && _vietnameseLetter.hasMatch(s)) {
      for (final t in templates) {
        final out = t.apply(s, (v) => lookup(v) ?? v);
        if (out == null) continue;
        // A short template ('{0} ngày {1}') can swallow a whole sentence into
        // its values; keep the match only when nothing Vietnamese leaks through,
        // or when the template's own text is most of the sentence (the values are
        // then data such as names).
        if (!_vietnameseLetter.hasMatch(out.replaceAll(_dongSymbol, '')) ||
            t.staticLength * 2 >= s.length) {
          return out;
        }
      }
    }

    // Runtime strings built by interpolation ("$count nhân viên"): substitute the
    // Vietnamese fragments around the values, on word boundaries. Tried before the
    // partial paths below because it only ever returns a fully translated result.
    // Every fragment key carries a diacritic, so plain ASCII text can skip the scan.
    if (_vietnameseLetter.hasMatch(s)) {
      final byFragment = _replaceFragments(s);
      if (byFragment != null) return byFragment;
    }

    // "Label: dynamic value" — translate the label part only.
    final colon = trimmed.indexOf(': ');
    if (colon > 1) {
      final t = map[trimmed.substring(0, colon)];
      if (t != null) return '$t${trimmed.substring(colon)}';
    }

    // Segmented labels such as "A • B" or "A - B".
    for (final sep in const [' • ', ' | ', ' - ', ' / ']) {
      if (trimmed.contains(sep)) {
        final parts = trimmed.split(sep);
        var hit = false;
        final out = parts.map((p) {
          final t = map[p.trim()];
          if (t != null) hit = true;
          return t ?? p;
        }).join(sep);
        if (hit) return out;
      }
    }

    // Last resort: replace long, unambiguous phrases inside a dynamic sentence.
    if (s.length < _kPhraseMinLen) return null;
    var result = s;
    var changed = false;
    for (final e in _longPhrases) {
      if (result.contains(e.key)) {
        result = result.replaceAll(e.key, e.value);
        changed = true;
      }
    }
    return changed ? result : null;
  }

  /// Substitute known Vietnamese UI fragments, longest first, only where both
  /// edges of the match fall on a word boundary.
  ///
  /// All-or-nothing on purpose: a half-translated sentence reads worse than the
  /// original, so the result is kept only when no Vietnamese word survives.
  /// Returns null when nothing hit or the result is still mixed.
  String? _replaceFragments(String s) {
    var out = s;
    var changed = false;
    for (final pair in _fragmentEntries) {
      final vi = pair.key;
      if (vi.length > out.length) continue;
      var i = out.indexOf(vi);
      while (i >= 0) {
        final end = i + vi.length;
        final beforeOk = i == 0 || !_wordChar.hasMatch(out[i - 1]);
        final afterOk = end >= out.length || !_wordChar.hasMatch(out[end]);
        if (beforeOk && afterOk) {
          out = out.replaceRange(i, end, pair.value);
          changed = true;
          i = out.indexOf(vi, i + pair.value.length);
        } else {
          i = out.indexOf(vi, i + 1);
        }
      }
    }
    if (!changed) return null;
    final probe = out.replaceAll(_dongSymbol, '');
    return _vietnameseLetter.hasMatch(probe) ? null : out;
  }
}

final Map<String, _LangPack> _packs = <String, _LangPack>{};
_LangPack? _active;
final Map<String, String> _cache = <String, String>{};

/// `assets/l10n/<code>.json`: {"m": {vi: text}, "t": [[viTemplate, template], …]}.
Future<(Map<String, String>, List<_Template>)> _readAsset(String code) async {
  try {
    final raw = await rootBundle.loadString('assets/l10n/$code.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final map = (data['m'] as Map<String, dynamic>? ?? const {})
        .map((k, v) => MapEntry(k, v as String));
    final templates = <_Template>[
      for (final t in (data['t'] as List<dynamic>? ?? const []))
        _Template((t as List<dynamic>)[0] as String, t[1] as String),
    // Most specific first: the template with the most fixed text wins.
    ]..sort((a, b) => b.staticLength.compareTo(a.staticLength));
    return (map, templates);
  } catch (e) {
    debugPrint('l10n: cannot load $code pack: $e');
    return (<String, String>{}, <_Template>[]);
  }
}

Future<_LangPack> _pack(String code) async {
  final have = _packs[code];
  if (have != null) return have;
  final (map, templates) = await _readAsset(code);
  final _LangPack pack;
  if (code == 'en') {
    // Entries "translated" to themselves are untranslated leftovers; dropping them
    // lets the other paths (ALL-CAPS, fragments, templates) try.
    final base = <String, String>{...kEnUiMap}..removeWhere((k, v) => k == v);
    pack = _LangPack({...base, ...map}, templates);
  } else {
    pack = _LangPack(map, templates, fallback: await _pack('en'));
  }
  return _packs[code] = pack;
}

/// Switch the UI language used by [tr]: loads its pack (once), then applies it.
Future<void> trUseLanguage(String code) async {
  AppLocale.setLanguageCode(code);
  final lang = AppLocale.languageCode;
  final pack = lang == 'vi' ? null : await _pack(lang);
  // A newer switch may have finished while this one was loading.
  if (AppLocale.languageCode != lang) return;
  _active = pack;
  _cache.clear();
}

/// Translate a Vietnamese UI string into the selected app language.
///
/// Keep Vietnamese literals in source (primary UI language). Call [tr] only for
/// **display** text — never for API/status comparisons or storage keys.
String tr(String vietnamese) {
  final pack = _active;
  if (pack == null || vietnamese.isEmpty) return vietnamese;
  final cached = _cache[vietnamese];
  if (cached != null) return cached;
  final out = pack.translate(vietnamese) ?? vietnamese;
  if (_cache.length < 20000) _cache[vietnamese] = out;
  return out;
}

/// Null-preserving [tr] for optional labels (hintText, errorText, ...).
String? trN(String? vietnamese) =>
    vietnamese == null ? null : tr(vietnamese);

/// Translate if [vietnamese] looks like UI copy; otherwise return as-is.
String trOr(String? vietnamese, [String fallback = '']) {
  final s = vietnamese ?? fallback;
  return tr(s);
}

/// Clear memoized translations (call when the UI language changes).
void trResetCache() => _cache.clear();
