using ZKTecoADMS.Api.Controllers.Base;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosCustomersController
{
    public record CustomerPaymentDto(
        Guid Id, string PaymentNo, decimal Amount, string PaymentMethod,
        DateTime PaidAt, string? Note, Guid? SaleOrderId, string? CreatedBy);

    public record CreateCustomerPaymentDto(
        decimal Amount,
        string? PaymentMethod,
        DateTime? PaidAt,
        string? Note,
        Guid? SaleOrderId = null,
        Guid? BankAccountId = null);

    [HttpGet("{id:guid}/payments")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<CustomerPaymentDto>>>> GetPayments(Guid id)
    {
        var storeId = RequiredStoreId;
        var items = await dbContext.PosCustomerPayments.AsNoTracking()
            .Where(p => p.CustomerId == id && p.StoreId == storeId && p.Deleted == null)
            .OrderByDescending(p => p.PaidAt)
            .Select(p => new CustomerPaymentDto(
                p.Id, p.PaymentNo, p.Amount, p.PaymentMethod, p.PaidAt, p.Note, p.SaleOrderId, p.CreatedBy))
            .ToListAsync();
        return Ok(AppResponse<List<CustomerPaymentDto>>.Success(items));
    }

    [HttpPost("{id:guid}/payments")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<CustomerPaymentDto>>> AddPayment(
        Guid id, [FromBody] CreateCustomerPaymentDto dto)
    {
        var storeId = RequiredStoreId;
        var customer = await dbContext.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (customer == null)
            return NotFound(AppResponse<CustomerPaymentDto>.Fail("Không tìm thấy khách hàng"));

        var (pay, err) = await PosCustomerFinanceHelper.CollectDebtAsync(
            dbContext, storeId, customer, dto.Amount,
            dto.PaymentMethod ?? "Tiền mặt", dto.PaidAt, dto.Note, dto.SaleOrderId, CurrentUserEmail);
        if (err != null) return BadRequest(AppResponse<CustomerPaymentDto>.Fail(err));
        await PosFinanceSyncHelper.SyncCustomerPaymentAsync(
            dbContext, pay!, customer, CurrentUserId, dto.BankAccountId);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<CustomerPaymentDto>.Success(new CustomerPaymentDto(
            pay!.Id, pay.PaymentNo, pay.Amount, pay.PaymentMethod, pay.PaidAt, pay.Note,
            pay.SaleOrderId, pay.CreatedBy)));
    }

    /// <summary>
    /// Tóm tắt nợ của khách cho màn bán hàng (nhắc nợ khi chọn khách): số nợ hiện tại (đọc mới, không lấy số cũ trên máy),
    /// số đơn còn nợ, đơn nợ lâu nhất (ngày), lần thu nợ gần nhất.
    /// </summary>
    [HttpGet("{id:guid}/debt-summary")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "PosSell", "PosCustomers", "PosSaleOrders")]
    public async Task<ActionResult<AppResponse<object>>> DebtSummary(Guid id)
    {
        var storeId = RequiredStoreId;
        var c = await dbContext.PosCustomers.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy khách hàng"));
        var open = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.CustomerId == id && o.Deleted == null &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee > o.PaidAmount)
            .Select(o => new
            {
                o.OrderNo,
                Due = o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee - o.PaidAmount,
                At = o.SaleDate ?? o.CreatedAt,
            })
            .OrderBy(o => o.At)
            .ToListAsync();
        var lastPay = await dbContext.PosCustomerPayments.AsNoTracking()
            .Where(p => p.CustomerId == id && p.StoreId == storeId && p.Deleted == null)
            .OrderByDescending(p => p.PaidAt)
            .Select(p => new { p.PaidAt, p.Amount })
            .FirstOrDefaultAsync();
        static int AgeDays(DateTime utc) => PosDebtPolicy.AgeDaysVn(utc);
        var oldest = open.FirstOrDefault();
        var policy = await PosDebtPolicy.LoadAsync(dbContext, storeId);
        var limit = policy.LimitFor(c);
        var term = policy.TermFor(c);
        var oldestDays = oldest == null ? 0 : AgeDays(oldest.At);
        return Ok(AppResponse<object>.Success(new
        {
            debtLimit = limit,
            limitIsCustom = c.DebtLimit is > 0,
            availableCredit = limit is decimal l ? Math.Max(0, l - c.CurrentDebt) : (decimal?)null,
            termDays = term,
            overdueDays = term > 0 && oldestDays > term ? oldestDays - term : 0,
            overdueDebt = term > 0 ? open.Where(o => AgeDays(o.At) > term).Sum(o => o.Due) : 0,
            blockOverLimit = policy.BlockOverLimit,
            blockOverdue = policy.BlockOverdue,
            customerId = c.Id,
            currentDebt = c.CurrentDebt,
            openOrderCount = open.Count,
            openOrderDebt = open.Sum(o => o.Due),
            oldestOrderNo = oldest?.OrderNo,
            oldestDays = oldest == null ? 0 : AgeDays(oldest.At),
            over30 = open.Where(o => AgeDays(o.At) > 30).Sum(o => o.Due),
            lastPaymentAt = lastPay == null ? (DateTime?)null : ZKTecoADMS.Application.Helpers.VnTimeHelper.UtcToVn(lastPay.PaidAt),
            lastPaymentAmount = lastPay?.Amount,
        }));
    }

    public record DebtAdjustDto(decimal NewBalance, string? Reason, DateTime? At = null);

    /// <summary>
    /// Nhập nợ đầu kỳ (chuyển từ phần mềm cũ) / điều chỉnh công nợ khách về số đúng, có lý do — ghi sổ công nợ
    /// («Số dư đầu» nếu khách chưa có dòng sổ nào, còn lại «Điều chỉnh»). Không đổi tiền đã thu của các đơn.
    /// </summary>
    [HttpPost("{id:guid}/debt-adjust")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> AdjustDebt(Guid id, [FromBody] DebtAdjustDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto.NewBalance < 0) return BadRequest(AppResponse<object>.Fail("Công nợ không được âm"));
        var reason = dto.Reason?.Trim();
        if (string.IsNullOrEmpty(reason)) return BadRequest(AppResponse<object>.Fail("Nhập lý do điều chỉnh"));
        var c = await dbContext.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy khách hàng"));
        if (dto.NewBalance == c.CurrentDebt) return BadRequest(AppResponse<object>.Fail("Công nợ không đổi"));
        var hasLedger = await dbContext.PosDebtLedgerEntries.AnyAsync(e =>
            e.StoreId == storeId && e.PartyType == PosDebtLedger.Customer && e.PartyId == id);
        var before = c.CurrentDebt;
        c.CurrentDebt = Math.Round(dto.NewBalance, 0);
        c.UpdatedAt = DateTime.UtcNow;
        c.UpdatedBy = CurrentUserEmail;
        PosDebtLedger.Add(dbContext, storeId, PosDebtLedger.Customer, c.Id, before, c.CurrentDebt,
            hasLedger || before != 0 ? "Adjust" : "Opening", null, null, reason,
            dto.At?.ToUniversalTime() ?? DateTime.UtcNow, CurrentUserEmail);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id, before, currentDebt = c.CurrentDebt }));
    }

    /// <summary>Sổ đối chiếu công nợ khách trong kỳ (đầu kỳ, từng phát sinh có số dư, cuối kỳ).</summary>
    [HttpGet("{id:guid}/statement")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Statement(Guid id, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        var c = await dbContext.PosCustomers.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy khách hàng"));
        return Ok(AppResponse<object>.Success(
            await PosDebtStatement.BuildAsync(dbContext, storeId, PosDebtLedger.Customer, id, c.CurrentDebt, from, to, HttpContext.BranchContext())));
    }

    [HttpGet("{id:guid}/points")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetPointHistory(
        Guid id, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var customer = await dbContext.PosCustomers.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (customer == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy khách hàng"));

        var q = dbContext.PosCustomerPointTransactions.AsNoTracking()
            .Where(t => t.CustomerId == id && t.StoreId == storeId && t.Deleted == null);
        var total = await q.CountAsync();
        var items = await q.OrderByDescending(t => t.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(t => new
            {
                t.Id,
                Type = t.TransactionType.ToString(),
                t.Points,
                t.BalanceAfter,
                t.Note,
                t.SaleOrderId,
                t.CreatedAt,
            })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new
        {
            pointBalance = customer.PointBalance,
            total,
            page,
            pageSize,
            items,
        }));
    }

    [HttpGet("{id:guid}/history")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetHistory(Guid id, [FromQuery] int take = 30)
    {
        var storeId = RequiredStoreId;
        take = Math.Clamp(take, 5, 100);
        var orders = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.CustomerId == id && o.StoreId == storeId && o.Deleted == null)
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt)
            .Take(take)
            .Select(o => new
            {
                o.Id,
                o.OrderNo,
                o.Status,
                o.Total,
                o.PaidAmount,
                // Phải thu = tiền hàng + VAT + phụ thu + phí giao (trước đây quên VAT… → nợ âm); đơn hủy không nợ.
                PayableTotal = o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee,
                BalanceDue = o.Status == PosSaleOrderStatus.Cancelled
                    ? 0
                    : o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee - o.PaidAmount,
                o.SaleDate,
                o.CreatedAt,
            })
            .ToListAsync();
        var payments = await dbContext.PosCustomerPayments.AsNoTracking()
            .Where(p => p.CustomerId == id && p.StoreId == storeId && p.Deleted == null)
            .OrderByDescending(p => p.PaidAt)
            .Take(take)
            .Select(p => new
            {
                p.Id,
                p.PaymentNo,
                p.Amount,
                p.PaymentMethod,
                p.PaidAt,
                p.Note,
                p.SaleOrderId,
            })
            .ToListAsync();
        var sessionBalances = await dbContext.PosCustomerSessionBalances.AsNoTracking()
            .Where(b => b.CustomerId == id && b.StoreId == storeId && b.Deleted == null)
            .OrderByDescending(b => b.CreatedAt)
            .Select(b => new
            {
                b.Id,
                b.PackageName,
                b.TotalSessions,
                b.RemainingSessions,
                UsedSessions = b.TotalSessions - b.RemainingSessions,
                b.ExpiresAt,
                b.CreatedAt,
            })
            .ToListAsync();
        var sessionTxnRows = await (
            from t in dbContext.PosCustomerSessionTransactions.AsNoTracking()
            join b in dbContext.PosCustomerSessionBalances.AsNoTracking() on t.BalanceId equals b.Id
            where t.CustomerId == id && t.StoreId == storeId && t.Deleted == null
            orderby (t.UsedAt ?? t.CreatedAt) descending
            select new
            {
                t.Id,
                t.BalanceId,
                b.PackageName,
                t.TransactionType,
                t.SessionDelta,
                t.RemainingAfter,
                At = t.UsedAt ?? t.CreatedAt,
                t.EmployeeName,
                t.Note,
            }).Take(take).ToListAsync();
        var sessionTxns = sessionTxnRows.Select(t => new
        {
            t.Id,
            t.BalanceId,
            t.PackageName,
            Type = t.TransactionType.ToString(),
            t.SessionDelta,
            t.RemainingAfter,
            t.At,
            t.EmployeeName,
            t.Note,
        }).ToList();
        return Ok(AppResponse<object>.Success(new { orders, payments, sessionBalances, sessionTxns }));
    }
}
