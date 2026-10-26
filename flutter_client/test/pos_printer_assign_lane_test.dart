import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_product_printer_assignment_screen.dart';

void main() {
  group('assignLaneIsLabel', () {
    test('máy cloud đầu tiên nhận mọi loại chứng từ (cả tem) vẫn là lane phiếu bếp', () {
      // Server EnsureDefaultRoutes: máy K80 duy nhất nhận KitchenSlip + KitchenLabel + BarcodeLabel…
      const roles = [
        'KitchenSlip',
        'KitchenVoid',
        'StockIssue',
        'KitchenLabel',
        'BarcodeLabel',
        'ScaleLabel',
        'EndOfDayReport',
      ];
      expect(assignLaneIsLabel(isLabelPrinter: false, roles: roles), isFalse);
      expect(
        purposeForAssignLane(isLabel: false, roles: roles),
        PosAssignPrinterPurpose.kitchenSlip,
      );
    });

    test('máy chỉ có vai trò tem là lane tem', () {
      const roles = ['KitchenLabel', 'BarcodeLabel'];
      expect(assignLaneIsLabel(isLabelPrinter: false, roles: roles), isTrue);
      expect(
        purposeForAssignLane(isLabel: true, roles: roles),
        PosAssignPrinterPurpose.kitchenLabel,
      );
    });

    test('máy tem (hãng label) nhưng cấu hình Báo kho → lane phiếu, mục đích Báo kho', () {
      const roles = ['StockIssue'];
      expect(assignLaneIsLabel(isLabelPrinter: true, roles: roles), isFalse);
      expect(
        purposeForAssignLane(isLabel: false, roles: roles),
        PosAssignPrinterPurpose.stockIssue,
      );
    });

    test('chưa cấu hình chứng từ → theo hãng máy', () {
      expect(assignLaneIsLabel(isLabelPrinter: true, roles: const []), isTrue);
      expect(assignLaneIsLabel(isLabelPrinter: false, roles: const []), isFalse);
      expect(
        purposeForAssignLane(isLabel: false, roles: const []),
        PosAssignPrinterPurpose.kitchenSlip,
      );
      expect(
        purposeForAssignLane(isLabel: true, roles: const []),
        PosAssignPrinterPurpose.kitchenLabel,
      );
    });

    test('máy chỉ in hóa đơn / cuối ngày không phải lane tem', () {
      expect(
        assignLaneIsLabel(
          isLabelPrinter: false,
          roles: const ['SaleInvoice', 'EndOfDayReport'],
        ),
        isFalse,
      );
    });
  });
}
