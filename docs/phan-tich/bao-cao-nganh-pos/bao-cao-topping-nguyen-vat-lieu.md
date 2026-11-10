# Báo cáo: Topping và Nguyên vật liệu — SBOX POS

Commit sửa lỗi: `1c829480` (nhánh fix/tingee-agent-scope-deploy). **Chưa deploy, chưa build APK.**
Test: 5 bài mới `PosToppingStockTests` đạt; toàn bộ .NET 912/913 (1 bài lỗi có sẵn, không liên quan: `PosQuoteDocumentTests.Gia_da_gom_VAT…`). `flutter analyze` 2 app: không lỗi mới.

## 1. Bán hàng chọn topping

| Kiểm tra | Kết quả |
|---|---|
| Hộp chọn topping (bấm + để chọn nhiều phần cùng loại) | Hoạt động. Gộp topping từ mọi nhóm gắn món, không trùng. |
| Tiền topping cộng vào dòng | Đúng: (giá món + tổng topping) × số ly, làm tròn đồng — máy và server tính giống nhau. |
| Số lượng topping nhân theo số ly | Đúng (2 ly × 1 trân châu = trừ 2 phần). |
| In phiếu bếp / hóa đơn / tem ly / hóa đơn điện tử | Có hiện topping («+ Trân châu x2»); HĐĐT ghi topping trong tên món, tiền khớp. |
| Hủy đơn | Hoàn kho đúng (hoàn theo đúng những gì đã trừ). |
| Trả hàng | Hoàn kho topping theo SL trả × SL topping. |

**Lỗi đã sửa:**
1. **Topping có định lượng trừ sai kho** *(cao)*: vd «Trân châu» khai định lượng 30 g bột năng. Lúc kiểm tra tồn và giữ chỗ hệ thống tính theo **bột năng**, nhưng lúc bán lại trừ **chính «Trân châu»** (tồn âm dần) và **bột năng không hề giảm**. Trả hàng cũng cộng nhầm vào «Trân châu». → Nay bán trừ bột năng, trả hàng cộng lại bột năng.
2. **Giá topping không được kiểm tra** *(trung bình — gian lận)*: server cộng nguyên giá topping do máy bán gửi lên; gửi giá 0 là bớt được tiền topping mà không cần quyền sửa giá. → Nay giá topping phải khớp giá đang bán (giá trong nhóm topping / tùy chọn thêm, hoặc giá bán topping) hoặc giá đã có trên đơn tạm; sai thì đòi quyền sửa giá như giá món. Đơn offline đồng bộ sau không bị chặn.
3. **Bấm lại cùng món trên máy bàn/tablet** *(trung bình)*: ly thứ 2 bị **gộp vào dòng ly 1** rồi hộp topping mở ra → topping chọn cho ly 2 bị áp cho **cả 2 ly** (tính tiền 2 lần). → Món tự mở hộp topping nay mỗi lần bấm là một dòng riêng.
4. Món bật «cho chọn topping» nhưng nhóm topping đã xóa → **mỗi lần bấm món hiện cảnh báo «Chưa có topping»**. → Khi tự mở thì bỏ qua im lặng (bấm nút Topping vẫn báo).
5. Số lượng topping lỗi (0) — máy tính tiền thiếu so với server. → Thống nhất.

## 2. Gán topping cho sản phẩm

- Màn **Nhóm topping**: tạo nhóm, thêm hàng topping. Nhóm do **Nhập menu AI** tạo hiện bình thường ở đây (giá phụ thu = giá topping).
- Gắn nhóm vào món: **chỉ làm được từng món** trong màn sửa hàng hóa. **Chưa có** gắn hàng loạt theo nhóm hàng (vd gắn «Topping trà sữa» cho cả nhóm «Trà sữa») — Nhập menu AI làm được việc này tự động, còn tạo tay thì phải mở từng món.
- **Đã sửa:** giá phụ thu trong nhóm **không sửa được** (cố định giá lúc thêm) → nay bấm vào topping trong nhóm để sửa giá; ô chọn hàng mặc định **chỉ hiện hàng loại Topping** (bỏ chọn để thêm hàng khác).

## 3. Báo cáo topping

- **Hàng hóa bán ra / Lợi nhuận theo hàng**: topping **được tách thành dòng riêng** (số lượng = số ly × số phần, doanh thu = giá topping), món chính chỉ còn phần tiền của món. Đúng.
- **Đã sửa:** topping có định lượng — giá vốn nguyên liệu trước đây bị tính cho **chính nguyên liệu** (không hiện trong báo cáo hàng bán) → lợi nhuận topping bị thổi phồng; nay tính về topping.
- **Gợi ý nhập hàng** bỏ sót topping (trân châu, thạch… có theo dõi tồn) → đã thêm.
- **Còn lại (chưa sửa):** khi khách trả món có topping, giá vốn hoàn của topping bị trừ vào **món chính** (tổng lãi đơn vẫn đúng, chỉ lệch lãi từng mặt hàng). Sửa cần đổi cách ghi sổ trả hàng.
- **Chưa có báo cáo riêng cho topping** (tỷ lệ ly có topping, topping bán chạy, doanh thu topping theo món) — đang lẫn trong danh sách hàng bán.

## 4. Nguyên vật liệu (định lượng)

