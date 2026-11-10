# Báo cáo: «Tạo hàng từ ảnh menu (AI)» — SBOX POS

Commit sửa lỗi nhỏ: `37c1f14e` (nhánh fix/tingee-agent-scope-deploy). **Chưa deploy.**

## 1. Chức năng đang làm gì

1. Chủ quán chụp tối đa 8 ảnh menu → bấm «Đọc menu bằng AI».
2. AI (Gemini) đọc: **tên món, nhóm (tiêu đề mục trên menu), giá, size kèm giá, đơn vị** (Ly/Phần/Tô…), và thử ghép mỗi món với «danh mục mẫu» của SBOX để lấy ảnh có sẵn.
3. Màn xem trước: mỗi món có ô Tên / Nhóm / Giá / Size (gõ dạng «M 30.000; L 38.000»), ô tick chọn, nút bỏ ảnh. Món trùng tên với hàng đã có được bỏ chọn sẵn.
4. Bấm «Tạo N món» → tạo nhóm hàng (gộp nhóm trùng tên, không phân biệt dấu/hoa thường), tạo mặt hàng, đơn vị tính, và mỗi size thành một biến thể có giá riêng.

**Làm tốt:** đọc tên/giá/size; quy đổi «35k», «1.2tr»; gộp nhóm; không tạo trùng hàng đã có (so tên bỏ dấu: «Banh Mi» = «Bánh mì»); món có S/M/L ra đúng giá từng size; mã hàng không đụng mã cũ (kể cả hàng đã xóa).

## 2. Câu hỏi chính — có phân biệt đúng loại mặt hàng không?

**Không.** AI **không được hỏi** món đó là loại gì. Loại hàng chỉ lấy được khi món **ghép trúng một mục trong danh mục mẫu**; còn lại **tất cả thành «Hàng hóa»**.

| Loại | Kết quả hiện tại |
|---|---|
| Hàng hóa (đồ uống, món ăn) | Đúng (mặc định). |
| Dịch vụ (spa, cắt tóc, karaoke…) | Chỉ đúng nếu trùng mẫu (vd «Cắt tóc nam»). Còn lại thành **Hàng hóa có theo dõi tồn kho** → tồn = 0 → nếu cửa hàng chưa bật «cho bán âm kho» thì **bấm bán báo «hết hàng»**. |
| Dịch vụ tính giờ (karaoke, bi-a) | Không bao giờ tự thành «tính theo giờ»; giá ghi «200k/giờ» thành món giá cố định 200k. *(Đã sửa: nếu trùng mẫu dịch vụ tính giờ thì giữ cách tính giờ của mẫu.)* |
| Combo | Luôn thành Hàng hóa thường, không có thành phần (không trừ kho thành phần). Chấp nhận được tạm thời, nhưng sai bản chất. |
| Topping / món thêm | **Sai nhiều nhất.** Mục «Topping» trên menu thành các món bán lẻ riêng trên màn bán; **không tạo nhóm topping, không gắn vào trà sữa/cà phê**, món không bật «cho chọn topping». Riêng topping trùng mẫu (vd «Trân châu đen») thành loại Topping nhưng bị **ẩn khỏi màn bán** và không gắn món nào → không bán được cho đến khi tự cấu hình. Cùng một mục topping có thể nửa hiện, nửa ẩn. |
| Nguyên liệu | Không tạo (đúng — menu không có nguyên liệu). |

**Nhóm hàng:** đúng theo tiêu đề mục trên menu. **Đơn vị:** AI đoán khá hợp lý nhưng **không sửa được** ở màn xem trước (ô này bị ẩn). **Giá topping:** chỉ là giá bán món lẻ, không phải «phụ thu khi thêm vào món».

## 3. Ví dụ theo loại hình

