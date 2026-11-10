# Báo cáo rà soát chức năng Thu chi — SBOX (01/11/2026)

Chỉ đọc code, CHƯA sửa gì, chưa chạy thử trên QA. Đường dẫn server tính từ `ZKTecoADMS-master/src/`, client từ `ZKTecoADMS-master/`.
Mỗi lỗi mức Cao đã được đọc lại trực tiếp trong code. Các mức TB/Thấp do agent rà, mới kiểm lại một phần.
Bản nháp phần lõi: `thu-chi-core-draft.md` (cùng thư mục).

## Kết luận nhanh
Phần lõi Thu chi đã đúng: CRUD, tổng hợp, số dư quỹ, chuyển quỹ, khóa phiếu tự sinh, đồng bộ bán offline không trùng, trả lương nhiều lần.
Hệ thống **chưa đúng hoàn toàn**: có **7 lỗi làm sai tiền thật** (sổ quỹ lệch, hoặc nhân viên nhận tiền 2 lần), nằm ở 3 nhóm:
- Đơn online, COD và hoàn tất đơn nháp.
- Hủy, hoàn duyệt thưởng/phạt và ứng lương (lỗi NoTracking).
- Tiền ca thu ngân.

Ngoài ra trên C20 và điện thoại, danh sách Thu chi chỉ hiện 20 phiếu đầu.

## Đã đúng
- `Api/Controllers/CashTransactionsController.cs`:
  - Mọi endpoint lọc theo StoreId.
  - Sửa, xóa, đổi trạng thái dùng AsTracking; xóa là xóa mềm.
  - Phiếu tự sinh từ bán hàng (POS): bị chặn sửa số tiền, xóa, bỏ thanh toán (trả 409).
  - Phiếu tự sinh từ nhân sự: bỏ thanh toán hoặc xóa thì chứng từ gốc quay về «chưa thanh toán» (`CashSourceRevert`, `PayslipPayments.SyncForVoucherAsync`).
- Các con số tổng: `summary`, `fund-balances`, báo cáo POS/HKD/chi nhánh đều lọc `IsActive && Deleted==null && Status==Completed` và cộng trong CSDL. Ngày phiếu thống nhất lưu giờ VN.
- Quỹ:
  - Phiếu gắn tài khoản ngân hàng thì tính vào quỹ ngân hàng đó.
  - Tiền mặt gồm phiếu Tiền mặt không gắn tài khoản.
  - Có dòng riêng cho phiếu chưa gán tài khoản.
  - Chuyển quỹ và hủy chuyển quỹ đều kiểm đủ số dư.
- Bán hàng:
  - Hoàn tất và hủy đơn giành trạng thái đơn bằng `ExecuteUpdate`, nên không ghi 2 lần.
  - Đơn offline chống trùng bằng unique index `OfflineNo` và `ClientRequestId`.
  - Nhiều phương thức thanh toán thì mỗi phương thức một phiếu; tiền thừa được cắt, cọc được trừ.
  - Mọi chỗ hủy phiếu phía bán hàng đều đã AsTracking.
- Nhân sự:
  - Trả lương: mỗi phương thức một phiếu; trả một phần hoặc chốt lại thì tính lại đúng; không cho trả vượt số còn lại.
  - Ứng lương không bị chi 2 lần qua lương.
  - DB có unique index `UX_CashTransactions_HrmSource`.
- Chi nhánh: `BranchStockInterceptor` chặn sửa/xóa phiếu ngoài chi nhánh. Header `X-Branch-Id` làm danh sách, tổng hợp và số dư quỹ khớp nhau.
- Client:
  - Đường dẫn, tên trường và enum khớp server.
  - Ô tổng lấy từ server, không cộng theo trang.
  - Form khóa các trường của phiếu tự sinh.
  - Quyền ngầm BankAccount ↔ CashTransaction khớp server.

