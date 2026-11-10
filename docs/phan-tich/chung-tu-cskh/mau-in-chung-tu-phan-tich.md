# Mẫu in chứng từ POS (báo giá / HĐ / đề nghị TT / bàn giao / nghiệm thu) — xem trước vs bản xuất

## Luồng dựng
- Nội dung: máy chủ `POST /api/pos/quotes/{id}/preview` → `PosQuoteDocumentHtml.BuildAsync` (mẫu cửa hàng hoặc
  `src/ZKTecoADMS.Api/PrintTemplates/A4/*.html`) → `PosPrintTemplateHtmlRenderer.Render` bọc vỏ máy chủ
  (`@page margin:12mm`).
- App (`posQuoteServerDocument`, `pos_quote_care_sheet.dart`) bỏ vỏ máy chủ, bọc lại bằng
  `wrapPosCommercialPrintHtml` (`@page margin:0` + body padding = lề mẫu + `posCommercialContentCss`).
- Xem trước: `showPosHtmlPrintDialog(a4Paper:true)` → `buildPosHtmlPreview`:
  - web: iframe 794×1123, một dải liền, không ngắt trang (trang 2 phải cuộn trong iframe);
  - Android (C20 / điện thoại): flutter_html (`pos_html_preview_stub.dart`) tự dựng — cỡ chữ / giãn dòng / lề
    ô bảng / ngắt trang khác Chromium.
- Xuất: In / Xuất PDF / gửi khách = HTML đã bọc của app → `POST /quotes/{id}/export/pdf` (Chromium);
  Word = `GET /export/file?format=docx` (HTML vỏ máy chủ → LibreOffice); mẫu Word cửa hàng → LibreOffice.
- Lệch: xem trước là trình dựng khác (flutter_html / iframe không phân trang); PDF thật do Chromium phân trang.
  Thêm: vỏ app `@page margin:0` → trang 2+ của PDF sát mép trên (chỉ trang 1 có lề trên).
  `export/file?format=pdf` theo vỏ máy chủ bị tràn lề phải (app chỉ gọi khi có mẫu Word nên ít gặp).

## Kết quả
- Commit `62c3e46b` trên nhánh fix/tingee-agent-scope-deploy (chưa push, chưa deploy).
- Ảnh so sánh xem trước (trái, trong app web) ↔ PDF «Xuất PDF» tải từ app (phải): `mau-in-anh/SBS_*.png`;
  3 kiểu báo giá không VAT / cộng VAT / đã gồm VAT: `mau-in-anh/VAT_3_kieu.png`.
- Test: PosQuoteDocumentTests 14/14 (PG thật), Flutter pos_commercial_* 15/15.
- Chưa sửa: `GET /export/file?format=pdf` theo vỏ máy chủ (@page 12mm) tràn lề phải — app chỉ gọi khi có mẫu Word.
- `pos_contract_detail_screen.dart` có phiên khác đang viết lại menu chứng từ — chỉ commit 2 hunk a4Paper.

## Sửa (phiên mẫu in)
- Hộp xem trước A4 hiện chính file PDF máy chủ dựng (raster từng trang), In dùng đúng file đó; mất mạng → HTML cũ.
- Vỏ app: `@page` mang lề mẫu, body padding chỉ khi xem trên màn hình → trang 2+ có lề.
- Mẫu báo giá tách có / không VAT (rev 3).
