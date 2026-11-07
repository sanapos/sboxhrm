import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/features/leave/leave_catalog.dart';

/// REST trả enum dạng tên, SignalR dạng số: cả hai phải ra cùng một giá trị.
void main() {
  group('LeavePaymentSource.fromValue', () {
    test('đọc tên enum từ REST', () {
      expect(LeavePaymentSource.fromValue('EmployerPaid'), LeavePaymentSource.employerPaid);
      expect(LeavePaymentSource.fromValue('Unpaid'), LeavePaymentSource.unpaid);
      expect(LeavePaymentSource.fromValue('SocialInsurance'), LeavePaymentSource.socialInsurance);
      expect(LeavePaymentSource.fromValue('EmployerWithBhxhSettlement'), LeavePaymentSource.employerBhxh);
    });

    test('đọc số và chuỗi số', () {
      expect(LeavePaymentSource.fromValue(1), LeavePaymentSource.unpaid);
      expect(LeavePaymentSource.fromValue('2'), LeavePaymentSource.socialInsurance);
    });

    test('giá trị lạ về mặc định', () {
      expect(LeavePaymentSource.fromValue(null), LeavePaymentSource.employerPaid);
      expect(LeavePaymentSource.fromValue('Khac'), LeavePaymentSource.employerPaid);
    });
  });

  group('SickLeaveMode.fromValue', () {
    test('đọc tên enum từ REST', () {
      expect(SickLeaveMode.fromValue('NotApplicable'), SickLeaveMode.notApplicable);
      expect(SickLeaveMode.fromValue('UseAnnualLeave'), SickLeaveMode.useAnnualLeave);
      expect(SickLeaveMode.fromValue('SocialInsurance'), SickLeaveMode.socialInsurance);
    });

    test('đọc số', () {
      expect(SickLeaveMode.fromValue(2), SickLeaveMode.socialInsurance);
    });
  });
}
