using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Sửa / xóa / hủy thay người dùng: xóa phiếu nhân sự, thu chi, hàng hóa, khách, NCC, khuyến mãi; hủy hóa đơn và
/// chứng từ kho đã hoàn thành (API tự đảo tồn kho, sổ quỹ, công nợ); đổi giá / ngừng bán hàng; sửa thông tin khách / NCC.
/// Xóa và hủy là RỦI RO CAO: thẻ đỏ, xác nhận hai lần, không hoàn tác. Mỗi loại kiểm quyền Xóa / Sửa / Duyệt riêng
/// và phạm vi nhân sự (phiếu của nhân viên ngoài phạm vi không đụng được).
/// </summary>
public sealed partial class AiAssistantActions
{
    const string DeleteModule = "@delete";
    const string CancelModule = "@cancel";
    const string ContactModule = "@contact";

    static readonly Dictionary<string, KindRule> DeleteKinds = new()
    {
        ["penalty"] = new("Phiếu phạt", "PenaltyTickets", 'D'),
        ["reward"] = new("Phiếu thưởng", "BonusPenalty", 'D'),
        ["cash"] = new("Phiếu thu / chi", "CashTransaction", 'D'),
        ["advance"] = new("Yêu cầu ứng lương", "AdvanceRequests", 'D'),
        ["leave"] = new("Đơn nghỉ phép", "Leave", 'D'),
        ["attendance_fix"] = new("Phiếu bổ sung chấm công", "AttendanceCorrection", 'D'),
        ["overtime"] = new("Đăng ký tăng ca của bạn", "Overtime", 'D'),
        ["product"] = new("Hàng hóa", "PosProducts", 'D'),
        ["customer"] = new("Khách hàng", "PosCustomers", 'D'),
        ["supplier"] = new("Nhà cung cấp", "PosProducts", 'D'),
        ["promotion"] = new("Chương trình khuyến mãi", "PosPromotions", 'D'),
        // API xóa voucher yêu cầu quyền Sửa hàng hóa (không phải Xóa) — theo đúng API.
        ["voucher"] = new("Mã giảm giá (voucher)", "PosProducts", 'E'),
    };

    static readonly Dictionary<string, KindRule> CancelKinds = new()
    {
        ["sale_order"] = new("Hóa đơn bán", "PosSellCancelPaid", 'A'),
        ["purchase_receipt"] = new("Phiếu nhập kho", "PosPurchaseReceipts", 'E'),
        ["purchase_return"] = new("Phiếu trả hàng NCC", "PosPurchaseReturns", 'E'),
        ["stock_count"] = new("Phiếu kiểm kho", "PosStockCounts", 'E'),
        ["damage_issue"] = new("Phiếu xuất hủy", "PosDamageIssues", 'E'),
        ["internal_use"] = new("Phiếu xuất dùng nội bộ", "PosInternalUseIssues", 'E'),
    };

    static readonly Dictionary<string, KindRule> ContactKinds = new()
    {
        ["customer"] = new("Khách hàng", "PosCustomers", 'E'),
        ["supplier"] = new("Nhà cung cấp", "PosProducts", 'E'),
    };

    /// <summary>Loại chứng từ find_records tra được.</summary>
    static readonly string[] RecordKinds =
    [
        "penalty", "reward", "cash", "advance", "overtime", "leave", "attendance_fix",
        "purchase_receipt", "purchase_return", "stock_count", "damage_issue", "internal_use", "promotion", "voucher",
    ];

    static readonly Def[] ManageDefs =
    [
        new("propose_delete", DeleteModule, 'D', false,
            "XÓA (hoặc hủy nếu chứng từ đã duyệt) một bản ghi. Khách / NCC đã có giao dịch thì chuyển sang ngừng theo dõi. "
            + "Lấy id bằng find_records / find_products / find_customers / find_suppliers.",
            new()
            {
                ["kind"] = ("STRING", "Loại"),
                ["record_id"] = ("STRING", "Id bản ghi"),
                ["reason"] = ("STRING", "Lý do"),
            }, ["kind", "record_id"]),
        new("propose_cancel_document", CancelModule, 'E', false,
            "HỦY chứng từ đã hoàn thành (hóa đơn bán, nhập kho, trả NCC, kiểm kho, xuất hủy, xuất nội bộ) — tự đảo tồn kho, "
            + "sổ quỹ, công nợ. Hóa đơn: find_orders; phiếu kho: find_records.",
            new()
            {
                ["kind"] = ("STRING", "Loại chứng từ"),
                ["record_id"] = ("STRING", "Id chứng từ"),
                ["reason"] = ("STRING", "Lý do hủy"),
            }, ["kind", "record_id", "reason"]),
        new("propose_update_product", "PosProducts", 'E', false,
            "ĐỔI GIÁ BÁN / GIÁ VỐN hoặc NGỪNG BÁN / MỞ BÁN LẠI một mặt hàng (find_products lấy id).",
            new()
            {
                ["product_id"] = ("STRING", "Id hàng"),
                ["price"] = ("NUMBER", "Giá bán mới"),
                ["cost"] = ("NUMBER", "Giá vốn mới"),
                ["active"] = ("BOOLEAN", "false = ngừng bán, true = mở bán lại"),
            }, ["product_id"]),
        new("propose_update_contact", ContactModule, 'E', false,
            "SỬA thông tin khách hàng / nhà cung cấp (tên, SĐT, email, địa chỉ, ghi chú). Chỉ truyền trường cần đổi.",
            new()
            {
                ["kind"] = ("STRING", "Loại"),
                ["record_id"] = ("STRING", "Id (find_customers / find_suppliers)"),
                ["name"] = ("STRING", "Tên mới"),
                ["phone"] = ("STRING", "SĐT mới"),
                ["email"] = ("STRING", "Email mới"),
                ["address"] = ("STRING", "Địa chỉ mới"),
                ["note"] = ("STRING", "Ghi chú mới"),
            }, ["kind", "record_id"]),
    ];