## Lỗi mức CAO (sai tiền)
| # | Lỗi | Vị trí | Tái hiện | Đề xuất |
|---|---|---|---|---|
| C1 | Đơn online COD ghi **phiếu thu tiền mặt đủ tiền ngay lúc hoàn tất**, chưa thu tiền thật. Lúc đối soát COD thấy đơn hết nợ nên không ghi phiếu tiền hãng chuyển về. | `Api/Services/PosOnlineOrderHelper.cs:98` truyền 0 nhưng `:123` `paid = paidAmount > 0 ? paidAmount : due` | Xác nhận đơn online COD → quỹ tiền mặt và ca thu ngân +đủ tiền đơn | COD hoàn tất với PaidAmount = 0, không sinh phiếu bán; ghi tiền lúc đối soát COD |
| C2 | `POST /sales/{id}/complete` gộp mọi phương thức vào **một phiếu**, mất tài khoản ngân hàng | `Api/Controllers/PosSalesController.Draft.cs:1103-1108` | Nháp 500k tiền mặt + 500k CK → hoàn tất → 1 phiếu 1.000k «Chuyển khoản, chưa gán TK»; quỹ tiền mặt và ca thiếu 500k | Lưu chi tiết thanh toán của nháp, hoặc chặn hoàn tất khi phương thức là chuỗi gộp |
| C3 | Tiền ca tính theo `CreatedAt` và người ghi sổ: (a) hủy đơn của ca trước không sinh phiếu chi trong ca hiện tại; (b) đơn offline đồng bộ muộn rơi sang ca khác | `Api/Controllers/PosShiftCashHelper.cs:55-59` | Hủy đơn tiền mặt của hôm qua rồi trả tiền khách từ két → ca báo thiếu | Hủy đơn đã thu thì tạo phiếu chi hoàn (giờ hiện tại); phiếu offline lấy giờ `OfflineAt` |
| C4 | Hoàn duyệt ứng lương **không hủy phiếu chi chờ** (NoTracking: phiếu được đọc không track nên thay đổi không lưu) | `Api/Controllers/AdvanceRequestsController.cs:309-314`; gốc ở `Infrastructure/Services/PaymentFinanceHelper.cs:150-166` (`ResolveLinkedAsync`), DbContext NoTracking ở `Infrastructure/DependencyInjectionExtensions.cs:75` | Duyệt 5tr → hoàn duyệt → phiếu vẫn chờ → kế toán vẫn chi được, lương không trừ. Duyệt lại 3tr thì vẫn dùng phiếu 5tr | `ResolveLinkedAsync` dùng AsTracking (sửa 1 chỗ, hết C4+C5). Khi chi, gán lại `Amount = ApprovedAmount` |
| C5 | Thưởng/phạt: hủy, hoàn duyệt, xóa, chi hàng loạt **không ghi phiếu thu chi** (cùng lỗi NoTracking) | `Api/Controllers/TransactionsController.cs:157-168`, `:214-219`, `:325-329` | Hủy thưởng → phiếu chi chờ vẫn còn và chi được. Chi hàng loạt → khoản thưởng ghi đã trả nhưng phiếu vẫn chờ | Như C4 |
| C6 | Bỏ thanh toán hoặc xóa phiếu của thưởng tiền mặt → `PaymentMethod = null`, mà null nghĩa là «tính vào lương» → **nhân viên nhận 2 lần** | `Infrastructure/Services/CashSourceRevert.cs:75-83` + `Api/Controllers/HrFinanceController.cs:199-201` | Thưởng tiền mặt 1tr → bỏ đánh dấu đã chi → bảng lương cộng 1tr, phiếu chi chờ vẫn còn → chi lần nữa | Thưởng tiền mặt (Settlement=cash) giữ `"Cash"`, không đặt null |
| C7 | C20, điện thoại, cửa sổ thấp (<720): danh sách Thu chi **chỉ hiện 20 phiếu**, không có phân trang hay tải thêm | `flutter_client/lib/screens/cash_transaction_screen.dart:884-890` (phân trang chỉ ở `desktopBody`), `:1289` | Tháng có >20 phiếu, mở Thu chi trên C20 → không xem được phiếu cũ hơn | Thêm tải thêm khi cuộn, hoặc sliver phân trang cho nhánh mobile |

