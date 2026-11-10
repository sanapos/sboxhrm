# Nhân sự chấm công — ghi rõ 3 thao tác đồng bộ (09/11/2026)

Chưa commit / deploy. File của phiên này (chỉ phần này):
- flutter_client/lib/screens/device_users_screen.dart — bỏ 3 icon (Tải từ máy / Copy sinh trắc / Tải hồ sơ NS) khỏi thanh trên; thêm khung «Đồng bộ nhân viên với máy chấm công» (`_buildSyncActionsPanel`, lớp `_SyncActionInfo` cuối file) đầu trang; thêm dòng chiều dữ liệu trong hộp chọn máy (tải từ máy) và hộp tải hồ sơ NS.
- flutter_client/lib/widgets/copy_biometrics_dialog.dart — dòng giải thích đầu hộp; `_confirmOverwrite` hỏi lại trước khi copy (đếm người trùng PIN / nhân viên trên máy đích = bị ghi đè).
- tool/i18n/{en,ko,ja,zh}.json + assets/l10n/{en,ko,ja,zh}.json — 20 chuỗi + 3 mẫu mới, nối cuối (không sắp xếp lại), sửa bản dịch «Tải hồ sơ nhân sự xuống máy» / «Copy sinh trắc sang máy khác». Các file này lúc sửa đang sạch so với HEAD.

Ý nghĩa (đã đọc backend):
- Tải từ máy: lệnh SyncDeviceUsers → máy gửi user về SBOX; không đổi gì trên máy.
- Tải hồ sơ NS: createDeviceUser cho NV chưa liên kết máy đó; không đụng người đã có; không có sinh trắc.
- Copy sinh trắc (BiometricController.CopyBiometricsCore): khớp PIN (DeviceUserPins.Key) hoặc EmployeeId trên máy đích → ghi đè tên, thẻ, mật khẩu, quyền, vân tay cùng FingerIndex, khuôn mặt cùng FaceIndex; ngón khác giữ; chưa có thì tạo mới.

Ảnh: E:\gtmp\devusers_shots (build web E:\gtmp\devusers_web, API 7070, TK QA Gym, 2 máy giả lập qua playwright route, chặn mọi lệnh ghi). Các cửa hàng QA khác báo «hết hạn» khi đăng nhập.
