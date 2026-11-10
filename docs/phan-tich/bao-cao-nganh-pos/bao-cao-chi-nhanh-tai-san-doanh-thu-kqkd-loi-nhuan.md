# Phân tích: Báo cáo chi nhánh · Tài sản · Doanh thu · Kết quả kinh doanh · Lợi nhuận

Ngày 17/10/2026, nhánh fix/tingee-agent-scope-deploy. Mức độ: 🔴 cao (sai số liệu) · 🟠 trung bình · 🟡 thấp (giao diện, câu chữ).

## Cách tính chung (đã đối chiếu)
- **Doanh thu thuần** = Σ `Total` đơn hoàn thành. Đã trừ giảm giá, voucher, điểm và hàng khách trả; **chưa gồm VAT, phụ thu, phí giao hàng** (ba khoản này lưu riêng).
- **Giá vốn thuần** = giá vốn ghi khi bán − giá vốn hàng khách trả (`PosReportMoney`), gồm cả dịch vụ và combo.
- Kỳ báo cáo theo ngày kinh doanh VN, có giờ cắt ngày. Phiếu thu chi lọc theo giờ VN. Năm báo cáo dùng chung định nghĩa này, nên tổng doanh thu và giá vốn của chúng khớp nhau (test `PosReportConsistencyTests`).

## 1. Báo cáo chi nhánh (`BranchOperationsController.Compare/Overview`, `branch_report_screen.dart`)
| # | Mức | Vấn đề | Trạng thái |
|---|---|---|---|
| 1 | 🔴 | Tiền COD hãng vận chuyển chuyển về (phiếu «Thu hộ COD», ghi chú `pos cod #`) bị tính là **«thu khác»**. Doanh thu của đơn đó đã được tính rồi, nên lãi ròng chi nhánh bị đội lên đúng bằng tiền COD. Báo cáo Lãi lỗ đã loại khoản này. | **Đã sửa** + test |
| 2 | 🟠 | Tổng lãi ròng các chi nhánh **không khớp** Lãi lỗ cửa hàng. Chi nhánh trừ lương theo phiếu lương (gộp, phân bổ theo ngày) và không trừ hao hụt kho. Lãi lỗ trừ hao hụt kho (xuất hủy, kiểm kê) và chỉ trừ lương khi đã chi qua sổ quỹ (tiền thực trả). | Đề xuất: thống nhất một định nghĩa; Lãi lỗ nên có dòng «Lương (phiếu lương)» và chi nhánh nên có dòng «Hao hụt kho» |
| 3 | 🟠 | Lương tính cả phiếu lương **nháp / chờ duyệt**, trong khi chú thích trên màn hình ghi «phiếu lương đã chốt». | Đề xuất: chỉ tính Đã duyệt / Đã trả, hoặc sửa chú thích |
| 4 | 🟠 | Giá trị tồn kho chỉ tính dòng không biến thể (`variantId == null`). Hàng quản lý theo biến thể (size, màu) có giá trị 0. Đây là giá trị hiện tại, không phải cuối kỳ. | Đề xuất |
| 5 | 🟠 | Lương gán theo chi nhánh **hiện tại** của nhân viên. Nhân viên chuyển chi nhánh thì lương các tháng cũ cũng chuyển theo. | Đề xuất: lưu chi nhánh trên phiếu lương |
| 6 | 🟡 | Biểu đồ theo ngày lọc lại toàn bộ đơn cho mỗi (chi nhánh × ngày), nên kỳ 1 năm nhiều chi nhánh sẽ chậm. «Top hàng» ở trang chi tiết dùng tiền dòng gộp (chưa trừ hàng trả và giảm giá đơn), nên có thể lớn hơn doanh thu chi nhánh. | Đề xuất: gom nhóm một lần; dùng `NetLinesAsync` |
| 7 | 🟡 | Chưa có kết luận dễ hiểu (chi nhánh nào lỗ, vì sao), chưa xếp hạng biên lãi ròng, chưa có cảnh báo. | Đề xuất: thẻ xanh / vàng / đỏ theo chi nhánh (`pos_health_widgets`) |

