import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/landing_usage_guide.dart';

void main() {
  test('Tab Ngành hàng có đủ các ngành và id không trùng', () {
    final d = LandingGuideData.defaults;
    expect(d.industryCount, greaterThanOrEqualTo(8));
    expect(d.stepsAt(3), same(d.industry));
    expect(LandingGuideData.keyForIndex(3), 'industry');
    expect(LandingGuideData.indexForKey('industry'), 3);
    expect(LandingGuideData.isKnownSection('industry'), isTrue);
    final ids = [...d.basic, ...d.advanced, ...d.pos, ...d.industry].map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('Tìm karaoke / hoa hồng ra mục ngành hàng', () {
    final d = LandingGuideData.defaults;
    expect(d.search('karaoke').any((h) => h.sectionIndex == 3 && h.step.id == 'ind_room_hourly'), isTrue);
    expect(d.search('hoa hồng').any((h) => h.sectionIndex == 3), isTrue);
  });

  test('Nội dung CMS cũ (chưa có industry) vẫn giữ mục ngành hàng mặc định', () {
    final d = LandingGuideData.fromApiJson('{"basic":[],"advanced":[],"pos":[]}');
    expect(d.industryCount, LandingGuideData.defaults.industryCount);
    final edited = LandingGuideData.fromApiJson(
        '{"industry":[{"id":"ind_gym","title":"Gym sửa","desc":"x"}]}');
    expect(edited.industry.firstWhere((s) => s.id == 'ind_gym').title, 'Gym sửa');
  });
}
