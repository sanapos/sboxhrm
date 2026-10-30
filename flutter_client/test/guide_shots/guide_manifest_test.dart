import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/landing_industry_guide.dart';
import 'package:zkteco_flutter_client/utils/landing_usage_guide.dart';

/// Mọi [GuideShot] khai báo trong hướng dẫn phải có đủ ảnh máy tính + điện thoại, và
/// mỗi dòng bước nó gắn vào phải tồn tại. GUIDE_SHOT_DIR có → ghi manifest.json
/// (tên ảnh, chú thích, bước) để scripts/guide_html_shots.py chèn hình vào guide.html.
void main() {
  final steps = [
    ...LandingUsageGuide.basicSteps,
    ...LandingUsageGuide.advancedSteps,
    ...LandingUsageGuide.posSteps,
    ...landingIndustrySteps,
  ];

  test('Ảnh hướng dẫn đủ file và gắn đúng dòng bước', () {
    final seen = <String>{};
    for (final step in steps) {
      for (final s in step.shots) {
        expect(seen.add(s.name), isTrue, reason: 'ảnh ${s.name} khai báo hai lần');
        expect(s.afterBullet, inInclusiveRange(1, step.bullets.length), reason: '${step.id}/${s.name}: không có dòng bước ${s.afterBullet}');
        for (final f in ['${s.name}.webp', '${s.name}-mobile.webp']) {
          expect(File('web/images/guide/$f').existsSync(), isTrue,
              reason: 'thiếu web/images/guide/$f — chạy scripts/render-guide-shots.ps1');
        }
      }
    }
  });

  test('Ghi manifest ảnh hướng dẫn', () {
    final dir = Platform.environment['GUIDE_SHOT_DIR'];
    if (dir == null) return;
    final rows = [
      for (final step in steps)
        for (final s in step.shots)
          {
            'name': s.name,
            'caption': s.caption,
            'stepId': step.id,
            'stepTitle': step.title,
            'bullet': step.bullets[s.afterBullet - 1],
          },
    ];
    File('$dir/manifest.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));
  });
}
