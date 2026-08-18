using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Unique (ComboProductId, ComponentProductId) gồm cả dòng soft-delete —
/// không insert lại cùng cặp, revive dòng cũ.
/// </summary>
internal static class PosProductComboLinePersistHelper
{
    public static async Task ReplaceLinesAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid comboProductId,
        IReadOnlyList<(Guid ComponentId, decimal Qty)> lines,
        string userEmail)
    {
        var now = DateTime.UtcNow;
        var wanted = lines
            .Where(x => x.ComponentId != Guid.Empty && x.Qty > 0)
            .GroupBy(x => x.ComponentId)
            .ToDictionary(g => g.Key, g => g.Sum(x => x.Qty));

        var existing = await db.PosProductComboLines
            .IgnoreQueryFilters()
            .Where(x => x.StoreId == storeId && x.ComboProductId == comboProductId)
            .ToListAsync();

        foreach (var row in existing)
        {
            if (wanted.TryGetValue(row.ComponentProductId, out var qty))
            {
                row.Qty = qty;
                row.IsActive = true;
                row.Deleted = null;
                row.DeletedBy = null;
                row.UpdatedAt = now;
                row.UpdatedBy = userEmail;
                wanted.Remove(row.ComponentProductId);
            }
            else if (row.Deleted == null)
            {
                row.IsActive = false;
                row.Deleted = now;
                row.DeletedBy = userEmail;
                row.UpdatedAt = now;
                row.UpdatedBy = userEmail;
            }
        }

        foreach (var (componentId, qty) in wanted)
        {
            db.PosProductComboLines.Add(new PosProductComboLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ComboProductId = comboProductId,
                ComponentProductId = componentId,
                Qty = qty,
                IsActive = true,
                CreatedBy = userEmail,
            });
        }
    }
}
