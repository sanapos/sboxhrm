using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// «Số này từ đâu ra» cho các màn Super Admin: cửa hàng đứng sau số trên thẻ gói / đại lý, nhật ký kho lượt Tingee,
/// đơn mua lượt của cửa hàng. Điều kiện chép đúng từ endpoint tổng (packages, agents, platform-credits,
/// credit-purchases-report) để danh sách khớp số.
/// </summary>
public partial class SystemAdminV2Controller
{
    private const int SaDrillMaxRows = 500;

    /// <summary>
    /// Cửa hàng theo gói ([packageId], hoặc noPackage=true: chưa gán gói) và / hoặc đại lý ([agentId]).
    /// kind: all | active | expiring | expired | new30 — cùng điều kiện với số đếm trong packages / agents.
    /// </summary>
    [HttpGet("drill/stores")]
    public async Task<ActionResult<AppResponse<object>>> DrillStores(
        [FromQuery] Guid? packageId, [FromQuery] Guid? agentId, [FromQuery] bool noPackage = false, [FromQuery] string kind = "all")
    {
        var now = DateTime.UtcNow;
        var since = now.AddDays(-30);
        var q = db.Stores.AsNoTracking().AsQueryable();
        if (packageId.HasValue) q = q.Where(s => s.ServicePackageId == packageId);
        else if (noPackage) q = q.Where(s => s.ServicePackageId == null);
        if (agentId.HasValue) q = q.Where(s => s.AgentId == agentId);
        q = (kind ?? "all").Trim().ToLowerInvariant() switch
        {
            "active" => q.Where(s => s.IsActive && !s.IsLocked && (s.ExpiryDate == null || s.ExpiryDate > now)),
            "expiring" => q.Where(s => s.IsActive && s.ExpiryDate > now && s.ExpiryDate <= now.AddDays(7)),
            "expired" => q.Where(s => s.ExpiryDate != null && s.ExpiryDate <= now),
            "new30" => q.Where(s => s.CreatedAt >= since),
            _ => q,
        };

        var count = await q.CountAsync();
        var items = await q
            .OrderBy(s => s.ExpiryDate == null).ThenBy(s => s.ExpiryDate).ThenBy(s => s.Name)
            .Take(SaDrillMaxRows)
            .Select(s => new
            {
                id = s.Id,
                name = s.Name,
                code = s.Code,
                phone = s.Phone,
                createdAt = s.CreatedAt,
                expiryDate = s.ExpiryDate,
                isActive = s.IsActive,
                isLocked = s.IsLocked,
                packageName = s.ServicePackage == null ? null : s.ServicePackage.Name,
                agentName = s.Agent == null ? null : s.Agent.Name,
                ownerName = s.Owner == null ? null : (s.Owner.LastName + " " + s.Owner.FirstName),
                ownerPhone = s.Owner == null ? null : s.Owner.PhoneNumber,
            })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new { count, truncated = count > items.Count, items }));
    }

    /// <summary>
    /// Nhật ký kho lượt thông báo CK. source: TingeePurchase (đã mua) | StoreAllocation (đã bán / cấp cửa hàng) | trống = tất cả.
    /// total = Σ |delta| của các dòng lọc.
    /// </summary>
    [HttpGet("drill/credit-ledgers")]
    public async Task<ActionResult<AppResponse<object>>> DrillCreditLedgers([FromQuery] string? source)
    {
        var q = db.PosPlatformNotificationCreditLedgers.AsNoTracking().Where(x => x.Deleted == null);
        if (!string.IsNullOrWhiteSpace(source) && Enum.TryParse<PosPlatformCreditLedgerSource>(source.Trim(), true, out var src))
            q = q.Where(x => x.Source == src);

        var count = await q.CountAsync();
        var sumDelta = await q.SumAsync(x => (int?)x.Delta) ?? 0;
        var rows = await q.OrderByDescending(x => x.CreatedAt).Take(SaDrillMaxRows)
            .Select(x => new { x.Id, x.Delta, x.BalanceAfter, x.Source, x.StoreId, x.Note, x.CreatedAt, x.CreatedBy })
            .ToListAsync();
        var storeIds = rows.Where(x => x.StoreId.HasValue).Select(x => x.StoreId!.Value).Distinct().ToList();
        var names = storeIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await db.Stores.AsNoTracking().Where(s => storeIds.Contains(s.Id)).ToDictionaryAsync(s => s.Id, s => s.Name ?? "");

        return Ok(AppResponse<object>.Success(new
        {
            count,
            sumDelta,
            total = Math.Abs(sumDelta),
            truncated = count > rows.Count,
            items = rows.Select(x => new
            {
                id = x.Id,
                delta = x.Delta,
                balanceAfter = x.BalanceAfter,
                source = x.Source.ToString(),
                storeId = x.StoreId,
                storeName = x.StoreId is Guid sid ? names.GetValueOrDefault(sid) : null,
                note = x.Note,
                createdAt = x.CreatedAt,
                createdBy = x.CreatedBy,
            }).ToList(),
        }));
    }

    /// <summary>Đơn cửa hàng tự mua gói lượt theo trạng thái (Paid / Pending) — cùng điều kiện credit-purchases-report.</summary>
    [HttpGet("drill/credit-purchases")]
    public async Task<ActionResult<AppResponse<object>>> DrillCreditPurchases([FromQuery] string status = "Paid")
    {
        var st = Enum.TryParse<PosNotificationCreditPurchaseStatus>(status, true, out var s) ? s : PosNotificationCreditPurchaseStatus.Paid;
        var q = db.PosNotificationCreditPurchases.AsNoTracking().Where(x => x.Deleted == null && x.Status == st);
        var count = await q.CountAsync();
        var credits = await q.SumAsync(x => (int?)x.CreditCount) ?? 0;
        var amount = await q.SumAsync(x => (decimal?)x.AmountPaid) ?? 0;
        var items = await q.OrderByDescending(x => x.CreatedAt).Take(SaDrillMaxRows)
            .Select(x => new
            {
                id = x.Id,
                storeName = x.Store != null ? x.Store.Name : null,
                packageName = x.Package != null ? x.Package.Name : "Gói credit",
                creditCount = x.CreditCount,
                amountPaid = x.AmountPaid,
                status = x.Status.ToString(),
                paidAt = x.PaidAt,
                createdAt = x.CreatedAt,
                externalPaymentRef = x.ExternalPaymentRef,
            })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new { count, credits, amount, truncated = count > items.Count, items }));
    }
}
