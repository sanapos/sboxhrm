import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/landing_industry_guide.dart';
import 'package:zkteco_flutter_client/utils/landing_usage_guide.dart';

/// Trợ lý AI (máy chủ) trả lời «làm thế nào…» bằng đúng nội dung hướng dẫn này:
/// toàn bộ bước được xuất ra src/ZKTecoADMS.Api/Services/HelpCorpus/landing-guide.json
/// (nhúng vào API, đọc bởi AiAssistantHelpCorpus). Sửa hướng dẫn mà quên xuất lại → test đỏ.
/// Xuất lại: GUIDE_CORPUS_UPDATE=1 flutter test test/guide_shots/guide_corpus_test.dart
const corpusPath = '../src/ZKTecoADMS.Api/Services/HelpCorpus/landing-guide.json';

String buildGuideCorpusJson() {
  final sections = {
    'basic': LandingUsageGuide.basicSteps,
    'advanced': LandingUsageGuide.advancedSteps,
    'pos': LandingUsageGuide.posSteps,
    'industry': landingIndustrySteps,
  };
  final rows = [
    for (final MapEntry(key: mode, value: steps) in sections.entries)
      for (final s in steps)
        {
          'mode': mode,
          'stepId': s.id,
          'title': s.title,
          'desc': s.desc,
          'bullets': s.bullets,
          'tip': s.tip,
          'keywords': s.keywords,
          'shots': [
            for (final shot in s.shots) {'afterBullet': shot.afterBullet, 'caption': shot.caption},
          ],
        },
  ];
  return '${const JsonEncoder.withIndent(' ').convert(rows)}\n';
}

void main() {
  test('Mã bước hướng dẫn không trùng giữa các mục (AI tra theo mã bước)', () {
    final ids = [
      ...LandingUsageGuide.basicSteps,
      ...LandingUsageGuide.advancedSteps,
      ...LandingUsageGuide.posSteps,
      ...landingIndustrySteps,
    ].map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'trùng mã bước');
  });

  test('Bản hướng dẫn cho trợ lý AI khớp hướng dẫn trong app', () {
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
