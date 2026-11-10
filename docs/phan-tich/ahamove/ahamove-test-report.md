# Test tạo đơn giao hàng AhaMove — 03/11/2026

## Cách đã thử
- Test có sẵn: `dotnet test` (build ra E:\gtmp\aha_tests), lọc Ahamove|Shipping → 176/176 đạt (8 test AhaMove dùng HTTP giả).
- Chạy thật: API code hiện tại ở 127.0.0.1:7073 (DB sbox_qa, `ahamove-qa/run-aha-api.ps1`, dll ở E:\gtmp\aha_api), máy chủ AhaMove giả 127.0.0.1:7099 (`ahamove-qa/aha_mock.py`, phải là HTTP/1.1 — bản HTTP/1.0 làm .NET dùng lại kết nối đã đóng → «response ended prematurely», lỗi giả). Cửa hàng QA Retail a1f71c, setting AhaMove trỏ ApiBaseUrl về mock. Kịch bản: `ahamove-qa/aha_flow.py`, kết quả `ahamove-qa/aha_flow_out2.txt`.
- Staging thật (partner-apistg.ahamove.com) chỉ gọi /v3/accounts/token với khóa giả: 404 `{"code":"PARTNER_NOT_FOUND","title":"Partner not found.","description":"Sorry, your parner not found."}`. Không có khóa sandbox nên không tạo đơn trên staging.
- Dọn: đã tắt AhaMove (Enabled=false, xóa ApiBaseUrl) ở QA Retail; dừng 7073/7099. Còn lại 6 đơn nháp giao hàng TMP01–TMP06 trong QA Retail (2 đơn TMP05/TMP06 có mã vận đơn giả).

## Kết quả từng bước (qua API thật + mock)
1. Lưu cấu hình → đổi key lấy JWT, notice «Đã lấy token…» ✅
2. /quote → 33.000đ, DAD-BIKE, ETA 25 phút ✅   3. /compare → AhaMove có badge rẻ/nhanh ✅
4. /shipments → mã 260HFO4A, lưu DeliveryCarrierFee, COD 200.000, CASH_BY_RECIPIENT, link shared ✅
5. Bấm lần 2 bị chặn ✅  6. /label trả shared_link ✅  7. sync-tracking ACCEPTED → picking ✅
8. Webhook: không khóa 401, ?hash= 200, header apikey + mã «-1» 200, COMPLETED+path FAILED → delivery_failed ✅
9. Hủy → cancelled, tạo lại sau hủy ✅; hủy khi IN PROCESS → «Order status is not cancellable» ✅

## Lỗi tìm thấy (chưa sửa — chờ người dùng đồng ý)
A. Token AhaMove làm mới KHÔNG được lưu (DbContext NoTracking): LoadEnabledCarrierAsync (PosShippingService.cs:275) và CompareForOrderAsync (:398) đọc setting không AsTracking → `settings.Password = token` + SaveChangesAsync không ghi. Đo được: sau khi token cũ hết hạn/thu hồi, MỌI lời gọi đều 401 → lấy token → gọi lại (3 request thay vì 1); DB giữ mãi token chết. Sửa: `.AsTracking()` ở 2 chỗ đó (hoặc ExecuteUpdate cột Password).
B. Đọc lỗi AhaMove sai trường: PostAccountTokenAsync (AhamoveShippingClient.cs:176) so `title == "USER_NOT_FOUND"`, nhưng AhaMove thật để mã ở `code`, `title` là câu chữ → nhánh tự đăng ký tài khoản (/v3/accounts) không bao giờ chạy; tương tự kiểm `ACCOUNT_EXISTED` (:150) và `ORDER_CANCELLED` (:667). Người dùng nhận thông báo tiếng Anh «Sorry, your parner not found.». Sửa: đọc `code` trước `title`, map mã lỗi chính sang tiếng Việt.
C. Đổi API key / Sandbox↔Production / SĐT không xóa JWT cũ (UpsertAsync :312) → JWT cũ còn hạn được dùng tiếp (gửi JWT staging lên production, hoặc vẫn báo «Đã lấy token» dù key mới sai). Sửa: xóa Password khi ApiToken/UseSandbox/ShopId/ApiBaseUrl đổi.
D. (nhẹ) Địa chỉ giao lặp phường: «20 Lê Lợi, Phường Hải Châu, Phường Hải Châu, Đà Nẵng» — Normalizer dùng phường làm quận cho địa chỉ 2 cấp, AhaMove ComposeDropoffAddress ghép cả hai; DeliveryDistrict của đơn bị ghi = tên phường. Sửa: bỏ quận nếu trùng phường khi ghép địa chỉ AhaMove.
E. (lưu ý) Tọa độ điểm giao lấy từ Nominatim (OSM) công khai — chạy được trong test, nhưng không có cache/giới hạn tốc độ; Nominatim chặn >1 req/s.

