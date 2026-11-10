# Thu chi — phát hiện phần lõi server (nháp, phiên rà Thu chi)

Gốc: `ZKTecoADMS-master/src`. Đường dẫn bên dưới tương đối từ đây.

## Đúng
- CRUD `Api/Controllers/CashTransactionsController.cs`: lọc StoreId mọi endpoint; sửa/xóa dùng AsTracking (không dính NoTracking); xóa mềm.
- Phiếu tự sinh POS bị chặn sửa số tiền / xóa / bỏ thanh toán (Conflict 409); phiếu HRM bỏ thanh toán/xóa → RevertSourceAsync hoàn chứng từ gốc + tính lại phiếu lương.
- Tổng hợp (`summary`), số dư quỹ (`fund-balances`), báo cáo POS/HKD/chi nhánh đều lọc `IsActive && Deleted==null && Status==Completed`; ngày phiếu lưu giờ VN, cộng trong CSDL.
- Quỹ: phiếu gắn TK NH vào quỹ NH, tiền mặt = Cash không gắn TK, có dòng «chưa gán TK»; chuyển quỹ kiểm đủ số dư, hủy chuyển quỹ kiểm quỹ đích.
- Mã phiếu: unique (StoreId, TransactionCode) lọc Deleted IS NULL, có retry; PosFinanceSyncHelper có RegenerateDuplicateCodesAsync dùng HashSet.
- Chặn sửa/xóa phiếu ngoài chi nhánh: BranchStockInterceptor (`Infrastructure/Interceptors/BranchStockInterceptor.cs:165-179`).

## Lỗi / thiếu
1. [TB] Mã phiếu HRM sinh ngẫu nhiên 4 ký tự hex: `CH-{yyyyMMdd}-{Guid[..4]}` — `Infrastructure/Services/PayslipPayments.cs:40`, `Application/Helpers/PayslipCashTransactionHelper.cs:98`, `Application/Commands/AdvanceRequests/AdvanceRequestCommands.cs:816`, `BusinessTrip/BusinessTripAdvanceCommands.cs:210`, `BusinessTripSettlementCommands.cs:433`. Không retry khi trùng unique index → 500. Trả lương 200 NV (tiền mặt + CK = ~400 phiếu/ngày) xác suất ≥1 lần trùng ≈ 70% (birthday 400²/2·65536). `PayrollPaymentController.Pay` (dòng 143-160) lặp từng phiếu, exception bung ra giữa vòng → một phần đã trả, client nhận lỗi 500. Ngày trong mã lấy UTC (lệch ngày VN 0–7h). Đề xuất: dùng chung GenerateCodeAsync + retry như PosFinanceSyncHelper.
2. [TB] Lộ số liệu chi nhánh khác: `ScopeByBranchAsync` (`CashTransactionsController.cs:450-457`) khi có `?branchId=` bỏ qua `AllowedBranchIds` → user giới hạn chi nhánh A gọi `summary?branchId=B`, `fund-balances?branchId=B`, `fund-transfers?branchId=B` xem được tổng thu chi / số dư quỹ của B. `GetTransaction(id)` (dòng 156-203) không ApplyBranchScope, không lọc IsActive (xem được phiếu đã xóa).
3. [TB] Duyệt / chi thưởng-phạt hàng loạt không kiểm cửa hàng: `Api/Controllers/TransactionsController.cs` bulk-approve (243-289) và bulk-pay (293-~395) không gọi `InStoreAsync`; bulk-pay nạp `PaymentTransactions` chỉ theo Ids (dòng ~309). Biết GUID phiếu cửa hàng khác → duyệt được + phiếu thu chi tạo vào cửa hàng mình. (IDOR, cần biết id.)
4. [TB] Quyền mặc định thu ngân `PermissionPresetCatalog.cs:253` `.Set(Req, "CashTransaction")` = Xem+Tạo: danh sách `GET /api/CashTransactions` không giới hạn theo nhân viên (khác `FinanceAnalyticsController` cash-transactions dòng 702+ có giới hạn) → thu ngân thấy toàn bộ sổ quỹ gồm «Chi lương T../.. – tên NV» kèm số tiền. Cần xác nhận ý đồ sản phẩm.
5. [Thấp] Sửa phiếu đã vào quỹ ghi nhật ký vào InternalNote, cắt ở 2000 ký tự (`CashTransactionsController.cs:404-408`) nhưng cột chỉ 1000 (`Infrastructure/Configurations/CashTransactionConfiguration.cs:54-55`) → khi ghi chú > 1000 ký tự lưu lỗi 500. DTO tạo/sửa không kiểm độ dài (InternalNote/Description/ContactPhone 20) → 500 thay vì 400.
6. [Thấp] Định nghĩa «đã thu/chi» không thống nhất: summary/quỹ/báo cáo POS dùng `Status==Completed`; danh sách hiển thị `IsPaid ? Completed : Status` (dòng 118); `FinanceAnalyticsController` dùng `IsPaid || Completed` (dòng ~754). Dữ liệu cũ IsPaid=true/Status=Pending hoặc `PUT {id}/status` gửi Status=Completed + IsPaid=false → 2 màn ra 2 số.
7. [Thấp] Mã phiếu tay: retry đếm lại `count+1` (dòng 295-297) — nếu trùng do mã hex HRM tình cờ là số (vd «0042») thì lần thử nào cũng ra cùng mã → 500 sau 5 lần.
8. [Thấp] `CreateCashTransactionDto.TransactionDate` mặc định `DateTime.UtcNow` (DTO dòng 74) trong khi quy ước lưu giờ VN → client bỏ trống ngày thì lệch 7h.
9. [Thiếu tính năng] Không có số dư đầu kỳ cho quỹ / TK ngân hàng (`Domain/Entities/BankAccount.cs` không có trường), số dư tính từ 0 → phải lập phiếu Thu giả, làm phồng tổng thu.
10. [Ghi chú] Server không có endpoint xuất Excel sổ thu chi (report `cash-transactions` cũng không có `format=excel`); client tự dựng Excel ở `flutter_client/lib/screens/cash_transaction_screen.dart:764`.