    Task<Pending?> ManageProposalAsync(string tool, Ctx c, Dictionary<string, object?> a, CancellationToken ct) => tool switch
    {
        "propose_review_requests" => Wrap(ReviewAsync(c, a, ct)),
        "propose_delete" => Wrap(DeleteAsync(c, a, ct)),
        "propose_cancel_document" => Wrap(CancelDocumentAsync(c, a, ct)),
        "propose_update_product" => Wrap(UpdateProductAsync(c, a, ct)),
        "propose_update_contact" => Wrap(UpdateContactAsync(c, a, ct)),
        _ => OpsProposalAsync(tool, c, a, ct),
    };

    static async Task<Pending?> Wrap(Task<Pending> t) => await t;

    string RequireKind(Ctx c, string module, Dictionary<string, object?> a)
    {
        var kind = (S(a, "kind") ?? "").Trim().ToLowerInvariant();
        if (!KindsOf(module).ContainsKey(kind)) throw new ActionError("Loại không hợp lệ: " + kind);
        if (!AllowedKinds(c, module).Contains(kind))
            throw new ActionError($"Tài khoản không có quyền với {KindsOf(module)[kind].Label.ToLower(Vi)}.");
        return kind;
    }

    Guid RecordId(Dictionary<string, object?> a) =>
        G(a, "record_id") ?? throw new ActionError("Thiếu id — tra bằng find_records / find_* trước.");

    bool InScope(Ctx c, Guid? employeeId, Guid? userId) =>
        c.Scope.WholeStore || (employeeId is Guid e && c.Scope.HasEmployee(e)) || (userId is Guid u && c.Scope.HasUser(u));

