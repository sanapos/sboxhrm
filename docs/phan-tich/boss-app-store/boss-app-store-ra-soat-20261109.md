# SBOX BOSS trên App Store — rà soát 09/11/2026

Nguồn: App Store Connect API (khóa NH398D89H2, chỉ GET, script ở scratchpad phiên ddfb7ca2: asc_get.py, boss_state.py, cmp_sets.py), code tại commit 9cc89885 (feat/boss-parity, build 5), ảnh ở `dist/app-store-assets/boss`. Trình duyệt tích hợp chưa đăng nhập App Store Connect nên không xem giao diện web; không bấm / sửa gì.

## 1. Hiện trạng thực tế

- App 6831442612, bundle `boss.sboxpos.com`, SKU sbox-boss-ios, ngôn ngữ chính vi.
- Một phiên bản: **1.0.0 — WAITING_FOR_REVIEW**, phát hành thủ công. Gắn **build 5** (VALID, iOS 16+, tải lên 08/11 04:42 PST).
- Lần gửi duyệt: 518d4ba1… gửi 08/11 12:44 UTC đang chờ; 2 lần trước (12:06, 12:32) đã đóng.
- **Ảnh chụp màn hình (locale vi):**
  | Bộ ảnh | Số ảnh | Cỡ |
  |---|---|---|
  | APP_IPHONE_61 (iPhone 6.1"/6.3") | 4 | 1206×2622, đã xử lý xong |
  | APP_IPAD_PRO_3GEN_129 (iPad 13") | 2 | 2752×2064, đã xử lý xong |
  | iPhone 6.9" (APP_IPHONE_67) | **không có** | — |
  | iPhone 6.5" (APP_IPHONE_65) | **không có** | — |
  | Video xem trước | 0 | — |
  → Trang phiên bản trên App Store Connect hiện ô **6.9" Display trống**: đây là chỗ thấy «chưa có ảnh». Ảnh chỉ nằm ở cỡ 6.3", phải mở «View All Sizes in Media Manager» mới thấy.
- So sánh: Nhân Viên cũng chỉ có 6.1/6.3" + 5 ảnh iPad, và **đã được duyệt (PENDING_DEVELOPER_RELEASE — chờ người dùng bấm phát hành)**. POS 1.0.5 có bộ 6.9" rỗng + 3 ảnh 6.1" + 6 iPad, đang chờ duyệt. Vậy Apple không chặn nộp khi thiếu 6.9", nhưng trang chưa đúng chuẩn.

## 2. Yêu cầu Apple (tài liệu Screenshot specifications, đọc 09/11/2026)

- iPhone 6.9": 1320×2868, 1290×2796, 1260×2736 (dọc; ngang đảo lại). Bắt buộc nếu không có 6.5".
- iPhone 6.5": 1284×2778, 1242×2688. Bắt buộc nếu không có 6.9".
- iPhone 6.1"/6.3": 1206×2622, 1179×2556. Không cần nếu có 6.9" (tự thu nhỏ).
- iPad 13": 2064×2752 hoặc 2048×2732 (dọc; ngang 2752×2064 / 2732×2048). **Bắt buộc vì app chạy trên iPad** (TARGETED_DEVICE_FAMILY = 1,2). 11" tự thu nhỏ từ 13".
- Mỗi cỡ: tối thiểu 1, tối đa 10 ảnh. Định dạng .png / .jpg / .jpeg, **không có kênh alpha / trong suốt**, RGB.
- Nên tải đúng cỡ lớn nhất (6.9" + 13"), App Store Connect tự thu nhỏ cho máy nhỏ hơn.
- 2.3.3: ảnh phải cho thấy app đang dùng; ảnh iPad phải là app chạy trên iPad — Apple hay từ chối với câu «13-inch iPad screenshots show an iPhone image that has been modified or stretched».
- Ảnh khóa khi phiên bản đang chờ / đang duyệt / đã duyệt. Chỉ sửa được khi rút khỏi duyệt (Developer Rejected), bị từ chối, hoặc ở phiên bản sau.

## 3. Bảng yêu cầu

| Mục | Hiện có | Trạng thái | Rủi ro bị từ chối |
|---|---|---|---|
| Ảnh iPhone 6.9"/6.5" | không có; chỉ 4 ảnh 6.3" | **Thiếu** | Thấp (Apple đã duyệt Nhân Viên như vậy) nhưng trang ASC trống, máy Pro Max / Plus / Air có thể hiện ảnh thu phóng |
| Ảnh iPad 13" | 2 ảnh, mỗi ảnh là **2 khung màn điện thoại ghép trên nền** | Có nhưng sai bản chất | **Cao — 2.3.3** (ảnh iPhone ghép thành ảnh iPad) |
| Nội dung ảnh | Tổng quan «0 đ», «Chưa có số hôm qua để so», chữ bị cắt «Hôm qua cả n…», «cùng giờ» | Yếu | Thấp với duyệt, kém về tiếp thị |
| Giao diện thật trên iPad | `BossShell` không có bố cục máy tính bảng: iPad hiện giao diện điện thoại kéo giãn toàn màn | Chưa thử máy thật | Trung bình — Apple duyệt bằng iPad Air 11"; nếu vỡ bố cục là 4.0 / 2.1 |
| Tên | SBOX BOSS | Có | — |
| Phụ đề | «Doanh thu, duyệt việc, kho» (26/30) | Có | — |
| Văn bản quảng cáo | 130/170 | Có | — |
| Mô tả | 1265/4000, không nhắc khuôn mặt / vị trí / AI / Android | Có | Thấp |
| Từ khóa | 94/100 | Có | — |
| URL hỗ trợ / marketing | https://sboxpos.com | Có | Thấp — trang chủ, có hotline |
| URL chính sách | https://sboxpos.com/privacy-policy-pos.html — mở được, nêu BOSS iOS không có khuôn mặt, không thu vị trí, có mục xóa tài khoản | Có | Thấp |
| Danh mục | Business / Productivity | Có | — |
| Độ tuổi | 4+, không UGC, không quảng cáo | Có | Thấp — BOSS không có Bản tin; «Ý kiến nhân viên» là kênh riêng nội bộ |
| Bản quyền / Content Rights | DOES_NOT_USE_THIRD_PARTY_CONTENT | Có | — |
| App Privacy | Theo memory: đã Publish 08/11 (8 loại, App Functionality, gắn danh tính, không tracking). API không đọc được, web chưa đăng nhập | Chưa đối chiếu lại | Thấp nếu khớp |
| Tài khoản demo | demopos@gmail.com, có mật khẩu, ghi chú có Store code demopos | Có | Trung bình nếu mật khẩu đổi / cửa hàng hết gói — chưa thử đăng nhập lại hôm nay |
| Ghi chú duyệt | Ghi «does not use … background modes» nhưng Info.plist có `remote-notification`, `fetch` | Mâu thuẫn nhỏ | Thấp — nên sửa chữ khi có dịp |
| Câu xin quyền | Camera, ảnh, Bluetooth, mạng nội bộ, Face ID: câu riêng BOSS. Micro / giọng nói: câu «không dùng» (thư viện có sẵn trong gói). Vị trí đã xóa khỏi plist | Có | Thấp (5.1.1 nếu người duyệt soi plist) |
| Hỏi quyền lúc mở app | Đã bỏ (b912a361) | Đã sửa | — |
| Mã bí mật đổi máy chủ | iOS khóa sboxpos.com (b912a361) | Đã sửa | — |
| Firebase iOS | Có plist riêng boss.sboxpos.com, script kiểm bundle (5e070706) | Đã sửa | — |
| Khuôn mặt / vị trí / AI | Gỡ plugin, bỏ chữ (daec5fb1, 680c5487, 9cc89885) | Đã sửa | Thấp |
| Export compliance | `ITSAppUsesNonExemptEncryption=false`, build ghi usesNonExemptEncryption=false | Có | — |
| Giá / khu vực | availableInNewTerritories=true; memory: Free, 175 khu vực | Có | — |
| Xóa tài khoản | Thêm → Xóa tài khoản; trang /delete-account.html | Có | — |
| Email liên hệ | Ghi chú duyệt: sboxhrm@gmail.com; chính sách: support@sboxhrm.com | Lệch nhẹ | Không ảnh hưởng duyệt |

## 4. Hai hướng xử lý (người dùng chọn)

A. **Rút khỏi hàng chờ ngay** (Remove from Review, chưa ai duyệt) → tải bộ 6.9" + bộ iPad thật → nộp lại cùng build 5. Mất chỗ trong hàng đợi (~1 ngày), tránh lần từ chối 2.3.3.
B. **Để Apple duyệt tiếp**. Nếu bị từ chối 2.3.3 thì chỉ sửa ảnh, không cần build mới. Nếu được duyệt, ảnh khóa tới bản 1.0.1.

Khuyến nghị: A — rủi ro 2.3.3 của ảnh iPad là rõ, và dựng ảnh iPad thật cũng là cách kiểm luôn giao diện BOSS trên iPad trước khi người duyệt thấy.

## 5. Kế hoạch tạo ảnh

Không chụp bằng giả lập Android (thanh trạng thái Android = rủi ro 2.3.10) và không ghép khung điện thoại vào nền iPad.

1. Dựng từ code (giống `render-guide-shots.ps1` / `make-appstore-assets.py` của POS), ở commit build 5 (9cc89885, worktree tạm): test widget mới `test/store_shots/boss_store_shots_test.dart`, `--dart-define=SBOX_APP=boss` (thiếu define là mất giao diện xanh đen + vàng), API giả có số liệu thật thà (doanh thu khác 0, có so hôm qua, yêu cầu chờ duyệt có tên người thật giả lập, không có chữ «QA»).
   - iPhone: màn logic 440×956 @3x → 1320×2868.
   - iPad: màn logic 1032×1376 @2x → 2064×2752 (dọc) hoặc 1376×1032 → 2752×2064 (ngang), **render nguyên màn BossShell như trên iPad**, không khung điện thoại.
2. Năm cảnh: Tổng quan (doanh thu, cần xử lý) · Cần duyệt (danh sách nghỉ phép / sửa công / ứng lương) · Báo cáo kinh doanh hoặc Lãi lỗ (có biểu đồ) · Quản lý (lưới chức năng) · Phiếu thu chi / Hàng hóa & kho.
3. Mở rộng `make-appstore-assets.py` thêm `--app boss`: nền xanh đen #2C3C5E, vạch vàng #EFC66A, chú thích 1 dòng; iPhone có khung bo góc như bộ hiện tại; iPad ảnh full màn + chú thích. RGB, không alpha. Ra `dist/app-store-assets/boss/iphone69-*.png`, `ipad-*.png`.
4. Soát tay: không chữ Android / Sunmi / QA / HRM / khuôn mặt / vị trí / AI, không chữ cắt cụt, khớp tính năng có trong build 5 (không có Device / DeviceUser / chấm công điện thoại).
5. Tải lên qua API (script asc_boss_shots.py của phiên c6764e5f): bộ APP_IPHONE_67 (6.9") 5 ảnh, thay bộ iPad 13" 5 ảnh; xóa hoặc giữ bộ 6.1" (nên xóa để mọi iPhone dùng ảnh 6.9" thu nhỏ, đồng bộ). Kiểm lại bằng appScreenshotSets + Media Manager.
6. Nên làm cùng lúc cho Nhân Viên ở bản sau (đang thiếu 6.9" và ảnh iPad có tên «QA Staff Boss»).
