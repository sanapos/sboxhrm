# Làm gọn giao diện chứng từ bán hàng + CSKH — phân tích (phiên «gọn giao diện chứng từ»)

Ảnh hiện trạng (web QA, TK Restaurant): thư mục `cskh-anh/` cạnh file này.

## File liên quan (flutter_client)
- `screens/pos/pos_quote_detail_screen.dart` — chi tiết báo giá (thẻ tiến độ + nút bước, hàng Gọi/Zalo/Gửi PDF/Chăm sóc, menu ⋮).
- `screens/pos/pos_contract_detail_screen.dart` — hồ sơ hợp đồng (Xem/in HĐ, Tạo trọn bộ, thu tiền, Hồ sơ liên quan, 3 nút + chứng từ, menu ⋮ mỗi chứng từ ~20 mục).
- `screens/pos/pos_quote_list_screen.dart` — danh sách + 4 tab + bảng thao tác (đã chia nhóm có chữ).
- `utils/pos_quote_commercial.dart` — `_askCommercialNote`: hộp «Ghi chú chứng từ (tuỳ chọn)» trước MỖI lần lập chứng từ / trọn bộ.
- `widgets/pos/pos_quote_care_sheet.dart` (từ dòng ~758) — sheet Lịch CSKH. Phần trên file (mẫu in) là của phiên mẫu in.
- `screens/pos/pos_quote_care_board_screen.dart` — bảng theo dõi + báo cáo theo nhân viên.
- Máy chủ: `PosQuotesController.Activities.cs` (activities CRUD, customer-history, care-overview, care-staff, customer-care). Chưa có API nhật ký CSKH toàn cửa hàng theo khoảng ngày.

## Ghi chú chứng từ
- Hỏi: `_askCommercialNote` (lập HĐ / đề nghị TT / bàn giao / nghiệm thu / xuất kho / trọn bộ). Giao diện cũ `pos_quote_editor_screen.dart` có `_askNote` riêng.
- Lưu: `PosQuoteDocument.Note`. Không có API sửa sau khi lập.
- Hiện: chỉ trên bản in — `{Ghi_Chu}` = ghi chú báo giá + ghi chú HĐ + ghi chú chứng từ (dòng «Ghi chú: …» cuối mẫu A4). Trong app không chỗ nào hiện `doc.note`.

## Thông báo nhắc hẹn CSKH bấm vào sai chỗ (03/11, phân tích)
- Máy chủ `PosQuoteFollowUpReminderBackgroundService`: relatedEntityType="PosQuote", relatedEntityId=quoteId, category "pos", không có url.
- App `utils/notification_navigation.dart`: không có case 'posquote' → rơi xuống nhánh category 'pos' → 'PosSaleOrder' → mở «Hóa đơn bán hàng». Cùng lỗi: "PosReportExpiry" («Cảnh báo hạn sử dụng»).
- Thông báo trên thanh Android (showGeneral) payload thiếu categoryCode/actionUrl → cùng thông báo, bấm từ thanh đi chỗ khác bấm từ danh sách.
- Shell POS riêng / Staff: popup không có onTap; PendingNotificationLaunch chỉ chờ MainLayout → bấm đẩy không đi đâu.
- Màn báo giá chưa đọc notificationHighlightId (chưa có cơ chế mở chi tiết theo id).
- 04/11 09:22: ĐÃ lên web sboxhrm.com, dựng từ f932417c + 18ffc593 + 879d1e16 (không kéo BOSS / KDS / các commit khác trên HEAD). Nhánh chưa push.
- ĐÃ SỬA commit 879d1e16: utils/notification_open_screens.dart (mở báo giá + sheet / báo cáo HSD), MainLayout mã giả 'PosQuoteDetail', notificationShellHandler cho shell POS riêng / Staff. Thử web QA: bấm nhắc hẹn → BG291020260003 + sheet chăm sóc; bấm «Cảnh báo hạn sử dụng» → Hàng sắp hết hạn.

## flutter_pos (T1)
Bản cũ tách nhánh (không có pos_quote_detail_screen). Hàm `_askCommercialNote` giống → áp được phần bỏ hộp ghi chú.

## Đã làm (commit cd355a64, chưa push / deploy)
- Gom nút báo giá / hợp đồng / danh sách, bỏ hộp hỏi ghi chú, ghi chú in sửa được (PUT documents/{docId}/note).
- CSKH: dòng thời gian, thẻ chăm sóc trên báo giá / HĐ, màn «Báo cáo chăm sóc khách» (GET care-log).
- flutter_pos chỉ bỏ hộp ghi chú.
- 01/11 ~22h: ĐÃ lên production sboxhrm.com (HEAD bccb9258). API do một phiên khác deploy từ E:\gtmp\deploy-wt (care-log, documents/{id}/note trả 401 = có route); web do phiên này build từ worktree sạch + render SEO. sboxpos.com (máy chủ riêng, bản 17/10) chưa cập nhật.
