using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services.Assets;

/// <summary>
/// Số liệu «Tổng quan tài sản»: giá trị mua / còn lại / khấu hao, tỷ lệ sử dụng, phân bổ theo
/// danh mục / loại / phòng ban, mua sắm 12 tháng, tuổi tài sản, việc cần xử lý, hoạt động gần đây.
/// </summary>
public static class AssetDashboardBuilder
{
    public const int IdleDays = 90;

    public static string StatusName(AssetStatus s) => s switch
    {
        AssetStatus.Active => "Đang sử dụng",
        AssetStatus.InMaintenance => "Đang bảo trì",
        AssetStatus.Broken => "Hỏng",
        AssetStatus.Disposed => "Đã thanh lý",
        AssetStatus.Lost => "Đã mất",
        AssetStatus.InStock => "Trong kho",
        _ => s.ToString(),
    };

    public static string TypeName(AssetType t) => t switch
    {
        AssetType.Electronics => "Thiết bị điện tử",
        AssetType.Furniture => "Nội thất",
        AssetType.Vehicle => "Phương tiện",
        AssetType.Tool => "Công cụ dụng cụ",
        AssetType.Machinery => "Máy móc",
        AssetType.Software => "Phần mềm",
        _ => "Khác",
    };

    static string TransferName(AssetTransferType t) => t switch
    {
        AssetTransferType.Assignment => "Cấp phát",
        AssetTransferType.Transfer => "Chuyển giao",
        AssetTransferType.Return => "Thu hồi",
        AssetTransferType.Maintenance => "Bảo trì",
        AssetTransferType.Disposal => "Thanh lý",
        _ => t.ToString(),
    };

    public static async Task<object> BuildAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var assets = await db.Assets.AsNoTracking()
            .Include(a => a.Category)
            .Include(a => a.CurrentAssignee)
            .Include(a => a.Images.Where(i => i.IsPrimary))
            .Where(a => a.StoreId == storeId && a.IsActive)
            .ToListAsync(ct);

        var lastMove = await db.AssetTransfers.AsNoTracking()
            .Where(t => t.Asset != null && t.Asset.StoreId == storeId)
            .GroupBy(t => t.AssetId)
            .Select(g => new { AssetId = g.Key, Last = g.Max(x => x.TransferDate) })
            .ToDictionaryAsync(x => x.AssetId, x => x.Last, ct);

        static bool InUse(Asset a) => a.Status is not (AssetStatus.Disposed or AssetStatus.Lost);
        var inUse = assets.Where(InUse).ToList();

        var purchaseValue = inUse.Sum(AssetValuation.PurchaseValue);
        var bookValue = inUse.Sum(a => AssetValuation.BookValue(a, now));
        var usable = inUse.Count(a => a.Status is AssetStatus.Active or AssetStatus.InStock or AssetStatus.InMaintenance);
        var assigned = inUse.Count(a => a.CurrentAssigneeId != null);
        var warrantySoon = inUse.Where(a => a.WarrantyExpiry.HasValue &&
                                            a.WarrantyExpiry.Value > now && a.WarrantyExpiry.Value <= now.AddDays(30)).ToList();
        var warrantyExpired = inUse.Count(a => a.WarrantyExpiry.HasValue && a.WarrantyExpiry.Value <= now);

        DateTime IdleSince(Asset a) =>
            new[] { a.PurchaseDate ?? a.CreatedAt, a.CreatedAt, lastMove.GetValueOrDefault(a.Id) }.Max();
        var idle = inUse.Where(a => a.Status == AssetStatus.InStock && a.CurrentAssigneeId == null &&
                                    (now - IdleSince(a)).TotalDays >= IdleDays).ToList();