- **Cà phê:** tốt. «Cà phê sữa M 25k / L 30k» → 1 món, 2 size đúng giá. Lưu ý: khi bán, bảng chọn size hiện thêm một lựa chọn «Ly» (= giá size nhỏ nhất) bên cạnh M/L — dễ bấm nhầm, báo cáo bị tách «Ly» và «M». *(Kết luận từ đọc mã, chưa thử trên máy thật.)*
- **Trà sữa:** món chính tốt; **topping hỏng** như bảng trên (trân châu, thạch, kem cheese thành món riêng hoặc bị ẩn, không có popup chọn topping khi bán trà sữa).
- **Spa / nail / salon:** phần lớn dịch vụ («Massage body 60 phút», «Gội đầu dưỡng sinh») thành Hàng hóa tồn kho 0 → **có thể không bán được** nếu không bật bán âm; không tính hoa hồng theo buổi, không có gói buổi.
- **Karaoke / bi-a:** giờ phòng thành món giá cố định, không đếm giờ; đồ uống/đồ ăn kèm thì ổn.

## 4. Lỗi khác tìm thấy

| # | Vấn đề | Mức | Trạng thái |
|---|---|---|---|
| 1 | Sửa giá trên màn xem trước gõ «35k» → lưu **35 đồng**; «1,2tr» → 12 đồng | Cao | **Đã sửa** (cả app quản lý và app POS) |
| 2 | Món một size mà AI để giá 0 → món giá 0 | Trung bình | **Đã sửa** |
| 3 | Một size chưa đọc được giá → **giá món = 0** và size đó giá 0 | Trung bình | **Đã sửa** (lấy size rẻ nhất có giá; size thiếu giá dùng giá món) |
| 4 | Mã hàng luôn «HH…» kể cả dịch vụ / topping (thêm tay thì DV…/TP…) | Thấp | **Đã sửa** |
| 5 | Dịch vụ trùng mẫu mất «cách tính tiền» (giờ/buổi) của mẫu | Trung bình | **Đã sửa** |
| 6 | Hai món cùng tên ở 2 nhóm (vd «Bạc xỉu» phin/máy) → món thứ 2 bị bỏ với lý do sai «đã có» | Thấp | **Đã sửa** lý do: «trùng tên trong danh sách» (vẫn chỉ tạo 1 món) |
| 7 | Món giá 0 (AI không đọc được giá) vẫn tạo, không cảnh báo | Trung bình | Chưa sửa |
| 8 | Gõ size thiếu giá («M; L 38.000») → size M **mất im lặng** | Thấp | Chưa sửa |
| 9 | Có size thì ô «Giá» bị bỏ qua dù vẫn hiện và sửa được | Thấp | Chưa sửa |
| 10 | Món đã có không cập nhật giá được (luôn bỏ qua) | Thấp | Chưa sửa (thiết kế) |
| 11 | Danh mục mẫu gửi AI lấy 600 mục đầu, không lọc theo ngành → nếu mẫu nhiều, món đồ uống có thể không được ghép ảnh | Thấp | Chưa sửa |

Test: `dotnet test --filter PosAiMenuServiceTests` 6/6 đạt; `flutter test test/pos_ai_menu_import_test.dart` 4/4 đạt.

## 5. Đề xuất (cần chủ sản phẩm duyệt — thay đổi lớn hơn)

1. **Cho AI trả thêm «loại»** (hàng hóa / dịch vụ / combo / topping) và **«tính giờ»**, kèm gợi ý theo ngành của cửa hàng; màn xem trước có ô chọn **Loại** và **Đơn vị** để sửa.
2. **Topping đúng cách:** mục topping trên menu → tạo **nhóm topping** (vd «Topping trà sữa») chứa các topping với giá phụ thu, rồi **gắn vào các món cùng menu** (bật «cho chọn topping»); màn xem trước cho chọn món nào được gắn.
3. **Dịch vụ không theo dõi tồn**: cửa hàng ngành spa/salon/karaoke mặc định dịch vụ; tối thiểu cảnh báo khi tạo hàng hóa tồn 0 mà chưa bật bán âm.
4. Cảnh báo đỏ món giá 0 / size thiếu giá trước khi tạo; bỏ lựa chọn «Ly» thừa khi món đã có size.

