using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Services;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Tra chứng từ gốc của phiếu thu / chi → nhân viên + chi nhánh đúng của khoản tiền:
///  • Chứng từ bán hàng (đơn, phiếu nhập, trả hàng…): chi nhánh của chứng từ — tiền nằm ở quỹ chi nhánh đó
///    (kể cả đơn online / webhook không có người thao tác).
///  • Chứng từ nhân sự (lương, ứng, thưởng phạt, công tác): chi nhánh của nhân viên; NV chưa gắn = trụ sở.
///  • Không suy ra được → null (BranchStockInterceptor gán chi nhánh đang thao tác / trụ sở).
/// </summary>
public static class CashSourceResolver
{
    public sealed record Info(string Type, Guid? EmployeeId, Guid? BranchId, bool Found);

    public static async Task<Info> ResolveAsync(ZKTecoDbContext db, Guid? storeId, string type, Guid id, CancellationToken ct = default)
    {
        Guid? emp = null, branch = null;
        var found = false;
        switch (type)
        {
            case CashSources.PosSale:
            case CashSources.PosCustomerReturn:
            {
                var o = await db.PosSaleOrders.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id).Select(x => new { x.BranchId }).FirstOrDefaultAsync(ct);
                found = o != null; branch = o?.BranchId;
                break;
            }
            case CashSources.PosDeposit:
            case CashSources.PosDepositRefund:
            {
                var r = await db.PosResourceReservations.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id).Select(x => new { SaleOrderId = x.DepositAppliedOrderId }).FirstOrDefaultAsync(ct);
                found = r != null;
                if (r?.SaleOrderId is Guid oid)
                    branch = await db.PosSaleOrders.IgnoreQueryFilters().AsNoTracking()
                        .Where(x => x.Id == oid).Select(x => x.BranchId).FirstOrDefaultAsync(ct);
                break;
            }
            case CashSources.PosPurchaseReceipt:
            {
                var r = await db.PosStockReceipts.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id).Select(x => new { x.BranchId }).FirstOrDefaultAsync(ct);
                found = r != null; branch = r?.BranchId;
                break;
            }
            case CashSources.PosSupplierPayment:
            {
                var p = await db.PosSupplierPayments.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id).Select(x => new { x.StockReceiptId }).FirstOrDefaultAsync(ct);
                found = p != null;
                if (p?.StockReceiptId is Guid rid)
                    branch = await db.PosStockReceipts.IgnoreQueryFilters().AsNoTracking()
                        .Where(x => x.Id == rid).Select(x => x.BranchId).FirstOrDefaultAsync(ct);
                break;
            }
            case CashSources.PosPurchaseReturnRefund:
            {
                var r = await db.PosPurchaseReturns.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id).Select(x => new { x.BranchId }).FirstOrDefaultAsync(ct);
                found = r != null; branch = r?.BranchId;
                break;
            }
            case CashSources.PosCustomerPayment:
                found = await db.PosCustomerPayments.IgnoreQueryFilters().AnyAsync(x => x.Id == id, ct);
                break;
            case CashSources.PosContract:
                found = await db.PosQuotes.IgnoreQueryFilters().AnyAsync(x => x.Id == id, ct);
                break;
            case CashSources.Payslip:
                emp = await db.Payslips.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id).Select(x => (Guid?)x.EmployeeId).FirstOrDefaultAsync(ct);
                found = emp != null;
                break;
            case CashSources.Advance:
            {
                var a = await db.AdvanceRequests.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id).Select(x => new { x.EmployeeId }).FirstOrDefaultAsync(ct);
                found = a != null; emp = a?.EmployeeId;
                break;
            }
            case CashSources.Reward:
            case CashSources.PenaltyTicket:
            {
                // «phiếu phạt #id» cũ dùng cho cả phiếu phạt lẫn phạt tự duyệt (PaymentTransaction) → tra cả hai.
                var t = await db.PenaltyTickets.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id).Select(x => new { x.EmployeeId }).FirstOrDefaultAsync(ct);
                if (t != null) { type = CashSources.PenaltyTicket; emp = t.EmployeeId; found = true; break; }
                var p = await db.PaymentTransactions.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id).Select(x => new { x.EmployeeId }).FirstOrDefaultAsync(ct);
                if (p != null) { type = CashSources.Reward; emp = p.EmployeeId; found = true; }
                break;
            }
            case CashSources.TripAdvance:
                emp = await db.BusinessTripAdvanceClaims.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id)
                    .Join(db.BusinessTripCases.IgnoreQueryFilters(), a => a.CaseId, c => c.Id, (a, c) => c.EmployeeId)
                    .FirstOrDefaultAsync(ct);
                found = await db.BusinessTripAdvanceClaims.IgnoreQueryFilters().AnyAsync(x => x.Id == id, ct);
                break;
            case CashSources.TripSettlement:
            case CashSources.TripRefund:
                emp = await db.BusinessTripSettlementClaims.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id)
                    .Join(db.BusinessTripCases.IgnoreQueryFilters(), s => s.CaseId, c => c.Id, (s, c) => c.EmployeeId)
                    .FirstOrDefaultAsync(ct);
                found = await db.BusinessTripSettlementClaims.IgnoreQueryFilters().AnyAsync(x => x.Id == id, ct);
                break;
        }

        // Chứng từ nhân sự: chi nhánh của nhân viên (NV chưa gắn chi nhánh = trụ sở).
        if (branch == null && emp is Guid eid && storeId is Guid sid)
        {
            var empBranch = await db.Employees.IgnoreQueryFilters().AsNoTracking()
                .Where(e => e.Id == eid).Select(e => new { e.BranchId }).FirstOrDefaultAsync(ct);
            if (empBranch != null)
                branch = empBranch.BranchId ?? await BranchQueryHelper.HeadquarterIdAsync(db, sid);
        }
        return new Info(type, emp, branch, found);
    }
}