- Món có định lượng: bán trừ đúng nguyên liệu (SL × định mức), hủy đơn / trả hàng hoàn đúng; kiểm tra tồn & giữ chỗ khi giữ bàn theo nguyên liệu. Topping có định lượng nay cũng đúng (mục 1).
- **Hạn chế thiết kế:** định lượng gắn theo **món, không theo size** — ly L trừ nguyên liệu giống ly M (thiếu so với thực tế).
- **Chưa có báo cáo nguyên vật liệu riêng**: chỉ xem được tồn kho (chung với hàng hóa) và thẻ kho từng mặt hàng. Không trả lời được «hôm nay dùng bao nhiêu sữa, cho món nào, tốn bao nhiêu tiền», «còn đủ bột năng cho mấy ngày».

## 5. Đề xuất (cần duyệt)

1. **Báo cáo Nguyên vật liệu** (mới): theo kỳ — mỗi nguyên liệu: đầu kỳ, nhập, **dùng theo định lượng**, hủy/hao hụt, cuối kỳ, giá trị; bấm vào xem **dùng cho món / topping nào**; cột «còn đủ dùng ~N ngày» theo mức dùng bình quân. Đồ thị: cột chồng «dùng theo món» và thanh cảnh báo sắp hết (tái dùng `pos_health_widgets.dart`).
2. **Báo cáo Topping** (mới): doanh thu & số phần topping, **% ly có topping**, topping bán chạy, topping theo món; đồ thị tròn / cột ngang.
3. **Gắn nhóm topping hàng loạt** trong màn Nhóm topping: chọn nhóm hàng / món để gắn, hiện số món đang gắn.
4. **Định lượng theo size** (M/L khác nhau) — hoặc hệ số theo size.
5. Ghi sổ trả hàng tách giá vốn topping (sửa lệch lãi từng mặt hàng khi trả).

---

## 6. Đã làm cả 5 đề xuất (commit `e63ecf99`, chưa deploy, chưa build APK)

1. **Báo cáo «Nguyên vật liệu»** (menu Báo cáo POS › Hàng hóa & kho; quyền xem Tồn kho): kết luận xanh/vàng/đỏ; 6 ô chỉ số (hết/sắp hết, cần nhập trong tuần, tiền NVL đã dùng, hủy/kiểm kê thiếu, âm kho, món chưa khai định lượng); việc nên làm («Nhập ngay «Bột năng» — đủ khoảng 0,4 ngày»); đồ thị «còn đủ dùng bao nhiêu ngày», «món tốn nguyên liệu nhất», «tiền NVL theo ngày»; từng NVL bấm ra xem dùng cho món nào; danh sách món bán mà chưa khai định lượng (tồn món âm). Lượng dùng = thẻ kho định lượng, đã trừ phần hoàn khi hủy đơn / trả hàng. Xuất Excel.
2. **Báo cáo «Topping»** (menu Báo cáo POS › Bán hàng; quyền xem Hàng hóa bán ra): % ly có topping (≥ 30% xanh, 15–30% vàng, < 15% đỏ), doanh thu / lãi / biên lãi topping, thanh «có topping / không thêm», topping bán chạy (thanh màu), từng topping (cảnh báo bán lỗ, hết hàng, lãi thấp, chưa có giá vốn), theo món (món bán nhiều mà ít ai thêm topping), tỷ lệ theo ngày. Xuất Excel.
3. **Gắn nhóm topping hàng loạt**: màn Nhóm topping hiện «Gắn vào N món — bấm để sửa» / menu «Gắn vào món…» → chọn cả nhóm hàng hoặc tick từng món. Món được gắn tự bật «cho chọn topping»; món bị gỡ mà không còn nhóm / tùy chọn nào thì tự tắt.
4. **Định lượng theo size**: màn sửa hàng › Định lượng NVL có chip «Mọi size / M / L…»; size khai riêng thì dùng định lượng riêng, chưa khai dùng «Mọi size»; nút «Chép từ Mọi size để sửa» / «Bỏ định lượng riêng». Bán, giữ chỗ bàn, trả hàng, kiểm tra tồn trên máy bán đều theo đúng size. Cơ sở dữ liệu: cột `PosProductRecipeLines.VariantId` (tự thêm khi khởi động, patch `PosRecipeBySize.sql`).
5. **Tách giá vốn topping khi trả hàng**: sổ trả hàng ghi riêng giá vốn từng topping (`PosSaleReturnLines.ToppingCostJson`) → Lợi nhuận theo hàng trừ đúng vào topping, không dồn vào món.

Kiểm thử: .NET 931/932 (bài lỗi còn lại là bài báo giá có sẵn, không liên quan); bài mới `PosMaterialToppingReportTests` + `PosToppingStockTests` + `PosAiMenuServiceTests` đều đạt. Flutter: `pos_material_topping_reports_test.dart` 7/7 (dựng 2 báo cáo ở khổ điện thoại 390 px và máy tính bảng 1100 px, đã xem ảnh chụp), `pos_ai_menu_import_test.dart` 11/11. `flutter analyze` 2 app không lỗi mới. Test chụp ảnh đã bắt và sửa một lỗi giao diện thẻ NVL (nền che hiệu ứng bấm).

**Chưa thử:** trên máy thật / dữ liệu thật (chưa deploy); flutter_pos chỉ chạy phân tích mã, chưa chạy test giao diện riêng.
