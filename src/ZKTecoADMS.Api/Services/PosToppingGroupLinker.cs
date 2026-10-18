using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Gắn một nhóm topping vào nhiều món một lần (chọn món / cả nhóm hàng) — trước đây phải mở từng món.
/// Món được gắn bật «cho chọn topping»; món bị gỡ mà không còn nhóm / tùy chọn thêm nào thì tắt lại
/// (tránh hộp topping trống bật lên mỗi lần bán).
/// </summary>
public static class PosToppingGroupLinker
{
    public sealed record LinkedProduct(Guid Id, string Name, string? CategoryName, Guid? CategoryId);

    /// <summary>Hàng gắn được topping: hàng hóa / dịch vụ / combo (không phải topping hay nguyên liệu).</summary>
    public static bool CanHaveToppings(PosProductType t) =>
        t is PosProductType.Goods or PosProductType.Service or PosProductType.Combo;

    public static async Task<List<LinkedProduct>> LinkedProductsAsync(ZKTecoDbContext db, Guid storeId, Guid groupId) =>
        await db.PosProductToppingGroupLinks.AsNoTracking()
            .Where(l => l.GroupId == groupId && l.StoreId == storeId && l.Deleted == null && l.IsActive
                        && l.Product != null && l.Product.Deleted == null)
            .OrderBy(l => l.Product!.Name)
            .Select(l => new LinkedProduct(l.ProductId, l.Product!.Name,
                l.Product.Category != null ? l.Product.Category.Name : null, l.Product.CategoryId))
            .ToListAsync();

    /// <summary>
    /// Đặt lại danh sách món gắn nhóm = <paramref name="productIds"/> ∪ mọi món thuộc <paramref name="categoryIds"/>.
    /// Trả số liên kết thêm / gỡ. Không SaveChanges — để controller lưu cùng giao dịch.
    /// </summary>
    public static async Task<(int Added, int Removed, int Total)> SetLinksAsync(
        ZKTecoDbContext db, Guid storeId, Guid groupId,
        IReadOnlyCollection<Guid>? productIds, IReadOnlyCollection<Guid>? categoryIds, string? actor)
    {
        var ids = (productIds ?? []).ToHashSet();
        var cats = (categoryIds ?? []).ToList();
        var candidates = await db.PosProducts.AsTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null
                        && (ids.Contains(p.Id) || (p.CategoryId != null && cats.Contains(p.CategoryId.Value))))
            .ToListAsync();
        var want = candidates.Where(p => CanHaveToppings(p.ProductType)).ToDictionary(p => p.Id);

        var links = await db.PosProductToppingGroupLinks.AsTracking()
            .Where(l => l.GroupId == groupId && l.StoreId == storeId && l.Deleted == null)
            .ToListAsync();
        var now = DateTime.UtcNow;
        int added = 0, removed = 0;
        var unlinked = new List<Guid>();
        foreach (var l in links.Where(l => !want.ContainsKey(l.ProductId)))
        {
            l.Deleted = now;
            l.DeletedBy = actor;
            l.IsActive = false;
            unlinked.Add(l.ProductId);
            removed++;
        }
        var linked = links.Where(l => want.ContainsKey(l.ProductId)).Select(l => l.ProductId).ToHashSet();
        foreach (var p in want.Values)
        {
            if (!linked.Contains(p.Id))
            {
                db.PosProductToppingGroupLinks.Add(new PosProductToppingGroupLink
                {
                    Id = Guid.NewGuid(), StoreId = storeId, ProductId = p.Id, GroupId = groupId,
                    IsActive = true, CreatedBy = actor,
                });
                added++;
            }
            if (!p.AllowToppings)
            {
                p.AllowToppings = true;
                p.UpdatedAt = now;
                p.UpdatedBy = actor;
            }
        }

        if (unlinked.Count > 0)
        {
            // Còn nhóm khác / tùy chọn thêm thì giữ «cho chọn topping».
            var stillHas = (await db.PosProductToppingGroupLinks.AsNoTracking()
                    .Where(l => unlinked.Contains(l.ProductId) && l.GroupId != groupId && l.StoreId == storeId
                                && l.Deleted == null && l.IsActive)
                    .Select(l => l.ProductId)
                    .Concat(db.PosProductToppingOptions.AsNoTracking()
                        .Where(o => unlinked.Contains(o.ProductId) && o.StoreId == storeId && o.Deleted == null && o.IsActive)
                        .Select(o => o.ProductId))
                    .ToListAsync())
                .ToHashSet();
            foreach (var p in await db.PosProducts.AsTracking()
                         .Where(p => unlinked.Contains(p.Id) && p.StoreId == storeId).ToListAsync())
            {
                if (stillHas.Contains(p.Id) || !p.AllowToppings) continue;
                p.AllowToppings = false;
                p.UpdatedAt = now;
                p.UpdatedBy = actor;
            }
        }
        return (added, removed, want.Count);
    }
}
