# Phân tích báo cáo theo ngành: Sổ khách lưu trú · Thẻ tập sắp hết hạn · Thuế hộ kinh doanh

Ngày 17/10/2026, nhánh fix/tingee-agent-scope-deploy. Mức độ: 🔴 cao (sai số liệu / rủi ro pháp lý) · 🟠 trung bình · 🟡 thấp (giao diện, câu chữ).

## 1. Sổ khách lưu trú (`PosStayGuestsController.Register`, `AnalyticsReportSpec.stayGuests`)

Phần đúng: kỳ lọc theo ngày giờ VN (`VnRange`), lấy mọi lượt ở giao với kỳ (khách đang ở cũng có). File Excel đổi giờ sang giờ VN. Lọc theo cửa hàng và bỏ bản ghi đã xóa (bộ lọc chung của DbContext).

| # | Mức | Vấn đề | Trạng thái |
|---|---|---|---|
| 1 | 🔴 | Trên app, giờ nhận / trả phòng **sớm hơn thực tế 7 tiếng**: API trả giờ UTC không có «Z», app hiểu là giờ máy. Ví dụ khách đến 21:30 thì app hiện 14:30. Đây là giờ dùng để khai báo tạm trú. Excel thì đúng. | **Đã sửa**: API trả giờ VN |
| 2 | 🟠 | Không nhắc khách thiếu số giấy tờ / ngày sinh, trong khi khai báo lưu trú cần hai thông tin này. | **Đã sửa**: thêm ô «Thiếu giấy tờ / ngày sinh» |
| 3 | 🟠 | **Phòng đã nhận nhưng chưa nhập khách nào thì không hiện trong sổ.** Đây là lỗ hổng lớn nhất về tuân thủ: quy định yêu cầu thông báo lưu trú trong ngày, và cũng là lúc dễ «quên» khai báo. | Đề xuất (cần lọc riêng tài nguyên là phòng khách sạn, vì bàn quán ăn cũng dùng `PosResourceSession`) |
| 4 | 🟠 | Không lọc theo chi nhánh (`PosServiceResource.BranchId` có sẵn). Chuỗi nhiều cơ sở thì mỗi cơ sở khai báo với công an phường của mình, nhưng sổ đang gộp tất cả. | Đề xuất `?branchId=` |
| 5 | 🟡 | Nhãn cột lộ tiếng Anh: «Ngày birth», «Primary». | **Đã sửa** |
| 6 | 🟡 | Biểu đồ «Số lượt theo nhận phòng» có trục 0,2 / 0,4 lượt (số lẻ). Cột «Trả phòng» để trống thay vì ghi «Đang ở». Giờ nhận phòng bị cắt «10/10/2026 2…». | Đề xuất |
| 7 | 🟡 | Khách nước ngoài khai báo theo quy trình riêng (hộ chiếu, thị thực, cổng xuất nhập cảnh). Sổ chưa tách nhóm này và chưa có cột số thị thực / ngày nhập cảnh. | Đề xuất |

## 2. Thẻ tập & gói buổi sắp hết hạn (`GetExpiringPacks`, `AnalyticsReportSpec.sessionExpiry`)

Phần đúng: «còn N ngày» tính theo ngày lịch VN. Thẻ thời gian không tính là «sắp hết buổi». Thẻ đã gia hạn cùng sản phẩm được đánh dấu để không nhắc trùng (thẻ thời gian gia hạn sẽ nối hạn từ hạn cũ).