## Lỗi mức TRUNG BÌNH
**Server — tiền và dữ liệu**
- T1 — Mã phiếu nhân sự dạng `CH-yyyyMMdd-<4 ký tự hex ngẫu nhiên>`:
  - Vị trí: `Infrastructure/Services/PayslipPayments.cs:40`, `Application/Helpers/PayslipCashTransactionHelper.cs:98`, `Application/Commands/AdvanceRequests/AdvanceRequestCommands.cs:816`, `Application/Commands/BusinessTrip/BusinessTripAdvanceCommands.cs:210`, `BusinessTripSettlementCommands.cs:433`.
  - Không thử lại khi trùng unique index (StoreId, TransactionCode).
  - Trả lương ~200 NV (tiền mặt + CK) trong một ngày: xác suất có ít nhất một lần trùng khoảng 70%. Khi trùng, `PayrollPaymentController.Pay` (`:143-160`) văng lỗi 500 giữa vòng lặp, một phần nhân viên đã được trả.
  - Ngày trong mã lấy theo UTC.
  - Đề xuất: dùng chung `PosFinanceSyncHelper.GenerateCodeAsync` + `RegenerateDuplicateCodesAsync`.
- T2 — Ứng lương: bỏ thanh toán hoặc xóa phiếu chi ứng ở màn Thu chi không bị chặn khi kỳ lương đã chốt (`CashTransactionsController.cs:441-444, 638` → `CashSourceRevert.cs:25-35`). Kết quả: ứng về «chưa chi» trong khi lương đã trừ.
- T3 — Trả lương, chi ứng, chi công tác: bấm 2 lần hoặc gửi song song thì phần chuyển khoản sinh 2 phiếu. Không có khóa (`PayslipPayments.cs:165-223`).
- T4 — Phiếu lập tay có thể «trả» phiếu lương hoặc ứng lương: chỉ cần ghi chú chứa «phiếu lương #<id>» hoặc «yêu cầu ứng lương #<id>» (`PayslipPayments.cs:34, 71-75`, `CashTransactionLinkageHelper.cs:47, 100`). Đề xuất: loại `SourceType == manual`.
- T5 — Dư ứng công tác có thể bị thu 2 lần khi đổi phương án từ «thu hoàn» sang «ghi nợ»: phiếu thu chờ không bị hủy (`BusinessTripCasesController.cs:267-290`).
- T6 — Hủy hoặc hoàn duyệt phiếu phạt đã thu tiền vẫn hủy phiếu thu, không tạo chứng từ hoàn (`PenaltyTicketsController.cs:377-380, 785-788`, `AttendanceCorrectionPenaltyHelper.cs:29-42`). Hủy phiếu phạt cũng không hủy khoản phạt chấm công liên kết (NoTracking, `PenaltyTicketsController.cs:858-873`).
- T7 — Bán hàng:
  - Hoàn tất đơn online gán lại `PaidAmount`/`PaymentMethod` SAU khi phiếu đã sinh (`PosQrTableOrderController.cs:1452-1461`).
  - Thu cọc đặt chỗ không chống bấm 2 lần (`PosFinanceSyncHelper.cs:124`, `PosSellIndustryController.Reservations.cs:842-877`).
  - Thu nợ khách không chống gửi lại, và không có cách hủy phiếu thu nợ hay trả nợ NCC ngoài phiếu (`PosCustomersController.Debt.cs:41-80`).
- T8 — Phương thức thanh toán sai:
  - Nhập hàng và NCC hoàn tiền luôn ghi Tiền mặt (`PosFinanceSyncHelper.cs:279, 501`).
  - Trả NCC, khách trả hàng, COD, Tingee không gắn `BankAccountId`, nên tiền rơi vào «chưa gán TK».
  - Trả hàng và hoàn cọc lấy phương thức gộp của đơn (`PosSalesController.cs:2645-2647`, `PosFinanceSyncHelper.cs:188`).