        // ── Việc cần xử lý (ưu tiên: hỏng → mất bảo hành sắp tới → bảo trì → nằm kho lâu)
        var attention = new List<(int Severity, Asset A, string Reason)>();
        attention.AddRange(assets.Where(a => a.Status == AssetStatus.Broken).Select(a => (3, a, "Hỏng — cần sửa hoặc thanh lý")));
        attention.AddRange(warrantySoon.Select(a => (2, a,
            $"Hết bảo hành sau {(int)Math.Ceiling((a.WarrantyExpiry!.Value - now).TotalDays)} ngày")));
        attention.AddRange(assets.Where(a => a.Status == AssetStatus.InMaintenance).Select(a => (2, a, "Đang bảo trì")));
        attention.AddRange(idle.Select(a => (1, a, $"Nằm kho {(int)(now - IdleSince(a)).TotalDays} ngày chưa cấp")));

        var months = Enumerable.Range(0, 12)
            .Select(i => new DateTime(now.Year, now.Month, 1).AddMonths(-11 + i))
            .ToList();

        var agingBuckets = new[] { ("Dưới 1 năm", 0.0, 1.0), ("1–3 năm", 1.0, 3.0), ("3–5 năm", 3.0, 5.0), ("Trên 5 năm", 5.0, 999.0) };

        var lastInventory = await db.AssetInventories.AsNoTracking()
            .Where(i => i.StoreId == storeId && i.Deleted == null && i.Status == 1)
            .OrderByDescending(i => i.EndDate ?? i.StartDate)
            .Select(i => new
            {
                i.Id,
                i.InventoryCode,
                i.Name,
                Date = i.EndDate ?? i.StartDate,
                Total = i.Items.Count,
                Checked = i.Items.Count(x => x.IsChecked),
                Issues = i.Items.Count(x => x.HasIssue),
            })
            .FirstOrDefaultAsync(ct);

        var recent = await db.AssetTransfers.AsNoTracking()
            .Where(t => t.Asset != null && t.Asset.StoreId == storeId)
            .OrderByDescending(t => t.TransferDate)
            .Take(10)
            .Select(t => new
            {
                t.TransferType,
                t.TransferDate,
                AssetCode = t.Asset!.AssetCode,
                AssetName = t.Asset.Name,
                From = t.FromUser != null ? (t.FromUser.LastName + " " + t.FromUser.FirstName).Trim() : null,
                To = t.ToUser != null ? (t.ToUser.LastName + " " + t.ToUser.FirstName).Trim() : null,
                t.IsConfirmed,
            })
            .ToListAsync(ct);

        static string EmpName(Employee? e) => e == null ? "" : $"{e.LastName} {e.FirstName}".Trim();