| # | Mức | Vấn đề | Trạng thái |
|---|---|---|---|
| 1 | 🔴 | **Thẻ đang bảo lưu** vẫn bị liệt kê «sắp hết hạn / đã hết hạn», nên lễ tân gọi nhầm khách đang bảo lưu. Màn hình Gym (`PosGymController.Expiring`) đã loại thẻ bảo lưu, nhưng báo cáo này thì chưa, nên hai nơi cho số khác nhau. | **Đã sửa** |
| 2 | 🟠 | Gói buổi dùng hết từ lâu (không có hạn) **nằm mãi trong danh sách**, vì điều kiện «còn ≤ 2 buổi» không giới hạn thời gian. Gói hết buổi còn bị ghi «Sắp hết buổi». | **Đã sửa**: chỉ giữ trong 30 ngày sau buổi cuối, trạng thái mới «Đã hết buổi» và ô đếm riêng |
| 3 | 🟠 | Khách đã xóa vẫn hiện, tên để trống. | **Đã sửa** |
| 4 | 🟠 | Biểu đồ tự động xếp hạng theo «số buổi đã dùng», không giúp gì cho việc gọi nhắc gia hạn. | **Đã sửa**: tắt (`rankChart: false`) |
| 5 | 🟠 | Khách gia hạn bằng **gói khác sản phẩm** (lên thẻ 3 tháng, đổi gói PT) vẫn bị nhắc, vì chỉ so cùng `ProductId`. | Đề xuất: so cùng loại thẻ (thời gian / buổi) |
| 6 | 🟡 | Cột «Còn (ngày)» ra số âm (-7), người không chuyên khó hiểu. Không có nút gọi / Zalo. Không có bộ lọc trạng thái, dù API đã hỗ trợ `status=`. | Đề xuất: «Hết hạn 7 ngày trước», nút gọi điện, chip lọc |

## 3. Thuế hộ kinh doanh (`HkdBooksController`, `pos_hkd_books_screen.dart`)

Phần đúng: ngày ghi sổ theo ngày lịch VN (`VnDay`, `PosBusinessRange`). Hàng trả lại ghi dòng âm theo ngày trả, không trừ hai lần. Chi phí bỏ «Nhập hàng / Trả hàng khách / Hoàn cọc» để không tính trùng. Các mẫu S1a / S2a–S2e đúng tên theo TT 152/2025. Test `PosReportConsistencyTests` đã có kiểm tra sổ HKD.

| # | Mức | Vấn đề | Trạng thái |
|---|---|---|---|
| 1 | 🔴 | **Nhóm thuế do người dùng tự chọn (mặc định nhóm 2)**, máy không đối chiếu với doanh thu thật. Hộ bán 4 tỷ / năm mà để nhóm 2 thì vẫn xuất S2a và tính thuế % doanh thu, không cảnh báo. | Đề xuất: tính doanh thu 12 tháng / năm nay rồi gợi ý nhóm («Bạn đã bán 2,4 / 3 tỷ»), thanh tiến độ tới ngưỡng |
| 2 | 🔴 | **Tỷ lệ % GTGT / TNCN mặc định 0%**, nên «Thuế ước tính» = 0 đồng mà không nhắc gì. | Đề xuất: chọn ngành thì gợi ý tỷ lệ (phân phối hàng hóa 1% + 0,5%; dịch vụ 5% + 2%; sản xuất / ăn uống 3% + 1,5%…), cảnh báo khi còn 0% |
| 3 | 🟠 | Quy định 2026 đang thay đổi: ngưỡng không chịu thuế là 500 triệu hay 1 tỷ (có nguồn nói NĐ 141/2026 nâng lên 1 tỷ). Chưa rõ nhóm 500 triệu – 3 tỷ tính trên toàn bộ doanh thu hay phần vượt ngưỡng. App đang nhân % với **toàn bộ** doanh thu và ghi cứng chữ «dưới 1 tỷ / 1–3 tỷ / trên 3 tỷ». | Cần đối chiếu văn bản gốc. Nên đưa ngưỡng và cách tính vào cấu hình, **chưa sửa code** |
| 4 | 🟠 | S2c (nhóm 3) tính **toàn bộ tiền nhập hàng trong kỳ** là chi phí, không phải giá vốn hàng đã bán. Nhập nhiều tồn kho cuối năm thì «thu nhập tính thuế» thấp giả tạo, nên quyết toán dễ bị điều chỉnh. | Đề xuất: dùng giá vốn hàng bán (đã có ở báo cáo lợi nhuận) hoặc ghi rõ phương pháp |
| 5 | 🟡 | Đổi nhóm ở hồ sơ nhưng chưa bấm «Lưu» thì bản xem trước vẫn dùng nhóm và % đã lưu (dòng tóm tắt ghi «Nhóm 2» khi đang xem S1a). | Đề xuất: gửi nhóm / % kèm yêu cầu xem trước, hoặc bắt lưu trước |
| 6 | 🟡 | Không có đồ thị, không có kết luận dễ hiểu. Người dùng chỉ thấy bảng chứng từ dài và mã sổ (S2a-HKD…). Hồ sơ HKD nằm dưới cùng, thu gọn. | Đề xuất: thẻ kết luận xanh / vàng / đỏ (`pos_health_widgets.dart`), «Doanh thu năm nay so với ngưỡng», cột doanh thu theo tháng, «Thuế ước tính quý này», lịch nộp tờ khai |
| 7 | 🟡 | Gộp mọi chi nhánh của cửa hàng. Với hộ kinh doanh (một MST) thì gộp là đúng, nhưng nên ghi rõ trên màn hình. | Ghi chú |