- T9 — Lọt dữ liệu và quyền:
  - Lọt dữ liệu giữa cửa hàng (cần biết GUID): `TransactionsController.cs` bulk-approve (`:243-291`) và bulk-pay (`:293-313`) không gọi `InStoreAsync`. Bulk-approve còn cho tự duyệt khoản của mình.
  - Lọt dữ liệu giữa chi nhánh: `?branchId=` ở `summary`, `fund-balances`, `fund-transfers` bỏ qua `AllowedBranchIds` (`CashTransactionsController.cs:450-467`). `GET {id}` không lọc chi nhánh và vẫn xem được phiếu đã xóa.
  - Mẫu quyền thu ngân `PermissionPresetCatalog.cs:253` có quyền Xem Thu chi. Danh sách không giới hạn theo người, nên thu ngân thấy «Chi lương T../.. – tên NV – số tiền» của cả cửa hàng. Cần chốt ý đồ sản phẩm.

**Client**
- T10 — Sửa phiếu làm mất `paymentReference`, `receiptImageUrl`, `tags`: form không gửi 3 trường này, server ghi đè toàn bộ (`cash_transaction_screen.dart:2872-2884`). Ví dụ phiếu chi lương CK mất mã tham chiếu.
- T11 — In phiếu dùng `paidDate` (UTC, parse như giờ local) thay cho `transactionDate`, nên lệch 7 giờ hoặc sai ngày (`flutter_client/lib/utils/cash_voucher_print.dart:15`).
- T12 — Nút «Thu tiền/Thanh toán/Hủy» hiện cho người chỉ có quyền Duyệt, nhưng server đòi quyền Sửa → lỗi 403 (`cash_transaction_screen.dart:1714, 2103` và `CashTransactionsController.cs:487`).
- T13 — Dòng tổng Excel cộng cả phiếu Hủy và Chờ (`:809-819`). Ô «Chờ thu/chi» đếm mọi thời gian, nhưng bấm vào lại lọc theo kỳ và `WaitingPayment`, nên danh sách không khớp số (`:1533-1555`).
- T14 — flutter_pos: nút «Tạo phiếu thu & In» không in (`flutter_pos/.../pos_cash_voucher_dialog.dart:143-147`). Không có link mở chứng từ gốc từ phiếu tự sinh. Không có chỗ đính kèm ảnh chứng từ (`ReceiptImageUrl` luôn null).

## Lỗi mức THẤP
- InternalNote: nhật ký sửa cắt ở 2000 ký tự trong khi cột chỉ 1000 (`CashTransactionsController.cs:404-408` và `CashTransactionConfiguration.cs:54`). DTO không kiểm độ dài, nên vượt giới hạn trả 500 thay vì 400.
- Định nghĩa «đã thu» không thống nhất: summary và quỹ dùng `Status==Completed`; danh sách hiển thị theo `IsPaid`; `FinanceAnalyticsController` cash-transactions dùng `IsPaid || Completed`. Hủy lần thu hợp đồng chỉ đổi Status, còn IsPaid=true (`PosQuotesController.Contract.cs:261-267`), nên danh sách vẫn hiện «Hoàn thành».
- `CreateCashTransactionDto.TransactionDate` mặc định là `DateTime.UtcNow`, lệch quy ước giờ VN.
- Phiếu Hủy vẫn sửa được và bật «Đã thanh toán» thì sống lại. Phiếu POS tự sinh vẫn đổi được phương thức và tài khoản.
- `flutter_pos/lib/models/cash_transaction.dart`:
  - Đọc `contactphone` (sai tên trường).
  - Thiếu `sourceType`.
  - VietQR dùng `toInt()` thay cho `round()`, nên số tiền trong QR lệch 1đ với số trên màn hình.
- Hub tài chính nhân sự đếm trên 100 phiếu đầu. `payCash` chọn CK nhưng không gửi `bankAccountId`.
- Chưa có số dư đầu kỳ cho quỹ/TK ngân hàng: số dư tính từ 0, phải lập phiếu Thu giả.
- Chốt lương: một nhân viên lỗi lưu làm hỏng các nhân viên sau (`FinalizePayrollCommand.cs:155`, thiếu `ChangeTracker.Clear()`).
- `/api/BankAccounts/vietqr-banks` yêu cầu Manager, nên nhân viên có quyền TK ngân hàng không tải được danh sách ngân hàng.
- i18n: nhiều `tr()` chứa biến nội suy.