## 2. Báo cáo tài sản (`AssetReportsController`, `AssetDashboardBuilder`, `asset_report_screen.dart`)
Phần đúng: khấu hao đường thẳng theo tỷ lệ %/năm (`AssetValuation`, có test). Tài sản đã thanh lý / mất có giá trị 0. Màn «Tổng quan» tách đúng tài sản đang dùng.
| # | Mức | Vấn đề | Trạng thái |
|---|---|---|---|
| 1 | 🔴 | Endpoint `summary` (màn «Báo cáo tài sản») cộng **nguyên giá tài sản đã thanh lý / mất** vào «Tổng giá trị mua» và giá trị theo loại / danh mục / người giữ. Số này khác màn Tổng quan. Ví dụ: thanh lý một máy 50 triệu thì tổng vẫn còn 50 triệu. | **Đã sửa** + test (vẫn đếm số lượng đủ) |
| 2 | 🟠 | **Khấu hao không vào Kết quả kinh doanh.** Mua tài sản bằng phiếu chi thì cả khoản tính chi phí ngay tháng mua. Không có phiếu chi thì không bao giờ thành chi phí. Lãi các tháng sau bị cao hơn thực tế. | Đề xuất: dòng «Khấu hao tài sản» trong KQKD (theo tháng), đánh dấu phiếu chi mua tài sản để không trừ hai lần |
| 3 | 🟠 | Không có chi nhánh trên tài sản, nên không có giá trị tài sản theo chi nhánh. Không chọn được «tính đến ngày», luôn là hôm nay. | Đề xuất |
| 4 | 🟡 | Bảo hành «còn N ngày» tính theo ngày UTC: từ 0h đến 7h sáng giờ VN lệch 1 ngày. Cột «Giá trị HT» trong Excel danh mục là giá 1 đơn vị, không ghi rõ. | Đề xuất |

## 3. Doanh thu (`sales/summary`, `PosRevenueReportScreen`)
| # | Mức | Vấn đề | Trạng thái |
|---|---|---|---|
| 1 | 🔴 | **Phụ thu** (phí phục vụ 5–10%…) và **phí giao hàng thu khách** không có trong «Doanh thu» và không có trong «DT gồm VAT» (= Total + VAT). Vì vậy «Đã thu» có thể lớn hơn «DT gồm VAT», người đọc khó hiểu. Lỗi này lan sang Lãi lỗ, Chi nhánh, Lợi nhuận: tiền phụ thu quán giữ lại **không vào lợi nhuận**. | **Cần quyết định** (xem dưới) |
| 2 | 🟡 | Ô so kỳ trước ổn. Còn thiếu đường «doanh thu / lãi theo ngày», chỉ có cột doanh thu. Chưa có kết luận dễ hiểu (tăng / giảm vì sao, ngày nào bất thường). | Đề xuất |

## 4. Kết quả kinh doanh (`pnl/summary`, `PosPnlReportScreen`)
Phần đúng: không trừ hàng trả hai lần, không trừ VAT. Có hao hụt kho (xuất hủy, dùng nội bộ, kiểm kê). Loại các phiếu thu chi không phải lãi / lỗ (tiền bán, nhập hàng, cọc, COD).
| # | Mức | Vấn đề | Trạng thái |
|---|---|---|---|
| 1 | 🔴 | Thiếu phụ thu và phí giao hàng / cước hãng (`DeliveryCarrierFee`). Thiếu khấu hao tài sản. Thiếu tiền cọc khách bỏ (cọc «Forfeited» là thu nhập, nhưng danh mục «Cọc đặt chỗ» bị loại toàn bộ). | **Cần quyết định** |
| 2 | 🟡 | Ô «Lợi nhuận ròng» ghi «Biên x%» nhưng là **biên lãi gộp**. | **Đã sửa** → «Biên lãi ròng» (`netMarginPct`) |
| 3 | 🟡 | Biểu đồ «Từ doanh thu đến lợi nhuận ròng» vẽ mọi khoản thành cột dương, nên khó thấy khoản nào làm giảm lãi. | Đề xuất: biểu đồ thác nước (xanh cộng, đỏ trừ) + kết luận màu + việc nên làm |

