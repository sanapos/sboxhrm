import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/task.dart';
import 'package:zkteco_flutter_client/models/task_v2.dart';

void main() {
  test('Biểu mẫu: đọc / ghi trường, giá trị', () {
    final fields = TaskFormFieldV2.parse(
        '[{"key":"nhiet_do","label":"Nhiệt độ tủ mát","type":"number","required":true,"unit":"°C"},'
        '{"key":"khu_vuc","label":"Khu vực","type":"select","options":["Bếp","Sảnh"]}]');
    expect(fields.length, 2);
    expect(fields.first.required, isTrue);
    expect(fields.first.unit, '°C');
    expect(fields.last.options, ['Bếp', 'Sảnh']);
    final again = TaskFormFieldV2.parse(TaskFormFieldV2.encode(fields));
    expect(again.map((f) => f.key), ['nhiet_do', 'khu_vuc']);
    expect(TaskFormFieldV2.encode([]), isNull);
    expect(TaskFormFieldV2.parse('hỏng'), isEmpty);
    expect(TaskFormFieldV2.parseValues('{"nhiet_do":"3.5","ok":true}'), {'nhiet_do': '3.5', 'ok': 'true'});
  });

  test('Việc mang dữ liệu đa ngành', () {
    final t = WorkTask.fromJson({
      'id': 't1', 'taskCode': 'TASK-1', 'title': 'Lắp máy lạnh', 'taskType': 'Installation', 'priority': 'High',
      'status': 'InProgress', 'progress': 0, 'storeId': 's', 'assignedById': 'u', 'createdAt': '2026-10-09T00:00:00',
      'customerName': 'Chị Lan', 'customerPhone': '0905', 'latitude': 16.05, 'longitude': 108.2,
      'requireCheckIn': true, 'pieceRate': 150000, 'pieceRatePaid': true, 'reworkCount': 1,
      'formSchema': '[{"key":"a","label":"A","type":"signature","required":true}]',
    });
    expect(t.customerName, 'Chị Lan');
    expect(t.requireCheckIn, isTrue);
    expect(t.pieceRate, 150000);
    expect(t.pieceRatePaid, isTrue);
    expect(t.reworkCount, 1);
    expect(TaskFormFieldV2.parse(t.formSchema).single.type, 'signature');
  });

  test('Thiết lập ngành, gói ưu tiên, bảng điều khiển', () {
    final ws = TaskWorkspaceV2.fromJson({
      'industryKey': 'service', 'taskLabel': 'Phiếu dịch vụ', 'projectLabel': 'Đơn dịch vụ',
      'photoStorage': 'gdrive', 'driveConnected': true, 'checkInRadiusM': 200, 'onboarded': true,
    });
    expect(ws.taskLabel, 'Phiếu dịch vụ');
    expect(ws.driveConnected, isTrue);
    expect(TaskWorkspaceV2.empty().onboarded, isFalse);
    final pack = TaskIndustryPackV2.fromJson({'key': 'sales', 'name': 'Sale', 'featured': true, 'taskLabel': 'Cơ hội', 'templates': [], 'stages': []});
    expect(pack.featured, isTrue);
    expect(pack.taskLabel, 'Cơ hội');
    final tpl = TaskTemplateV2.fromJson({'id': 'x', 'name': 'Mở ca', 'title': 'Mở ca', 'taskType': 'Routine', 'priority': 'High',
      'assignOnShift': true, 'pieceRate': 20000, 'formSchema': '[{"label":"Tiền đầu ca","type":"money"}]'});
    expect(tpl.assignOnShift, isTrue);
    expect(tpl.formFieldCount, 1);
    final d = TaskDashboardV2.fromJson({'total': 10, 'completed': 8, 'reworkRate': 12.5, 'avgCustomerRating': 4.5,
      'people': [{'employeeId': 'e', 'employeeName': 'An', 'completed': 3, 'pieceRateTotal': 300000}]});
    expect(d.people.single.pieceRateTotal, 300000);
    expect(d.reworkRate, 12.5);
  });
}