## Đã sửa (01/11/2026, chưa commit, chưa deploy)
- C4 + C5: `Infrastructure/Services/PaymentFinanceHelper.cs` `ResolveLinkedAsync` dùng AsTracking cho cả 2 truy vấn. Các nơi gọi đã kiểm: helper chạy sau `mediator.Send`; `EfRepository.UpdateAsync` xử lý được thực thể đang track; `HrFinanceController` có kiểm Detached.
- C4: `Application/Commands/AdvanceRequests/AdvanceRequestCommands.cs` (PayAdvanceRequestHandler) gán `pendingCashTx.Amount = payoutAmount` khi chi.
- C6: `Infrastructure/Services/CashSourceRevert.cs` chỉ đưa thưởng/phạt về bảng lương (`PaymentMethod = null`) khi phiếu chi đã xóa, hủy hoặc IsActive=false. Bỏ «đã chi» mà phiếu vẫn chờ thì giữ «Cash».
- Test mới trong `ZKTecoADMS.Tests/HrFinanceTests.cs`: `Cancel_linked_voucher_after_resolve_is_saved_under_no_tracking`, `Unpay_cash_bonus_keeps_it_out_of_payroll_until_voucher_is_gone`. Kết quả chạy các bộ HrFinance, PayrollPayment, CashSource, PenaltyAutoApprove, CashbookImplicitGrant: 46/46 đạt.
- `PenaltyTicketFinanceHelper.ResolveLinkedCashTransactionAsync` giữ nguyên, vì mọi nơi gọi đã `dbContext.Update(linkedCash)`.
- C1 (`Api/Services/PosOnlineOrderHelper.cs`, `Api/Controllers/PosQrTableOrderController.cs`):
  - `TryCompleteAsCodAsync` nhận thêm `collected`. Chưa thu → PaidAmount = 0, không sinh phiếu bán. `TryCompletePaidDraftAsync` đổi `paidAmount` thành `decimal?` (null = đủ tiền, 0 = chưa thu).
  - Tự hoàn tất lúc xác nhận (OnlineAutoPay): chưa thu.
  - «Giao thành công» khi đơn còn nháp: có vận đơn hãng → chưa thu (ghi lúc đối soát COD); giao nội bộ / không vận đơn → thu tiền mặt đủ.
  - «Giao thành công» khi đơn đã hoàn tất COD chưa thu, giao nội bộ: hàm mới `CollectCodOnDeliveredAsync` ghi một phiếu thu tiền mặt (bỏ qua đơn có khách công nợ, thu qua «Thu nợ»).
  - `POST online-orders/{id}/complete`: gửi PaidAmount thì phiếu thu ghi đúng số / phương thức đó; trước đây ghi phiếu đủ tiền mặt rồi mới ghi đè PaidAmount trên đơn. Endpoint này hiện không có màn nào gọi.
  - `TryCreateShipmentAsync`: COD = phải trả − đã trả, truyền null để dịch vụ tự trừ cước khi khách trả cước. Trước đây đơn đã hoàn tất luôn COD = 0, nên đơn tự hoàn tất lúc xác nhận giao hãng mà hãng không thu tiền khách.
