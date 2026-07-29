import 'app_locale.dart';
import 'en_ui_map.g.dart';

/// Phrases long enough to be unambiguous UI copy (never a person/place name).
const int _kPhraseMinLen = 10;

List<MapEntry<String, String>>? _phrases;
List<MapEntry<String, String>>? _fragments;
final Map<String, String> _cache = <String, String>{};

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

/// The đồng currency symbol ("1.000đ", "500 đ") stays as-is in English.
final RegExp _dongSymbol =
    RegExp(r'(?<!\p{L})đ(?!\p{L})', unicode: true, caseSensitive: false);

List<MapEntry<String, String>> get _longPhrases {
  return _phrases ??= (kEnUiMap.entries
      .where((e) => e.key.length >= _kPhraseMinLen)
      .toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length)));
}

/// Every Vietnamese entry usable as a fragment inside a dynamic string, longest
/// first. Keys must carry a diacritic so ASCII terms (PIN, OK, ID) are left be,
/// and values must be fully English so a substitution always makes progress.
List<MapEntry<String, String>> get _fragmentEntries {
  return _fragments ??= (kEnUiMap.entries
      .where((e) =>
          e.key.length >= 2 &&
          _vietnameseLetter.hasMatch(e.key) &&
          !_vietnameseLetter.hasMatch(e.value))
      .toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length)));
}

/// Translate a Vietnamese UI string when app language is English.
///
/// Keep Vietnamese literals in source (primary UI language). Call [tr] only for
/// **display** text — never for API/status comparisons or storage keys.
String tr(String vietnamese) {
  if (!AppLocale.isEnglish || vietnamese.isEmpty) return vietnamese;
  final cached = _cache[vietnamese];
  if (cached != null) return cached;
  final out = _translate(vietnamese);
  if (_cache.length < 20000) _cache[vietnamese] = out;
  return out;
}

String _translate(String s) {
  final direct = kEnUiMap[s];
  if (direct != null) return direct;

  final trimmed = s.trim();
  if (trimmed != s) {
    final t = kEnUiMap[trimmed];
    if (t != null) return s.replaceFirst(trimmed, t);
  }

  for (final suffix in const [':', '...', '…', '.', '!', '?', ' *', '*']) {
    if (trimmed.endsWith(suffix)) {
      final core =
          trimmed.substring(0, trimmed.length - suffix.length).trimRight();
      final t = kEnUiMap[core];
      if (t != null) return '$t$suffix';
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
    final t = kEnUiMap[trimmed.substring(0, colon)];
    if (t != null) return '$t${trimmed.substring(colon)}';
  }

  // Segmented labels such as "A • B" or "A - B".
  for (final sep in const [' • ', ' | ', ' - ', ' / ']) {
    if (trimmed.contains(sep)) {
      final parts = trimmed.split(sep);
      var hit = false;
      final out = parts.map((p) {
        final t = kEnUiMap[p.trim()];
        if (t != null) hit = true;
        return t ?? p;
      }).join(sep);
      if (hit) return out;
    }
  }

  // Last resort: replace long, unambiguous phrases inside a dynamic sentence.
  if (s.length < _kPhraseMinLen) return s;
  var result = s;
  var changed = false;
  for (final e in _longPhrases) {
    if (result.contains(e.key)) {
      result = result.replaceAll(e.key, e.value);
      changed = true;
    }
  }
  return changed ? result : s;
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