    async Task<string> EmployeeNameAsync(Ctx c, Guid? employeeId, Guid? userId, CancellationToken ct) =>
        await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == c.StoreId && ((employeeId != null && e.Id == employeeId) || (userId != null && e.ApplicationUserId == userId)))
            .Select(e => (e.FirstName + " " + e.LastName).Trim()).FirstOrDefaultAsync(ct) ?? "(không rõ)";

    Pending High(Pending p) => p with { Risk = "high" };

    // ─── Xóa ───────────────────────────────────────────────────────

    async Task<Pending> DeleteAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var kind = RequireKind(c, DeleteModule, a);
        var id = RecordId(a);
        var reason = S(a, "reason");
        const string outOfScope = "Bản ghi của nhân viên ngoài phạm vi bạn quản lý.";
        switch (kind)
        {
            case "penalty":
            {
                var t = await db.PenaltyTickets.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null, ct)
                        ?? throw new ActionError("Không tìm thấy phiếu phạt.");
                if (!InScope(c, t.EmployeeId, null)) throw new ActionError(outOfScope);
                if (t.Status == PenaltyTicketStatus.Cancelled) throw new ActionError("Phiếu phạt này đã hủy.");
                var lines = new List<Line>
                {
                    new("Phiếu", t.TicketCode), new("Nhân viên", await EmployeeNameAsync(c, t.EmployeeId, null, ct)),
                    new("Số tiền", Vnd(t.Amount)), new("Ngày vi phạm", t.ViolationDate.ToString("dd/MM/yyyy")),
                };
                return t.Status == PenaltyTicketStatus.Pending
                    ? High(New(c, "delete_penalty", "Xóa phiếu phạt", lines, "DELETE", $"/api/PenaltyTickets/{id}", null, "PenaltyTickets"))
                    : High(New(c, "cancel_penalty", "Hủy phiếu phạt", [.. lines, new("Lý do hủy", reason ?? "—")], "POST",
                        $"/api/PenaltyTickets/{id}/cancel", new { reason }, "PenaltyTickets",
                        ["Phiếu đã duyệt — hủy sẽ bỏ khoản phạt khỏi lương / sổ quỹ."]));
            }
            case "reward":
            {
                var t = await db.PaymentTransactions.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.Type == "Bonus", ct)
                        ?? throw new ActionError("Không tìm thấy phiếu thưởng.");
                if (t.EmployeeId is not Guid te || !await db.Employees.AnyAsync(e => e.Id == te && e.StoreId == c.StoreId, ct))
                    throw new ActionError("Không tìm thấy phiếu thưởng.");
                if (!InScope(c, te, null)) throw new ActionError(outOfScope);
                return High(New(c, "delete_reward", "Xóa phiếu thưởng",
                [
                    new("Nhân viên", await EmployeeNameAsync(c, te, null, ct)), new("Số tiền", Vnd(t.Amount)),
                    new("Ngày", t.TransactionDate.ToString("dd/MM/yyyy")), new("Lý do", t.Description ?? "—"),
                ], "DELETE", $"/api/Transactions/{id}", null, "BonusPenalty"));
            }
            case "cash":
            {
                var t = await db.CashTransactions.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null, ct)
                        ?? throw new ActionError("Không tìm thấy phiếu thu / chi.");
                if (CashSources.IsPos(t.SourceType))
                    throw new ActionError("Phiếu tự sinh từ bán hàng / nhập hàng — hủy chứng từ gốc (propose_cancel_document), không xóa phiếu.");
                var warn = CashSources.IsLinked(t.SourceType)
                    ? new List<string> { $"Phiếu gắn với {CashSources.Label(t.SourceType)} — chứng từ gốc quay về «chưa chi / chưa thu»." }
                    : [];
                return High(New(c, "delete_cash", t.Type == CashTransactionType.Income ? "Xóa phiếu thu" : "Xóa phiếu chi",
                [
                    new("Phiếu", t.TransactionCode), new("Số tiền", Vnd(t.Amount)),
                    new("Ngày", t.TransactionDate.ToString("dd/MM/yyyy")), new("Nội dung", t.Description ?? "—"),
                ], "DELETE", $"/api/CashTransactions/{id}", null, "CashTransaction", warn));
            }
            case "advance":
            {
                var r = await db.AdvanceRequests.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == c.StoreId, ct)
                        ?? throw new ActionError("Không tìm thấy yêu cầu ứng lương.");
                if (!InScope(c, r.EmployeeId, r.EmployeeUserId)) throw new ActionError(outOfScope);
                if (r.IsPaid) throw new ActionError("Khoản ứng đã chi tiền — xử lý ở màn Ứng lương (thu hồi / trừ lương), không xóa.");
                var lines = new List<Line>
                {
                    new("Nhân viên", await EmployeeNameAsync(c, r.EmployeeId, r.EmployeeUserId, ct)), new("Số tiền", Vnd(r.Amount)),
                    new("Ngày xin", r.RequestDate.ToString("dd/MM/yyyy")), new("Trạng thái", r.Status.ToString()),
                };
                return r.Status == AdvanceRequestStatus.Pending
                    ? High(New(c, "cancel_advance", "Hủy yêu cầu ứng lương", lines, "POST", $"/api/AdvanceRequests/{id}/cancel", null, "AdvanceRequests"))
                    : High(New(c, "delete_advance", "Xóa yêu cầu ứng lương", lines, "DELETE", $"/api/AdvanceRequests/{id}", null, "AdvanceRequests",
                        r.Status == AdvanceRequestStatus.Approved ? ["Đơn đã duyệt — phiếu chi chờ chi đi kèm cũng bị hủy."] : null));
            }
            case "leave":
            {
                var l = await db.Leaves.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == c.StoreId, ct)
                        ?? throw new ActionError("Không tìm thấy đơn nghỉ phép.");
                if (!InScope(c, l.EmployeeId, l.EmployeeUserId)) throw new ActionError(outOfScope);
                if (l.Status == LeaveStatus.Cancelled) throw new ActionError("Đơn này đã hủy.");
                var lines = new List<Line>
                {
                    new("Nhân viên", await EmployeeNameAsync(c, l.EmployeeId, l.EmployeeUserId, ct)),
                    new("Ngày nghỉ", $"{l.StartDate:dd/MM/yyyy}" + (l.EndDate.Date != l.StartDate.Date ? $" – {l.EndDate:dd/MM/yyyy}" : "")),
                    new("Loại", LeaveLabels.TryGetValue(l.Type, out var lt) ? lt : l.Type.ToString()), new("Trạng thái", l.Status.ToString()),
                };
                return l.Status == LeaveStatus.Pending
                    ? High(New(c, "cancel_leave", "Hủy đơn nghỉ phép", lines, "DELETE", $"/api/Leaves/{id}", null, "Leave"))
                    : High(New(c, "delete_leave", "Xóa đơn nghỉ phép", lines, "DELETE", $"/api/Leaves/{id}/force", null, "Leave",
                        ["Đơn đã xử lý — xóa hẳn; phép năm đã trừ (nếu có) được cộng trả lại."]));
            }
            case "attendance_fix":
            {
                var r = await db.AttendanceCorrectionRequests.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == c.StoreId, ct)
                        ?? throw new ActionError("Không tìm thấy phiếu bổ sung chấm công.");
                if (!InScope(c, null, r.EmployeeUserId)) throw new ActionError(outOfScope);
                if (r.Status == CorrectionStatus.Approved)
                    throw new ActionError("Phiếu đã duyệt — cần bỏ duyệt trước (màn Bổ sung chấm công), rồi mới xóa.");
                return High(New(c, "delete_attendance_fix", "Xóa phiếu bổ sung chấm công",
                [
                    new("Nhân viên", r.EmployeeName ?? await EmployeeNameAsync(c, null, r.EmployeeUserId, ct)),
                    new("Ngày giờ", $"{r.NewDate:dd/MM/yyyy} {r.NewTime:hh\\:mm}"), new("Lý do", r.Reason ?? "—"),
                ], "DELETE", $"/api/AttendanceCorrections/{id}", null, "AttendanceCorrection"));
            }
            case "overtime":
            {
                var o = await db.Overtimes.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == c.StoreId, ct)
                        ?? throw new ActionError("Không tìm thấy đăng ký tăng ca.");
                if (o.EmployeeUserId != c.UserId)
                    throw new ActionError("Chỉ người đăng ký tự hủy được tăng ca — quản lý dùng «từ chối» (propose_review_requests).");
                if (o.Status != OvertimeStatus.Pending) throw new ActionError("Chỉ hủy được đăng ký tăng ca đang chờ duyệt.");
                return High(New(c, "cancel_overtime", "Hủy đăng ký tăng ca",
                [
                    new("Ngày", o.Date.ToString("dd/MM/yyyy")), new("Giờ", $"{o.StartTime:hh\\:mm} – {o.EndTime:hh\\:mm}"),
                ], "DELETE", $"/api/Overtimes/{id}", null, "Overtime"));
            }
            case "product":
            {
                var p = await db.PosProducts.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null, ct)
                        ?? throw new ActionError("Không tìm thấy hàng hóa.");
                return High(New(c, "delete_product", "Xóa hàng hóa",
                [
                    new("Mặt hàng", $"{p.Name} ({p.ProductCode})"), new("Giá bán", Vnd(p.BasePrice)),
                    .. p.ProductType == PosProductType.Goods ? new[] { new Line("Tồn kho", $"{p.OnHandQty:0.##} {p.BaseUnitName}") } : [],
                ], "DELETE", $"/api/pos/products/{id}", null, "PosProducts",
                    ["Hàng bị xóa khỏi danh mục (lịch sử bán giữ nguyên). Chỉ muốn tạm ngừng bán thì dùng «ngừng bán»."]));
            }
            case "customer":
            {
                var x = await db.PosCustomers.AsNoTracking().FirstOrDefaultAsync(k => k.Id == id && k.StoreId == c.StoreId && k.Deleted == null, ct)
                        ?? throw new ActionError("Không tìm thấy khách hàng.");
                var lines = new List<Line> { new("Khách", x.Name), new("SĐT", x.Phone ?? "—") };
                if (await db.PosSaleOrders.AsNoTracking().AnyAsync(o => o.CustomerId == id, ct))
                    return New(c, "deactivate_customer", "Ngừng theo dõi khách hàng", lines, "POST", $"/api/pos/customers/{id}/deactivate", null,
                            "PosCustomers", ["Khách đã có hóa đơn nên không xóa được — chuyển sang ngừng theo dõi (ẩn khỏi danh sách)."])
                        with { Undo = [new("POST", $"/api/pos/customers/{id}/activate", null)] };
                return High(New(c, "delete_customer", "Xóa khách hàng", lines, "DELETE", $"/api/pos/customers/{id}", null, "PosCustomers"));
            }
            case "supplier":
            {
                var x = await db.PosSuppliers.AsNoTracking().FirstOrDefaultAsync(k => k.Id == id && k.StoreId == c.StoreId && k.Deleted == null, ct)
                        ?? throw new ActionError("Không tìm thấy nhà cung cấp.");
                var lines = new List<Line> { new("Nhà cung cấp", x.Name), new("SĐT", x.Phone ?? "—") };
                if (await db.PosStockReceipts.AsNoTracking().AnyAsync(r => r.SupplierId == id, ct))
                    return New(c, "deactivate_supplier", "Ngừng theo dõi nhà cung cấp", lines, "POST", $"/api/pos/purchase/suppliers/{id}/deactivate",
                            null, "PosSuppliers", ["NCC đã có phiếu nhập nên không xóa được — chuyển sang ngừng theo dõi."])
                        with { Undo = [new("POST", $"/api/pos/purchase/suppliers/{id}/activate", null)] };
                return High(New(c, "delete_supplier", "Xóa nhà cung cấp", lines, "DELETE", $"/api/pos/purchase/suppliers/{id}", null, "PosSuppliers"));
            }
            case "voucher":
            {
                var v = await db.PosVouchers.AsNoTracking().FirstOrDefaultAsync(k => k.Id == id && k.StoreId == c.StoreId && k.Deleted == null, ct)
                        ?? throw new ActionError("Không tìm thấy voucher.");
                return High(New(c, "delete_voucher", "Xóa mã giảm giá",
                [
                    new("Mã", v.Code), new("Tên", v.Name ?? "—"),
                    new("Mức giảm", v.DiscountType == PosVoucherDiscountType.Percent ? $"{v.DiscountValue:0.##}%" : Vnd(v.DiscountValue)),
                    new("Đã dùng", v.MaxUses is int mu ? $"{v.UsedCount}/{mu} lượt" : $"{v.UsedCount} lượt"),
                ], "DELETE", $"/api/pos/vouchers/{id}", null, "PosVouchers",
                    v.UsedCount > 0 ? ["Mã đã được dùng — hóa đơn cũ giữ nguyên, khách không nhập mã này được nữa."] : null));
            }
            default: // promotion
            {
                var x = await db.PosPromotions.AsNoTracking().FirstOrDefaultAsync(k => k.Id == id && k.StoreId == c.StoreId && k.Deleted == null, ct)
                        ?? throw new ActionError("Không tìm thấy chương trình khuyến mãi.");
                return High(New(c, "delete_promotion", "Xóa chương trình khuyến mãi",
                [
                    new("Chương trình", x.Name),
                    new("Thời gian", (x.ValidFrom is DateTime f ? f.ToString("dd/MM/yyyy") : "—") + " → " + (x.ValidTo is DateTime t ? t.ToString("dd/MM/yyyy") : "không hạn")),
                ], "DELETE", $"/api/pos/promotions/{id}", null, "PosPromotions"));
            }
        }
    }

    // ─── Hủy chứng từ đã hoàn thành ────────────────────────────────

    async Task<Pending> CancelDocumentAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var kind = RequireKind(c, CancelModule, a);
        var id = RecordId(a);
        var reason = S(a, "reason") ?? "Hủy bằng Trợ lý ảo";
        const string onlyCompleted = "Chỉ hủy được chứng từ đã hoàn thành (phiếu nháp xóa / sửa trên màn tương ứng).";
        switch (kind)
        {
            case "sale_order":
            {
                var o = await db.PosSaleOrders.AsNoTracking()
                            .Where(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null)
                            .Select(x => new { x.OrderNo, x.Status, x.CustomerName, x.Total, x.PaidAmount, At = x.SaleDate ?? x.CreatedAt })
                            .FirstOrDefaultAsync(ct) ?? throw new ActionError("Không tìm thấy hóa đơn.");
                if (o.Status != PosSaleOrderStatus.Completed) throw new ActionError(onlyCompleted);
                return High(New(c, "cancel_sale", "Hủy hóa đơn",
                [
                    new("Hóa đơn", o.OrderNo), new("Ngày", o.At.AddHours(AiAssistantVnTime.OffsetHours).ToString("dd/MM/yyyy HH:mm")),
                    new("Khách", o.CustomerName ?? "Khách lẻ"), new("Tổng tiền", Vnd(o.Total)), new("Lý do", reason),
                ], "POST", $"/api/pos/sales/{id}/cancel", new { reason }, "PosSaleOrders",
                    ["Hủy sẽ trả hàng về kho, đảo sổ quỹ / công nợ / điểm khách. Hóa đơn đã có trả hàng thì không hủy được."]));
            }
            case "purchase_receipt":
            {
                var r = await db.PosStockReceipts.AsNoTracking()
                            .Where(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null)
                            .Select(x => new { x.ReceiptNo, x.Status, x.TotalCost, x.PaidAmount, Supplier = x.Supplier != null ? x.Supplier.Name : null })
                            .FirstOrDefaultAsync(ct) ?? throw new ActionError("Không tìm thấy phiếu nhập.");
                if (r.Status != PosPurchaseReceiptStatus.Completed) throw new ActionError(onlyCompleted);
                return High(New(c, "cancel_purchase_receipt", "Hủy phiếu nhập kho",
                [
                    new("Phiếu", r.ReceiptNo), new("Nhà cung cấp", r.Supplier ?? "—"), new("Tiền hàng", Vnd(r.TotalCost)),
                    new("Đã trả NCC", Vnd(r.PaidAmount)), new("Lý do", reason),
                ], "POST", $"/api/pos/purchase/receipts/{id}/cancel", null, "PosPurchaseReceipts",
                    ["Hủy sẽ trừ lại tồn kho đã nhập, hủy thanh toán NCC và công nợ của phiếu."]));
            }
            case "purchase_return":
            {
                var r = await db.PosPurchaseReturns.AsNoTracking()
                            .Where(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null)
                            .Select(x => new { x.ReturnNo, x.Status, x.TotalAmount, x.RefundReceived })
                            .FirstOrDefaultAsync(ct) ?? throw new ActionError("Không tìm thấy phiếu trả hàng NCC.");
                if (r.Status != PosPurchaseReturnStatus.Completed) throw new ActionError(onlyCompleted);
                if (r.RefundReceived > 0) throw new ActionError("NCC đã hoàn tiền cho phiếu này — không hủy được.");
                return High(New(c, "cancel_purchase_return", "Hủy phiếu trả hàng NCC",
                    [new("Phiếu", r.ReturnNo), new("Giá trị", Vnd(r.TotalAmount)), new("Lý do", reason)],
                    "POST", $"/api/pos/purchase/returns/{id}/cancel", null, "PosPurchaseReturns",
                    ["Hủy sẽ cộng lại tồn kho và công nợ NCC."]));
            }
            case "stock_count":
            {
                var r = await db.PosStockCounts.AsNoTracking()
                            .Where(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null)
                            .Select(x => new { x.CountNo, x.Name, x.Status, x.CompletedAt })
                            .FirstOrDefaultAsync(ct) ?? throw new ActionError("Không tìm thấy phiếu kiểm kho.");
                if (r.Status != PosStockCountStatus.Completed) throw new ActionError(onlyCompleted);
                return High(New(c, "cancel_stock_count", "Hủy phiếu kiểm kho",
                    [new("Phiếu", $"{r.CountNo} · {r.Name}"), new("Lý do", reason)],
                    "POST", $"/api/pos/stock/counts/{id}/cancel", null, "PosStockCounts",
                    ["Hủy sẽ đảo các chênh lệch kiểm kê đã cân bằng vào tồn kho."]));
            }
            default: // damage_issue | internal_use
            {
                var damage = kind == "damage_issue";
                var wantKind = damage ? PosStockIssueKind.Damage : PosStockIssueKind.InternalUse;
                var r = await db.PosStockIssues.AsNoTracking()
                            .Where(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null)
                            .Select(x => new { x.IssueNo, x.Status, x.Kind, x.TotalValue, x.Reason })
                            .FirstOrDefaultAsync(ct) ?? throw new ActionError("Không tìm thấy phiếu xuất.");
                if (r.Kind != wantKind) throw new ActionError("Sai loại phiếu xuất — kiểm tra lại (xuất hủy / dùng nội bộ).");
                if (r.Status != PosStockIssueStatus.Completed) throw new ActionError(onlyCompleted);
                var label = damage ? "Hủy phiếu xuất hủy" : "Hủy phiếu xuất dùng nội bộ";
                return High(New(c, damage ? "cancel_damage_issue" : "cancel_internal_use", label,
                    [new("Phiếu", r.IssueNo), new("Giá trị", Vnd(r.TotalValue)), new("Lý do", reason)],
                    "POST", $"/api/pos/stock/{(damage ? "damage" : "internal-use")}/{id}/cancel", null,
                    damage ? "PosDamageIssues" : "PosInternalUseIssues", ["Hủy sẽ cộng lại tồn kho đã xuất."]));
            }
        }
    }

    // ─── Sửa hàng hóa / liên hệ ────────────────────────────────────

    async Task<Pending> UpdateProductAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var id = G(a, "product_id") ?? throw new ActionError("Thiếu hàng — dùng find_products.");
        var p = await db.PosProducts.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null, ct)
                ?? throw new ActionError("Không tìm thấy hàng hóa.");
        var price = a.ContainsKey("price") ? ParseMoney(S(a, "price")) : null;
        var cost = a.ContainsKey("cost") ? ParseMoney(S(a, "cost")) : null;
        bool? active = S(a, "active")?.ToLowerInvariant() switch { "true" or "1" => true, "false" or "0" => false, _ => null };
        if (price is < 0 || cost is < 0) throw new ActionError("Giá không hợp lệ.");

        var steps = new List<Step>();
        var undo = new List<Step?>();
        var lines = new List<Line> { new("Mặt hàng", $"{p.Name} ({p.ProductCode})") };
        string J(object o) => JsonSerializer.Serialize(o, Json);
        if (price != null || cost != null)
        {
            steps.Add(new("PATCH", $"/api/pos/products/{id}/quick", J(new { basePrice = price, costPrice = cost }), Label: "Giá"));
            undo.Add(new("PATCH", $"/api/pos/products/{id}/quick",
                J(new { basePrice = price != null ? p.BasePrice : (decimal?)null, costPrice = cost != null ? p.CostPrice : (decimal?)null })));
            if (price != null) lines.Add(new("Giá bán", $"{Vnd(p.BasePrice)} → {Vnd(price.Value)}"));
            if (cost != null) lines.Add(new("Giá vốn", $"{Vnd(p.CostPrice)} → {Vnd(cost.Value)}"));
        }
        if (active is bool act && act != p.IsActive)
        {
            steps.Add(new("PATCH", $"/api/pos/products/{id}/selling-status", J(new { isDirectSale = p.IsDirectSale, isActive = act }), Label: "Trạng thái bán"));
            undo.Add(new("PATCH", $"/api/pos/products/{id}/selling-status", J(new { isDirectSale = p.IsDirectSale, isActive = p.IsActive })));
            lines.Add(new("Trạng thái", act ? "Mở bán lại" : "Ngừng bán"));
        }
        if (steps.Count == 0) throw new ActionError("Chưa có gì cần đổi (giá mới / ngừng bán / mở bán).");
        var warnings = new List<string>();
        if (price is decimal np && p.BasePrice > 0 && Math.Abs(np - p.BasePrice) / p.BasePrice > 0.5m)
            warnings.Add($"Giá bán đổi hơn 50% so với hiện tại — kiểm tra lại số 0.");
        if (price is decimal np2 && np2 < (cost ?? p.CostPrice)) warnings.Add("Giá bán thấp hơn giá vốn.");
        return New(c, "update_product", "Sửa hàng hóa", lines, "PATCH", steps[0].Path, null, "PosProducts", warnings)
            with { Steps = steps, Batch = true, BatchUndo = undo };
    }

    async Task<Pending> UpdateContactAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var kind = RequireKind(c, ContactModule, a);
        var id = RecordId(a);
        var customer = kind == "customer";
        var cur = customer
            ? await db.PosCustomers.AsNoTracking().Where(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null)
                .Select(x => new { x.Name, x.Phone, x.Email, x.Address, x.Note }).FirstOrDefaultAsync(ct)
            : await db.PosSuppliers.AsNoTracking().Where(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null)
                .Select(x => new { x.Name, x.Phone, x.Email, x.Address, x.Note }).FirstOrDefaultAsync(ct);
        if (cur == null) throw new ActionError(customer ? "Không tìm thấy khách hàng." : "Không tìm thấy nhà cung cấp.");

        var patch = new Dictionary<string, string?>();
        var lines = new List<Line> { new(customer ? "Khách" : "Nhà cung cấp", cur.Name) };
        void Field(string arg, string json, string label, string? old)
        {
            if (S(a, arg) is not { } v || v == old) return;
            patch[json] = v;
            lines.Add(new(label, $"{(string.IsNullOrWhiteSpace(old) ? "(trống)" : old)} → {v}"));
        }
        Field("name", "name", "Tên", cur.Name);
        Field("phone", "phone", "SĐT", cur.Phone);
        Field("email", "email", "Email", cur.Email);
        Field("address", "address", "Địa chỉ", cur.Address);
        Field("note", "note", "Ghi chú", cur.Note);
        if (patch.Count == 0) throw new ActionError("Chưa có thông tin cần đổi.");
        var path = customer ? $"/api/pos/customers/{id}" : $"/api/pos/purchase/suppliers/{id}";
        return New(c, customer ? "update_customer" : "update_supplier", customer ? "Sửa thông tin khách hàng" : "Sửa thông tin nhà cung cấp",
                lines, "PUT", path, patch, customer ? "PosCustomers" : "PosSuppliers")
            with { MergeFrom = path };
    }

    // ─── Tra cứu thêm loại phiếu ───────────────────────────────────

    async Task<object> FindMoreRecordsAsync(Ctx c, string kind, Dictionary<string, object?> a, DateTime since, string q, Guid? emp,
        Func<Guid?, string> nameOfEmployee, CancellationToken ct)
    {
        var users = c.Scope.UserIds;
        var emps = c.Scope.EmployeeIds;
        Guid? empUser = emp is Guid eid
            ? await db.Employees.AsNoTracking().Where(x => x.Id == eid).Select(x => x.ApplicationUserId).FirstOrDefaultAsync(ct)
            : null;
        bool Match(params string?[] parts) => q.Length == 0 || VnSearch.Has(string.Join(" ", parts.Where(p => p != null)), q);

        async Task<object> Hr<T>(List<T> rows, Func<T, Guid?> uid, Func<T, Guid?> eidOf, Func<T, string, object> shape, Func<T, string> text)
        {
            var names = await NamesByUserAsync(c, rows.Select(uid), rows.Select(eidOf), ct);
            string Name(T r) => (eidOf(r) is Guid e && names.TryGetValue(e, out var n1) ? n1 : null)
                                ?? (uid(r) is Guid u && names.TryGetValue(u, out var n2) ? n2 : "");
            var list = rows.Where(r => Match(text(r), Name(r))).Take(10).Select(r => shape(r, Name(r))).ToList();
            return list.Count == 0 ? new { ket_qua = "Không tìm thấy" } : new { ket_qua = list };
        }

        switch (kind)
        {
            case "advance":
            {
                var rows = await db.AdvanceRequests.AsNoTracking()
                    .Where(x => x.StoreId == c.StoreId && x.CreatedAt >= since)
                    .Where(x => (users == null || (x.EmployeeUserId != null && users.Contains(x.EmployeeUserId.Value)))
                                || (emps != null && x.EmployeeId != null && emps.Contains(x.EmployeeId.Value)))
                    .Where(x => emp == null || x.EmployeeId == emp || (empUser != null && x.EmployeeUserId == empUser))
                    .OrderByDescending(x => x.CreatedAt).Take(60).ToListAsync(ct);
                return await Hr(rows, r => r.EmployeeUserId, r => r.EmployeeId,
                    (r, n) => new { id = r.Id, nhan_vien = n, so_tien = r.Amount, trang_thai = r.Status.ToString(), da_chi = r.IsPaid, ngay = r.RequestDate.ToString("yyyy-MM-dd"), ly_do = r.Reason },
                    r => r.Reason ?? "");
            }
            case "overtime":
            {
                var rows = await db.Overtimes.AsNoTracking()
                    .Where(x => x.StoreId == c.StoreId && x.CreatedAt >= since)
                    .Where(x => users == null || users.Contains(x.EmployeeUserId))
                    .Where(x => empUser == null || x.EmployeeUserId == empUser)
                    .OrderByDescending(x => x.Date).Take(60).ToListAsync(ct);
                return await Hr(rows, r => r.EmployeeUserId, _ => null,
                    (r, n) => new { id = r.Id, nhan_vien = n, ngay = r.Date.ToString("yyyy-MM-dd"), gio = $"{r.StartTime:hh\\:mm}-{r.EndTime:hh\\:mm}", trang_thai = r.Status.ToString() },
                    r => r.Reason ?? "");
            }
            case "leave":
            {
                var rows = await db.Leaves.AsNoTracking()
                    .Where(x => x.StoreId == c.StoreId && x.CreatedAt >= since)
                    .Where(x => users == null || users.Contains(x.EmployeeUserId))
                    .Where(x => empUser == null || x.EmployeeUserId == empUser)
                    .OrderByDescending(x => x.StartDate).Take(60).ToListAsync(ct);
                return await Hr(rows, r => r.EmployeeUserId, r => r.EmployeeId,
                    (r, n) => new { id = r.Id, nhan_vien = n, tu = r.StartDate.ToString("yyyy-MM-dd"), den = r.EndDate.ToString("yyyy-MM-dd"), loai = LeaveLabels.GetValueOrDefault(r.Type, r.Type.ToString()), trang_thai = r.Status.ToString() },
                    r => r.Reason ?? "");
            }
            case "attendance_fix":
            {
                var rows = await db.AttendanceCorrectionRequests.AsNoTracking()
                    .Where(x => x.StoreId == c.StoreId && x.CreatedAt >= since)
                    .Where(x => users == null || users.Contains(x.EmployeeUserId))
                    .Where(x => empUser == null || x.EmployeeUserId == empUser)
                    .OrderByDescending(x => x.CreatedAt).Take(60).ToListAsync(ct);
                return await Hr(rows, r => r.EmployeeUserId, _ => null,
                    (r, n) => new { id = r.Id, nhan_vien = n, ngay = r.NewDate?.ToString("yyyy-MM-dd"), gio = r.NewTime?.ToString(@"hh\:mm"), trang_thai = r.Status.ToString(), ly_do = r.Reason },
                    r => r.Reason ?? "");
            }
            case "purchase_receipt":
            {
                var rows = await db.PosStockReceipts.AsNoTracking()
                    .Where(x => x.StoreId == c.StoreId && x.Deleted == null && x.CreatedAt >= since)
                    .OrderByDescending(x => x.CreatedAt).Take(80)
                    .Select(x => new { x.Id, x.ReceiptNo, x.Status, x.TotalCost, x.CreatedAt, Ncc = x.Supplier != null ? x.Supplier.Name : null })
                    .ToListAsync(ct);
                return Result(rows.Where(r => Match(r.ReceiptNo, r.Ncc)).Take(10)
                    .Select(r => (object)new { id = r.Id, ma = r.ReceiptNo, ncc = r.Ncc, tien = r.TotalCost, trang_thai = r.Status.ToString(), ngay = r.CreatedAt.ToString("yyyy-MM-dd") }));
            }
            case "purchase_return":
            {
                var rows = await db.PosPurchaseReturns.AsNoTracking()
                    .Where(x => x.StoreId == c.StoreId && x.Deleted == null && x.CreatedAt >= since)
                    .OrderByDescending(x => x.CreatedAt).Take(80)
                    .Select(x => new { x.Id, x.ReturnNo, x.Status, x.TotalAmount, x.CreatedAt, Ncc = x.Supplier != null ? x.Supplier.Name : null })
                    .ToListAsync(ct);
                return Result(rows.Where(r => Match(r.ReturnNo, r.Ncc)).Take(10)
                    .Select(r => (object)new { id = r.Id, ma = r.ReturnNo, ncc = r.Ncc, tien = r.TotalAmount, trang_thai = r.Status.ToString(), ngay = r.CreatedAt.ToString("yyyy-MM-dd") }));
            }
            case "stock_count":
            {
                var rows = await db.PosStockCounts.AsNoTracking()
                    .Where(x => x.StoreId == c.StoreId && x.Deleted == null && x.CreatedAt >= since)
                    .OrderByDescending(x => x.CreatedAt).Take(80)
                    .Select(x => new { x.Id, x.CountNo, x.Name, x.Status, x.CreatedAt })
                    .ToListAsync(ct);
                return Result(rows.Where(r => Match(r.CountNo, r.Name)).Take(10)
                    .Select(r => (object)new { id = r.Id, ma = r.CountNo, ten = r.Name, trang_thai = r.Status.ToString(), ngay = r.CreatedAt.ToString("yyyy-MM-dd") }));
            }
            case "damage_issue" or "internal_use":
            {
                var k = kind == "damage_issue" ? PosStockIssueKind.Damage : PosStockIssueKind.InternalUse;
                var rows = await db.PosStockIssues.AsNoTracking()
                    .Where(x => x.StoreId == c.StoreId && x.Deleted == null && x.Kind == k && x.CreatedAt >= since)
                    .OrderByDescending(x => x.CreatedAt).Take(80)
                    .Select(x => new { x.Id, x.IssueNo, x.Status, x.TotalValue, x.Reason, x.CreatedAt })
                    .ToListAsync(ct);
                return Result(rows.Where(r => Match(r.IssueNo, r.Reason)).Take(10)
                    .Select(r => (object)new { id = r.Id, ma = r.IssueNo, gia_tri = r.TotalValue, ly_do = r.Reason, trang_thai = r.Status.ToString(), ngay = r.CreatedAt.ToString("yyyy-MM-dd") }));
            }
            case "promotion":
            {
                var rows = await db.PosPromotions.AsNoTracking()
                    .Where(x => x.StoreId == c.StoreId && x.Deleted == null)
                    .OrderByDescending(x => x.CreatedAt).Take(80)
                    .Select(x => new { x.Id, x.Name, x.Type, x.ValidFrom, x.ValidTo, x.IsActive })
                    .ToListAsync(ct);
                return Result(rows.Where(r => Match(r.Name)).Take(10)
                    .Select(r => (object)new { id = r.Id, ten = r.Name, loai = r.Type, tu = r.ValidFrom?.ToString("yyyy-MM-dd"), den = r.ValidTo?.ToString("yyyy-MM-dd"), dang_bat = r.IsActive }));
            }
            case "voucher":
            {
                var rows = await db.PosVouchers.AsNoTracking()
                    .Where(x => x.StoreId == c.StoreId && x.Deleted == null)
                    .OrderByDescending(x => x.CreatedAt).Take(120)
                    .Select(x => new { x.Id, x.Code, x.Name, x.DiscountType, x.DiscountValue, x.UsedCount, x.ValidTo, x.IsActive })
                    .ToListAsync(ct);
                return Result(rows.Where(r => Match(r.Code, r.Name)).Take(10)
                    .Select(r => (object)new
                    {
                        id = r.Id, ma = r.Code, ten = r.Name,
                        giam = r.DiscountType == PosVoucherDiscountType.Percent ? $"{r.DiscountValue:0.##}%" : Vnd(r.DiscountValue),
                        da_dung = r.UsedCount, het_han = r.ValidTo?.ToString("yyyy-MM-dd"), dang_bat = r.IsActive,
                    }));
            }
            default:
                return new { error = "kind phải là: " + string.Join(" | ", RecordKinds) };
        }

        static object Result(IEnumerable<object> list)
        {
            var l = list.ToList();
            return l.Count == 0 ? new { ket_qua = (object)"Không tìm thấy" } : new { ket_qua = (object)l };
        }
    }

    // ─── Hoàn tác ──────────────────────────────────────────────────

    /// <summary>
    /// Cách hoàn tác chứng từ vừa TẠO (theo loại + id API trả về). Sửa / xóa / hủy không hoàn tác được
    /// (trừ khi đề xuất đã có sẵn <see cref="Pending.Undo"/>, vd ngừng theo dõi khách → theo dõi lại).
    /// </summary>
    static List<Step>? UndoSteps(Pending p, string? docId, System.Text.Json.Nodes.JsonNode? data)
    {
        if (p.Undo != null) return p.Undo;
        if (OpsUndoSteps(p, docId, data) is { } ops) return ops;
        if (string.IsNullOrEmpty(docId)) return null;
        Step? s = p.Kind switch
        {
            "advance" => new("POST", $"/api/AdvanceRequests/{docId}/cancel", null),
            "penalty" => new("DELETE", $"/api/PenaltyTickets/{docId}", null),
            "reward" => new("DELETE", $"/api/Transactions/{docId}", null),
            "cash" => new("DELETE", $"/api/CashTransactions/{docId}", null),
            // API chỉ cho chính người đăng ký hủy tăng ca → chỉ hoàn tác được đăng ký cho bản thân.
            "overtime" when p.Body?.Contains("\"employeeUserId\"") != true => new("DELETE", $"/api/Overtimes/{docId}", null),
            "attendance_fix" => new("DELETE", $"/api/AttendanceCorrections/{docId}", null),
            "sale" => new("POST", $"/api/pos/sales/{docId}/cancel", JsonSerializer.Serialize(new { reason = "Hoàn tác (Trợ lý ảo)" }, Json)),
            "product" => new("DELETE", $"/api/pos/products/{docId}", null),
            "promotion" => new("DELETE", $"/api/pos/promotions/{docId}", null),
            "purchase_receipt" => new("POST", $"/api/pos/purchase/receipts/{docId}/cancel", null),
            "purchase_return" => new("POST", $"/api/pos/purchase/returns/{docId}/cancel", null),
            "stock_count" => new("POST", $"/api/pos/stock/counts/{docId}/cancel", null),
            "damage_issue" => new("POST", $"/api/pos/stock/damage/{docId}/cancel", null),
            "internal_use" => new("POST", $"/api/pos/stock/internal-use/{docId}/cancel", null),
            _ => null,
        };
        return s == null ? null : [s];
    }
}