## Đã sửa (03/11/2026, người dùng đồng ý; commit d220b070 trên fix/tingee-agent-scope-deploy, CHƯA deploy)
- A: AsTracking ở LoadEnabledCarrierAsync + CompareForOrderAsync → token làm mới được lưu.
- B: ReadErrorCode đọc `code` (rồi `title` dạng MÃ_LỖI); USER_NOT_FOUND / ACCOUNT_EXISTED / ORDER_CANCELLED theo mã; thông báo tiếng Việt cho PARTNER_NOT_FOUND, USER_NOT_FOUND, NOT_AUTHORIZED, INVALID_PHONE_NUMBER, DEACTIVATED_ACCOUNT, SERVICE_UNAVAILABLE.
  + Lỗi phát hiện thêm: EnsureUserTokenAsync đăng ký tài khoản khi `existed is false` (ngược) — trước đây bù trừ với lỗi đọc title nên thử đăng ký cho MỌI lỗi (kể cả sai key). Nay chỉ đăng ký khi USER_NOT_FOUND.
- C: UpsertAsync xóa JWT AhaMove khi ApiToken / UseSandbox / ShopId / PickupPhone / ApiBaseUrl đổi.
- D: ComposeDropoffAddress bỏ phần trùng; backfill DeliveryDistrict chỉ khi quận khác phường.
- Test mới: 10 test trong ShippingCarrierContractTests (Ahamove_*), tổng vận chuyển 186/186 đạt.
- Chạy lại luồng thật (aha_flow_out3.txt): token chỉ gọi 1 lần lúc lưu + 1 lần sau thu hồi, lần kế dùng token đã lưu; địa chỉ «20 Lê Lợi, Phường Hải Châu, Đà Nẵng». Staging thật khóa sai → notice «API Key AhaMove không đúng hoặc sai môi trường (Sandbox / Production) (PARTNER_NOT_FOUND)», không gọi /v3/accounts.
- QA Retail: AhaMove đã tắt lại; có thêm đơn nháp TMP07–TMP09 (tổng TMP01–TMP09).

## Đơn test trên STAGING AhaMove thật (03/11/2026, khóa staging người dùng gửi, SĐT 84935364556)
Chạy qua API QA 7073 (commit d220b070), cửa hàng QA Retail, điểm lấy 12 Bạch Đằng, Phường Hải Châu, Đà Nẵng (16.0678,108.2245).
Lưu cấu hình → «Đã lấy token user AhaMove (staging)»; báo giá DAD-BIKE 16.000đ, 1,84 km.
| Đơn SBOX | Mã AhaMove | Giao tới | Cước | payment_method | COD |
|---|---|---|---|---|---|
| TMP09 | 26ECGV3V | 20 Lê Lợi, P. Hải Châu | khách trả | CASH_BY_RECIPIENT | 200.000 |
| TMP10 | 26KRZ754 | 255 Hùng Vương, P. Thanh Khê | shop trả | BALANCE | 200.000 |
| TMP11 | 26XBKMS3 | 100 Nguyễn Văn Linh, P. Hải Châu | shop trả | BALANCE | 0 (đã trả trước) |
GET /v3/orders/{id} xác nhận: items (2 × 100.000), tracking_number = mã đơn SBOX, SĐT dạng 849…, lat/lng đủ, trạng thái ASSIGNING; sync-tracking → «Đang tìm tài xế». Không hủy đơn nào.
Chưa thử: webhook từ staging (QA local không có URL công khai); trường `remarks` (ghi chú) không thấy trong GET đơn.
Cấu hình AhaMove staging vẫn BẬT ở QA Retail (DB sbox_qa). Khóa ở scratchpad aha_stg_key.txt.

## Sửa chỗ hở webhook (03/11/2026, commit d8376649)
- Ghi chú đơn: SBOX gửi `remarks` (cấp đơn + từng điểm) đúng tên trường theo docs create-order; GET /v3/orders không trả remarks → không phải lỗi.
- Webhook AhaMove: docs nói gửi URL cho AhaMove cài — 1 URL / API key; đơn staging ghi partner "sbox" → nhiều shop có thể chung key, ?hash= riêng shop không dùng được. Nay nhận thêm `api_key` trong body khớp ApiToken AhaMove của cửa hàng sở hữu đơn (PosShippingService.AuthorizeAhamoveApiKeyAsync).
- Lỗi phát hiện thêm: đơn AhaMove có `tracking_code` (mã link theo dõi 261103…) — controller ưu tiên tracking_code hơn `_id` → không tìm thấy đơn, 401. Nay AhaMove luôn đọc `_id`.
- Test: Ahamove_webhook_nhan_api_key_trong_body (4 case), vận chuyển 190/190. QA 7073: body = đơn staging thật 26XBKMS3 + api_key thật → 200, đơn TMP11 «Đang lấy hàng»; key sai / thiếu → 401.
- Còn lại: deploy API; gửi AhaMove URL https://sboxhrm.com/api/webhooks/shipping/ahamove (kèm ?hash= nếu khóa riêng shop) để cài; sau đó staging callback mới thử được end-to-end.

## Deploy API (03/11/2026 ~09:38 giờ VN)
Deploy một phần: server tarball (bản 03/11 00:38 UTC) + chép đè 5 file của d220b070 + d8376649 (server đang đúng bản gốc của cả 5 file). Không kèm việc dở AiAssistant* của phiên khác. Bản trước lưu ở /root/api_src.before-ahamove.tar.gz.
Kiểm: zkteco_api healthy, /health 200, dll có AuthorizeAhamoveApiKeyAsync, https://sboxhrm.com/api/webhooks/shipping/ahamove trả 401 với đơn không tồn tại (đúng).
Việc còn lại: gửi AhaMove URL callback + 3 mã đơn test.