Ưu tiên gợi ý: (2) topping + (1) loại hàng — ảnh hưởng trực tiếp quán trà sữa và spa, hai nhóm khách hay dùng nhập menu bằng ảnh.

---

## 6. Cập nhật: đã sửa tất cả (commit `b64823ec`, chưa deploy, chưa build APK)

Người dùng duyệt «fix tất cả». Nay:

- **AI ghi luôn loại hàng** cho từng món: hàng hóa / dịch vụ / combo / topping / nguyên liệu, và với dịch vụ thì ghi **cách tính tiền**: giá cố định, theo giờ (karaoke, bi-a), theo ngày/đêm, gói buổi (kèm số buổi). AI không ghi loại thì lấy theo món mẫu.
- **Màn xem lại** có thêm: ô **Loại**, ô **Đơn vị**, ô **Tính tiền** + **Số buổi** (dịch vụ), ô **Gắn vào** (topping: tên nhóm / món, để trống = mọi món trong lần nhập), ô **Gồm các món** (combo: «Cơm gà x1; Trà đá x1»). Có size thì ô Giá khóa lại, ghi «theo size».
- **Topping:** gom theo mục trên menu thành **nhóm topping** (vd «Topping»; dùng lại nhóm cùng tên nếu đã có), giá phụ thu = giá topping; gắn vào món thuộc các nhóm ghi ở «Gắn vào» — **kể cả hàng đã có sẵn trong nhóm đó** — và bật «cho chọn topping». Topping ẩn khỏi lưới bán (đúng như topping tạo tay).
- **Combo:** gắn thành phần là món trong cùng menu hoặc hàng đã có (so tên bỏ dấu). Không tìm được món thành phần nào → tạo thành hàng hóa thường + cảnh báo (vì combo rỗng sẽ luôn báo hết hàng).
- **Cảnh báo giá:** dòng chưa có giá / size thiếu giá hiện chữ đỏ ngay dưới dòng; bấm Tạo sẽ hỏi «N món cần kiểm tra giá — Sửa lại / Vẫn tạo». Size không ghi giá (vd «XL») **không còn bị bỏ im lặng**: giữ lại, lấy giá size rẻ nhất (hoặc giá món nếu mọi size đều thiếu giá).
- **Sau khi tạo:** hiện danh sách lưu ý (món giá 0, combo thiếu thành phần, nhóm topping chưa gắn món, món bỏ qua).
- **Lựa chọn «Ly» thừa khi bán món có size:** đã bỏ. Món có size chỉ hiện các size. Phát hiện thêm khi kiểm tra: **món có size tạo tay** (dạng «M · Ly», «L · Ly») trước đây bị gộp hết thành **một** lựa chọn «Ly» — tức thu ngân không chọn được size; nay hiện đủ «M · Ly», «L · Ly». Món chỉ có đơn vị quy đổi (Lon / Thùng) giữ nguyên như cũ. *Thay đổi này ảnh hưởng mọi cửa hàng đang có món size tạo tay — nên thử trên máy thật sau khi build.*

Kiểm thử: `dotnet test --filter PosAiMenuServiceTests` 12/12 đạt; `flutter test test/pos_ai_menu_import_test.dart` 11/11 đạt; `flutter analyze` hai app không có lỗi mới. Toàn bộ bộ test .NET: 907/908 — 1 bài lỗi **không liên quan** (`PosQuoteDocumentTests.Gia_da_gom_VAT_khong_chen_dong_thue_vao_bang_tong`, phần báo giá của phiên khác).

**Chưa làm:** chưa thử trên máy C20Lite (cần build APK — chờ người dùng quyết); chưa gọi AI thật với ảnh menu (test dùng AI giả trả JSON cố định), nên độ chính xác AI phân loại cần thử bằng vài ảnh menu thật sau deploy.
