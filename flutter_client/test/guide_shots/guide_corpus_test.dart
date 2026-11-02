import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/landing_guide_groups.dart';
import 'package:zkteco_flutter_client/utils/landing_industry_guide.dart';
import 'package:zkteco_flutter_client/utils/landing_usage_guide.dart';

/// Một nguồn cho cả trợ lý AI và trang guide.html: toàn bộ hướng dẫn (khu → nhóm → bước)
/// xuất ra src/ZKTecoADMS.Api/Services/HelpCorpus/landing-guide.json (nhúng vào API, đọc bởi
/// AiAssistantHelpCorpus; scripts/guide_html_build.py dựng guide.html từ file này).
/// Sửa hướng dẫn mà quên xuất lại → test đỏ.
/// Xuất lại: GUIDE_CORPUS_UPDATE=1 flutter test test/guide_shots/guide_corpus_test.dart
const corpusPath = '../src/ZKTecoADMS.Api/Services/HelpCorpus/landing-guide.json';

final _allSteps = [
  ...LandingUsageGuide.basicSteps,
  ...LandingUsageGuide.advancedSteps,
  ...LandingUsageGuide.posSteps,
  ...landingIndustrySteps,
];

String buildGuideCorpusJson() {
  final data = LandingGuideData.defaults;
  final steps = <Map<String, Object?>>[];
  for (final area in LandingGuideGroups.areas) {
    for (final e in LandingGuideGroups.entries(data, area)) {
      final s = e.step;
      steps.add({
        'mode': e.section,
        'area': area.id,
        'group': e.group.id,
        'stepId': s.id,
        'title': s.title,
        'desc': s.desc,
        'bullets': s.bullets,
        'tip': s.tip,
        'keywords': s.keywords,
        'shots': [
          for (final shot in s.shots) {'name': shot.name, 'afterBullet': shot.afterBullet, 'caption': shot.caption},
        ],
      });
    }
  }
  final doc = {
    'areas': [
      for (final a in LandingGuideGroups.areas)
        {
          'id': a.id,
          'title': a.title,
          'subtitle': a.subtitle,
          'groups': [
            for (final g in a.groups) {'id': g.id, 'title': g.title, 'subtitle': g.subtitle},
          ],
        },
    ],
    'steps': steps,
  };
  return '${const JsonEncoder.withIndent(' ').convert(doc)}\n';
}

void main() {
  test('Mã bước hướng dẫn không trùng giữa các mục (AI tra theo mã bước)', () {
    final ids = _allSteps.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'trùng mã bước');
  });

  test('Mỗi bước thuộc đúng một nhóm, nhóm không trỏ tới bước không có', () {
    final ids = _allSteps.map((s) => s.id).toSet();
    final placed = <String, String>{};
    for (final a in LandingGuideGroups.areas) {
      for (final g in a.groups) {
        expect(g.stepIds, isNotEmpty, reason: 'nhóm ${g.id} rỗng');
        for (final id in g.stepIds) {
          expect(ids.contains(id), isTrue, reason: 'nhóm ${g.id} có bước không tồn tại: $id');
          expect(placed[id], isNull, reason: '$id nằm ở cả ${placed[id]} và ${g.id}');
          placed[id] = g.id;
        }
      }
    }
    expect(ids.difference(placed.keys.toSet()), isEmpty,
        reason: 'bước chưa xếp nhóm — thêm vào lib/utils/landing_guide_groups.dart');
  });

  test('Bước của khu nào chỉ nằm trong nhóm của khu đó', () {
    final data = LandingGuideData.defaults;
    for (final a in LandingGuideGroups.areas) {
      final inArea = {
        for (final sec in a.sections) ...data.stepsAt(LandingGuideData.indexForKey(sec)).map((s) => s.id),
      };
      for (final g in a.groups) {
        for (final id in g.stepIds) {
          expect(inArea.contains(id), isTrue, reason: '$id (nhóm ${g.id}) không thuộc khu ${a.id}');
        }
      }
    }
  });

  test('Bản hướng dẫn cho trợ lý AI / guide.html khớp hướng dẫn trong app', () {
    final json = buildGuideCorpusJson();
    final file = File(corpusPath);
    if (Platform.environment['GUIDE_CORPUS_UPDATE'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(json);
    }
    expect(file.existsSync(), isTrue, reason: 'chưa có $corpusPath — chạy với GUIDE_CORPUS_UPDATE=1');
    expect(file.readAsStringSync().replaceAll('\r\n', '\n'), json,
        reason: 'hướng dẫn đã đổi — chạy GUIDE_CORPUS_UPDATE=1 flutter test test/guide_shots/guide_corpus_test.dart');
  });
}