## Thay đổi đã làm (kèm test)
- `PosStayGuestsController.Register`: trả giờ VN, thêm `missingIdCount`.
- `PosSellIndustryController.Memberships.GetExpiringPacks`: bỏ thẻ bảo lưu và khách đã xóa; gói hết buổi chỉ giữ trong `expiredDays` ngày và có trạng thái «Đã hết buổi» / `usedUpCount`.
- `analytics_reports_screen.dart`: thêm `rankChart` (tắt cho thẻ tập), thêm nhãn tiếng Việt.
- Test: `src/ZKTecoADMS.Tests/Pos/PosIndustryReportsTests.cs` (2 test; khi bỏ phần sửa thì cả 2 đều đỏ), `flutter_client/test/analytics_reports_view_test.dart` (thêm 4 test chụp màn hình).
- **Chưa deploy.** API cần `scripts/deploy-api-only.ps1`, web cần `scripts/deploy-flutter-web-only.ps1`.

## Đề xuất nâng cấp giao diện (cần người dùng đồng ý)
1. Thuế HKD: màn hình «Sức khỏe thuế», gồm kết luận màu, thanh doanh thu so với ngưỡng, cột theo tháng, thuế ước tính theo quý, gợi ý nhóm và tỷ lệ theo ngành, việc nên làm.
2. Sổ lưu trú: thẻ đỏ «X phòng đang có khách nhưng chưa khai báo», «Y khách thiếu giấy tờ», nút «Xuất file khai báo hôm nay», tách khách nước ngoài.
3. Thẻ tập: chia nhóm «Gọi hôm nay / Tuần này / Đã hết – mời quay lại», nút gọi / Zalo, biểu đồ tròn theo trạng thái, tỷ lệ gia hạn tháng.

## Cập nhật: commit 1470953e (Thuế HKD, người dùng đã duyệt)
- Ngưỡng mới: dưới 1 tỷ/năm không nộp GTGT, TNCN (trước đây 500 triệu); 1–3 tỷ nộp % doanh thu; trên 3 tỷ tính TNCN trên thu nhập. Hằng số `ExemptRevenueBelow` / `IncomeMethodRevenueAbove` ở `HkdBooksController.Overview.cs`.
- API `GET /api/hkd/overview?year=&basis=all|invoice`. Sổ (xem + Excel) có thêm `basis=invoice`: chỉ đơn đã xuất HĐĐT (Issued), theo ngày lập hóa đơn.
- Sửa lỗi: sổ HKD trước đây chỉ lấy `Total` (tiền hàng), bỏ sót VAT, phụ thu, phí giao hàng.
- `PosReportMobileScaffold` dùng font app; `HkdBookPreviewPanel` có ScrollController riêng.
- Chưa làm: bản sao `flutter_pos/lib/screens/pos/pos_hkd_books_screen.dart` chưa có tổng quan. Chưa deploy.

## Deploy 17/10/2026 (người dùng yêu cầu)
- API sboxhrm (103.133.224.176) từ HEAD 1470953e: container healthy, /api/hkd/overview trả 401 khi chưa đăng nhập (có endpoint).
- Web sboxhrm.com: build 1.0.713 (build_number 1792243177), trang chủ SEO dựng đúng (h1 SBOX HRM, có canonical), main.dart.js có chuỗi mới.
- Khóa deploy: C:\Users\TH DECOR\.ssh\sbox_deploy_ed25519 (đặt $env:SBOX_DEPLOY_KEY trước khi chạy script).
- KHÔNG deploy sboxpos.com (103.133.225.67) và app flutter_pos.
