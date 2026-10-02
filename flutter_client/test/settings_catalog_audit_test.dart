import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/settings_hub_catalog.dart';

/// Rà soát Thiết lập SBOX: không mục nào trùng (số, mã, tên), không mục nào thiếu màn hình,
/// không còn tên gọi cũ trên giao diện.
void main() {
  final items = SettingsHubCatalog.allItems;

  test('Không trùng số, mã, tên mục', () {
    String dup(Iterable<Object> xs) {
      final seen = <Object>{};
      return xs.where((x) => !seen.add(x)).join(', ');
    }

    expect(dup(items.map((i) => i.index)), isEmpty, reason: 'trùng số');
    expect(dup(items.map((i) => i.code)), isEmpty, reason: 'trùng mã');
    expect(dup(items.map((i) => i.label.toLowerCase())), isEmpty, reason: 'trùng tên');
  });

  test('Mỗi mục thuộc một nhóm có thật, nhóm nào cũng có mục', () {
    final groups = SettingsHubCatalog.groups.map((g) => g.title).toSet();
    for (final i in items) {
      expect(groups, contains(i.groupTitle), reason: i.label);
    }
    for (final g in groups) {
      expect(items.any((i) => i.groupTitle == g), isTrue, reason: 'nhóm rỗng: $g');
    }
  });

  test('Mã cũ trỏ tới mục có thật; tra mã chữ ra đúng mục', () {
    SettingsHubCatalog.legacyIndex.forEach((old, now) {
      expect(SettingsHubCatalog.byIndex(old)?.index, now, reason: 'mã cũ $old');
    });
    for (final i in items) {
      expect(SettingsHubCatalog.byCode(i.code)?.index, i.index);
    }
    expect(SettingsHubCatalog.byIndex(29)?.label, 'Máy in'); // «Máy in cloud» cũ → mục Máy in
  });

  test('Mục nào cũng có màn hình; không còn nhánh mở mục đã bỏ', () {
    final src = File('lib/screens/settings_hub_screen.dart').readAsStringSync();
    final cases = RegExp(r'case (\d+):').allMatches(src).map((m) => int.parse(m.group(1)!)).toSet();
    for (final i in items) {
      expect(cases, contains(i.index), reason: 'thiếu màn hình: ${i.label}');
    }
    final known = {...items.map((i) => i.index), ...SettingsHubCatalog.legacyIndex.keys};
    expect(cases.difference(known), isEmpty, reason: 'nhánh thừa không có mục');
  });

  test('Không còn mục vận hành / trùng trong Thiết lập', () {
    final labels = items.map((i) => i.label).toSet();
    for (final gone in ['Máy in cloud', 'Lịch sử hủy / trả', 'Màn hình bếp (KDS)', 'Khách hàng POS', 'Thiết lập lương', 'Ngành hàng & bán hàng']) {
      expect(labels, isNot(contains(gone)), reason: gone);
    }
    // Ba mục «Tài khoản» khác nghĩa phải có tên phân biệt.
    expect(labels.where((l) => l == 'Tài khoản'), isEmpty);
  });

  test('Không còn tên gọi cũ trên giao diện', () {
    final bad = RegExp(r"'[^'\n]*(Thiết lập Sbox|Thiết lập POS|Thiết lập cửa hàng)[^'\n]*'");
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('${Platform.pathSeparator}l10n${Platform.pathSeparator}')) continue;
      final lines = f.readAsLinesSync();
      for (var n = 0; n < lines.length; n++) {
        final l = lines[n].trimLeft();
        if (l.startsWith('//')) continue;
        if (bad.hasMatch(l)) hits.add('${f.path}:${n + 1}');
      }
    }
    expect(hits, isEmpty);
  });
}
