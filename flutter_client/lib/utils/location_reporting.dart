/// Gửi vị trí định kỳ cho «Bản đồ nhân sự» của SBOX HRM.
///
/// Bản cài đặt thật là `GlobalLocationReporter` (dùng gói `geolocator`) và chỉ được `lib/main.dart` gắn vào.
/// Bản SBOX Bán Hàng dùng điểm vào riêng, không gắn — nên gói không chứa mã theo dõi vị trí, thứ Apple nêu
/// đích danh khi từ chối theo điều 2.5.19.
abstract class LocationReporting {
  Future<void> startIfEligible({String? employeeId});

  /// Mở lại app: có thể vừa được cấp quyền vị trí trong Cài đặt máy.
  Future<void> resume({String? employeeId});

  void stop();
}

/// Null = bản app này không theo dõi vị trí.
LocationReporting? locationReporter;