        return new
        {
            generatedAt = now,
            kpis = new
            {
                totalAssets = assets.Count,
                inUseAssets = inUse.Count,
                totalQuantity = inUse.Sum(a => a.Quantity),
                purchaseValue,
                bookValue,
                depreciation = purchaseValue - bookValue,
                depreciationPct = purchaseValue > 0 ? Math.Round((purchaseValue - bookValue) / purchaseValue * 100m, 1) : 0,
                assigned,
                usable,
                utilizationPct = usable > 0 ? Math.Round(assigned * 100m / usable, 1) : 0,
                inStock = inUse.Count(a => a.Status == AssetStatus.InStock),
                maintenance = inUse.Count(a => a.Status == AssetStatus.InMaintenance),
                broken = inUse.Count(a => a.Status == AssetStatus.Broken),
                disposed = assets.Count(a => a.Status == AssetStatus.Disposed),
                lost = assets.Count(a => a.Status == AssetStatus.Lost),
                warrantyExpiringSoon = warrantySoon.Count,
                warrantyExpired,
                idleInStock = idle.Count,
                pendingConfirm = await db.AssetTransfers.CountAsync(t =>
                    t.Asset != null && t.Asset.StoreId == storeId && !t.IsConfirmed &&
                    t.ToUserId != null && t.TransferDate >= now.AddDays(-60), ct),
            },
            byStatus = assets.GroupBy(a => a.Status)
                .Select(g => new
                {
                    status = (int)g.Key,
                    name = StatusName(g.Key),
                    count = g.Count(),
                    value = g.Sum(a => AssetValuation.BookValue(a, now)),
                })
                .OrderByDescending(x => x.count),
            byCategory = inUse.GroupBy(a => a.Category?.Name ?? "Chưa phân loại")
                .Select(g => new
                {
                    name = g.Key,
                    count = g.Count(),
                    purchaseValue = g.Sum(AssetValuation.PurchaseValue),
                    bookValue = g.Sum(a => AssetValuation.BookValue(a, now)),
                })
                .OrderByDescending(x => x.bookValue),
            byType = inUse.GroupBy(a => a.AssetType)
                .Select(g => new { type = (int)g.Key, name = TypeName(g.Key), count = g.Count(), bookValue = g.Sum(a => AssetValuation.BookValue(a, now)) })
                .OrderByDescending(x => x.bookValue),
            byDepartment = inUse.Where(a => a.CurrentAssignee != null)
                .GroupBy(a => string.IsNullOrWhiteSpace(a.CurrentAssignee!.Department) ? "Chưa phân phòng" : a.CurrentAssignee.Department!)
                .Select(g => new
                {
                    name = g.Key,
                    count = g.Count(),
                    employees = g.Select(a => a.CurrentAssigneeId).Distinct().Count(),
                    bookValue = g.Sum(a => AssetValuation.BookValue(a, now)),
                })
                .OrderByDescending(x => x.bookValue),
            purchasesByMonth = months.Select(m => new
            {
                month = m.ToString("MM/yyyy"),
                count = assets.Count(a => (a.PurchaseDate ?? a.CreatedAt) >= m && (a.PurchaseDate ?? a.CreatedAt) < m.AddMonths(1)),
                value = assets.Where(a => (a.PurchaseDate ?? a.CreatedAt) >= m && (a.PurchaseDate ?? a.CreatedAt) < m.AddMonths(1))
                    .Sum(AssetValuation.PurchaseValue),
            }),
            aging = agingBuckets.Select(b => new
            {
                label = b.Item1,
                count = inUse.Count(a => AssetValuation.AgeYears(a, now) >= b.Item2 && AssetValuation.AgeYears(a, now) < b.Item3),
                bookValue = inUse.Where(a => AssetValuation.AgeYears(a, now) >= b.Item2 && AssetValuation.AgeYears(a, now) < b.Item3)
                    .Sum(a => AssetValuation.BookValue(a, now)),
            }),
            topAssignees = inUse.Where(a => a.CurrentAssignee != null)
                .GroupBy(a => a.CurrentAssigneeId)
                .Select(g => new
                {
                    name = EmpName(g.First().CurrentAssignee),
                    department = g.First().CurrentAssignee!.Department,
                    count = g.Count(),
                    bookValue = g.Sum(a => AssetValuation.BookValue(a, now)),
                })
                .OrderByDescending(x => x.bookValue)
                .Take(5),
            attention = attention
                .OrderByDescending(x => x.Severity)
                .ThenByDescending(x => AssetValuation.BookValue(x.A, now))
                .Take(10)
                .Select(x => new
                {
                    id = x.A.Id,
                    code = x.A.AssetCode,
                    name = x.A.Name,
                    reason = x.Reason,
                    severity = x.Severity,
                    status = (int)x.A.Status,
                    imageUrl = x.A.Images.FirstOrDefault()?.ImageUrl,
                    assignee = EmpName(x.A.CurrentAssignee),
                }),
            recentActivity = recent.Select(r => new
            {
                type = (int)r.TransferType,
                typeName = TransferName(r.TransferType),
                date = r.TransferDate,
                assetCode = r.AssetCode,
                assetName = r.AssetName,
                from = r.From,
                to = r.To,
                confirmed = r.IsConfirmed,
            }),
            lastInventory,
        };
    }
}