- C2 (`Api/Controllers/PosSalesController.Draft.cs`, `PosSalesController.cs`): `POST /sales/{id}/complete` trả 400 khi đơn tạm có PaidAmount > 0 và phương thức gộp («A + B»), yêu cầu mở đơn ở màn bán và thanh toán lại. Thanh toán ở màn bán gửi `payments` nên ghi đúng từng phiếu. Còn hở: đơn tạm một phương thức chuyển khoản vẫn mất BankAccountId, phiếu vào «chưa gán tài khoản» (cần thêm cột lưu chi tiết thanh toán nháp).
- Test mới `ZKTecoADMS.Tests/Pos/PosOnlineCodCashTests.cs` (5 test, PostgreSQL thật).
- 09/11/2026: kiểm lại thấy C1–C6 còn nguyên trong code và đã commit (b0f46f74, 84394a84). C3, C7, T1 chưa sửa.
- C7 (`flutter_client/lib/screens/cash_transaction_screen.dart`): nhánh mobile thêm thanh phân trang (dùng lại `_buildPaginationControls`) ở cuối danh sách. Phân tích Dart không có lỗi / cảnh báo mới. Chưa chạy thử trên C20.
- T1: hàm chung `Application/Helpers/HrmVoucherCode.New` — «CH-yyyyMMdd-XXXXXXXX», ngày giờ VN, đuôi 8 ký tự hex. Thay ở `PayslipPayments`, `PayslipCashTransactionHelper`, `AdvanceRequestCommands`, `BusinessTripAdvanceCommands`, `BusinessTripSettlementCommands`. Test `Hrm_voucher_codes_use_vn_date_and_do_not_collide_in_a_payroll_run`. Chạy 79 test (HrFinance, PayrollPayment, Advance, BusinessTrip, CashSource, POS COD/hoàn tất, đối soát): đạt hết.
- C3 (người dùng đồng ý cách làm 09/11/2026):
  - `Infrastructure/Services/PosFinanceSyncHelper.ReverseSaleOnCancelAsync` nhận thêm `refundByUserId`. Phiếu thu của ngày VN trước, hoặc nằm trong ca thu ngân đã đóng của người ghi → giữ nguyên, lập phiếu chi «Hoàn tiền hủy đơn» lúc hủy, do người hủy ghi, cùng phương thức / tài khoản ngân hàng. InternalNote `pos trả khách #<đơn>|HUY|<phiếu thu>`, nguồn `pos_customer_return`, nên tiền ca, cuối ngày, đối soát tính là tiền hoàn. Phiếu thu trong ngày, ca chưa đóng → hủy như cũ. Hệ thống tự hủy (vận chuyển hoàn hàng, không người) → hủy như cũ.
  - Nơi gọi truyền người hủy: `PosSalesController.CancelSale`, `PosQrTableOrderController` (hủy đơn online, xóa đơn online đã thanh toán).
  - `CashReconcileController`: đơn đã hủy mà phiếu thu − phiếu hoàn = 0 thì không báo «phiếu thu còn hiệu lực».
  - `PosShiftCashHelper`: phiếu thu của đơn offline tính theo `OfflineAt` (giờ bán), không theo giờ đồng bộ. Lấy thêm phiếu bán hàng sinh tới 7 ngày sau khi ca đóng.
  - Ca đã đóng giữ `ExpectedCash` đã lưu lúc đóng; chỉ phần chi tiết tính lại.
  - Còn hở: báo cáo cuối ngày lọc theo đơn hoàn tất, nên xem lại ngày cũ thì đơn đã hủy vẫn biến mất khỏi «tiền bán» của ngày đó (như trước).
  - Test `ZKTecoADMS.Tests/Pos/PosShiftCashCancelTests.cs` (4 test). Chạy toàn bộ test POS + thu chi: 682/682 đạt.
- Đã commit trên nhánh `fix/tingee-agent-scope-deploy` (chưa push, chưa deploy): C7 `7a20d5b0`, T1 `48e9cef9`, C3 `6f49c6ec`.

## Đề xuất thứ tự sửa
1. **C4 + C5**: thêm AsTracking cho `PaymentFinanceHelper.ResolveLinkedAsync` và `PenaltyTicketFinanceHelper.ResolveLinkedCashTransactionAsync`. Một thay đổi nhỏ, sửa được nhiều luồng.
2. **C6**: một dòng trong `CashSourceRevert`.
3. **C1, C2**: COD và hoàn tất nháp. Sửa server, cần test bán hàng.
4. **C7**: phân trang nhánh mobile.
5. **T1**: mã phiếu nhân sự.
6. **C3**: tiền ca. Đây là thay đổi nghiệp vụ, cần chốt cách làm: hủy đơn ca trước thì tạo phiếu chi hoàn, đơn offline lấy giờ bán.
7. Các mục TB/Thấp còn lại.

Sau mỗi nhóm nên viết test vào `ZKTecoADMS.Tests` (đã có `HrFinanceTests`, `PayrollPaymentTests`, `CashSourceTests`) và chạy thử trên QA local (`scripts/run-qa-api.ps1`).