## 5. Lợi nhuận (`profit/by-product`, `profit/by-dimension`, `pos_profit_report_screen.dart`)
| # | Mức | Vấn đề | Trạng thái |
|---|---|---|---|
| 1 | 🔴 | Theo hàng: tổng doanh thu / giá vốn / lãi chỉ cộng **N dòng đầu sau khi xếp theo lãi giảm dần** (app gửi 500). Cửa hàng có hơn 500 mặt hàng thì các mặt hàng lỗ bị cắt, nên **tổng lãi cao hơn thực tế**. | **Đã sửa**: tổng trên mọi mặt hàng; danh sách cắt thì giữ cả nhóm lãi nhất và lỗ nhất; trả thêm `skuCount`, `truncated` |
| 2 | 🔴 | Tab nhóm / kênh / nhân viên: ba ô Doanh thu / Giá vốn / Lợi nhuận gộp **luôn 0đ**, vì API không trả tổng. | **Đã sửa** + test |
| 3 | 🟡 | Theo nhóm: giá vốn topping tặng (không có doanh thu riêng) không vào nhóm nào, nên tổng giá vốn theo nhóm có thể nhỏ hơn theo kênh. | Đề xuất |

## Thay đổi đã làm (commit kèm test; test Pos / Asset / Branch: 397 → 400, tất cả đạt; 3 test mới đều đỏ với mã cũ)
- `BranchOperationsController`: loại phiếu COD (`CodReceiptMarker`, danh mục «Thu hộ COD») khỏi «thu khác».
- `PosReportsController.Profit`: tổng theo hàng trên mọi mặt hàng (+`skuCount`, `truncated`); by-dimension trả `totalRevenue/totalCogs/totalProfit/marginPct/orderCount`.
- `AssetReportsController.BuildStatistics`: giá trị chỉ tính tài sản còn nắm giữ.
- `pos_split_report_screens.dart`: ô Lợi nhuận ròng hiện biên lãi ròng.
- Test: `BranchReportTests.Tien_COD_...`, `PosReportConsistencyTests.Loi_nhuan_theo_hang_cat_danh_sach_...` (+ khẳng định tổng ở test theo kênh / nhóm), `AssetReportSummaryTests`.
- Chưa deploy.

## Cần người dùng quyết định
1. **Phụ thu / phí giao hàng** nằm ở đâu: (a) cộng vào «Doanh thu thuần» ở mọi báo cáo (đổi số doanh thu hiện có), hoặc (b) giữ doanh thu như cũ và thêm dòng «Phụ thu, phí giao hàng thu khách» trừ «Cước hãng tính» trong KQKD và Chi nhánh. Đề xuất (b), ít xáo trộn hơn.
2. Thêm **khấu hao tài sản** và **cọc khách bỏ** vào KQKD.
3. Nâng cấp giao diện dễ hiểu (kết luận xanh / vàng / đỏ, thác nước lãi lỗ, xếp hạng chi nhánh) như đã làm với Thuế HKD.

## Cập nhật: commit fb67a7f2 (người dùng chọn phương án b)
- Doanh thu thuần giữ nguyên (Σ Total). KQKD và Chi nhánh thêm các dòng: «Phụ thu, phí giao hàng thu khách», «Cước hãng vận chuyển tính» (gồm cước hoàn, đơn hoàn vẫn tính; bỏ đơn khách trả cước thẳng cho hãng và vận đơn hủy), «Khấu hao tài sản», «Cọc khách bỏ».
- Tính chung trong `Controllers/Reports/PosPnlExtras.cs` và `AssetValuation.PeriodDepreciation`. Phiếu chi danh mục «Mua tài sản» không tính chi phí.
- Khấu hao của chi nhánh gán theo nhân viên đang giữ tài sản; tài sản chưa giao tính cho trụ sở. Tài sản đã thanh lý / mất không khấu hao (chưa có ngày thanh lý).
- Test: backend 403/403 (Pos / Asset / Branch), Flutter `pos_pnl_branch_report_test` + `branch_view_test` 10/10. Chưa deploy.

## Deploy 17/10/2026 (người dùng yêu cầu)
- API sboxhrm từ HEAD fb67a7f2 (gồm 0a92ebe8): container mới chạy từ khoảng 13:59, healthy.
- Web sboxhrm.com build_number 1792246833: trang chủ SEO dựng đúng, main.dart.js có chữ «Cước hãng», «Khấu hao», «Cọc khách bỏ», «Biên lãi ròng».
- Không deploy sboxpos.com.
