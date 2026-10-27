using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Hiểu biết sẵn về cửa hàng nạp vào hướng dẫn của AI:
///  • Hồ sơ chủ cửa hàng tự viết (giờ mở cửa, chính sách, nội quy, tên gọi tắt…);
///  • Ảnh chụp nhanh: ngành hàng, chi nhánh, nhóm hàng, món bán chạy 30 ngày, phòng ban.
/// Có sẵn trong prompt nên AI hiểu «cf sữa», «chi nhánh 2», «bên bếp» mà không phải gọi thêm công cụ (bớt một vòng gọi
/// = bớt một lượt quota). Lưu bộ nhớ đệm 30 phút / cửa hàng; hồ sơ xóa đệm ngay khi lưu.
/// </summary>
public static class AiAssistantStoreKnowledge
{
    public const int MaxProfileChars = 3000;

    static readonly TimeSpan SnapshotTtl = TimeSpan.FromMinutes(30);

    public static string ProfileKey(Guid storeId) => "ai-store-profile:" + storeId;

    static string SnapshotKey(Guid storeId, bool pos, bool hr) => $"ai-store-snapshot:{storeId}:{(pos ? 1 : 0)}{(hr ? 1 : 0)}";

    public static async Task<string?> ProfileAsync(ZKTecoDbContext db, IMemoryCache cache, Guid storeId, CancellationToken ct)
    {
        if (cache.TryGetValue(ProfileKey(storeId), out string? cached)) return cached;
        string? text = null;
        try
        {
            text = await db.AiStoreProfiles.AsNoTracking().Where(p => p.StoreId == storeId)
                .Select(p => p.Content).FirstOrDefaultAsync(ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Bảng chưa có (chưa chạy patch) → coi như chưa viết hồ sơ.
        }
        cache.Set(ProfileKey(storeId), text, new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = SnapshotTtl, Size = 1 });
        return text;
    }

    /// <param name="pos">Người hỏi xem được dữ liệu bán hàng (nhóm hàng, món bán chạy).</param>
    /// <param name="hr">Người hỏi xem được cơ cấu nhân sự (phòng ban, số người).</param>
    public static async Task<string> BuildAsync(
        ZKTecoDbContext db, IMemoryCache cache, Guid storeId, bool pos, bool hr, ILogger logger, CancellationToken ct)
    {
        var sb = new StringBuilder();
        var profile = await ProfileAsync(db, cache, storeId, ct);
        if (!string.IsNullOrWhiteSpace(profile))
        {
            sb.AppendLine("=== HỒ SƠ CỬA HÀNG (chủ cửa hàng viết — tuân theo khi trả lời) ===");
            sb.AppendLine(profile.Trim());
        }

        var key = SnapshotKey(storeId, pos, hr);
        if (!cache.TryGetValue(key, out string? snapshot))
        {
            try
            {
                snapshot = await SnapshotAsync(db, storeId, pos, hr, ct);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "AI store snapshot failed");
                snapshot = "";
            }
            cache.Set(key, snapshot, new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = SnapshotTtl, Size = 1 });
        }
        if (!string.IsNullOrWhiteSpace(snapshot))
        {
            if (sb.Length > 0) sb.AppendLine();
            sb.Append(snapshot);
        }
        return sb.ToString().Trim();
    }

    static async Task<string> SnapshotAsync(ZKTecoDbContext db, Guid storeId, bool pos, bool hr, CancellationToken ct)
    {
        var sb = new StringBuilder();
        var store = await db.Stores.AsNoTracking().Where(s => s.Id == storeId).Select(s => s.Name).FirstOrDefaultAsync(ct);
        sb.AppendLine($"=== CỬA HÀNG: {store} ===");
        var branches = await db.Branches.AsNoTracking().Where(b => b.StoreId == storeId && b.Deleted == null)
            .OrderBy(b => b.Name).Select(b => b.Name).Take(20).ToListAsync(ct);
        if (branches.Count > 0) sb.AppendLine("- Chi nhánh: " + string.Join(", ", branches));

        if (pos)
        {
            var profile = await db.PosStoreSellSettings.AsNoTracking()
                .Where(s => s.StoreId == storeId).Select(s => (PosSellProfile?)s.SellProfile).FirstOrDefaultAsync(ct);
            if (profile != null) sb.AppendLine($"- Ngành hàng: {profile}");
            var cats = await db.PosProductCategories.AsNoTracking()
                .Where(c => c.StoreId == storeId && c.Deleted == null).OrderBy(c => c.Name).Select(c => c.Name).Take(30).ToListAsync(ct);
            if (cats.Count > 0) sb.AppendLine("- Nhóm hàng: " + string.Join(", ", cats));
            var products = await db.PosProducts.AsNoTracking().CountAsync(p => p.StoreId == storeId && p.Deleted == null && p.IsActive, ct);
            sb.AppendLine($"- Số mặt hàng đang bán: {products}");
            var since = DateTime.UtcNow.AddDays(-30);
            var top = await db.PosSaleOrderLines.AsNoTracking()
                .Where(l => l.SaleOrder!.StoreId == storeId && l.SaleOrder.Deleted == null
                            && l.SaleOrder.Status == PosSaleOrderStatus.Completed
                            && (l.SaleOrder.SaleDate ?? l.SaleOrder.CreatedAt) >= since)
                .GroupBy(l => l.ProductName)
                .Select(g => new { Name = g.Key, Qty = g.Sum(x => x.Qty) })
                .OrderByDescending(x => x.Qty).Take(12).ToListAsync(ct);
            if (top.Count > 0) sb.AppendLine("- Bán nhiều nhất 30 ngày: " + string.Join(", ", top.Select(t => t.Name)));
        }

        if (hr)
        {
            var depts = await db.Departments.AsNoTracking()
                .Where(d => d.StoreId == storeId && d.Deleted == null).Select(d => new { d.Id, d.Name }).ToListAsync(ct);
            var counts = await db.Employees.AsNoTracking()
                .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkStatus == EmployeeWorkStatus.Active)
                .GroupBy(e => e.DepartmentId).Select(g => new { g.Key, N = g.Count() }).ToListAsync(ct);
            var total = counts.Sum(x => x.N);
            sb.AppendLine($"- Nhân viên đang làm: {total}"
                          + (depts.Count > 0
                              ? " (" + string.Join(", ", depts.Select(d => new { d.Name, N = counts.FirstOrDefault(x => x.Key == d.Id)?.N ?? 0 })
                                  .Where(x => x.N > 0).OrderByDescending(x => x.N).Take(15).Select(x => $"{x.Name} {x.N}")) + ")"
                              : ""));
        }
        return sb.ToString();
    }
}
