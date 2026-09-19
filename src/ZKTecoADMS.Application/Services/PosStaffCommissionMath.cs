using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Services;

/// <summary>Phân bổ doanh thu combo + tính hoa hồng NV — client Flutter phải khớp khi preview.</summary>
public static class PosStaffCommissionMath
{
    public record ComponentShare(Guid ProductId, decimal Qty, decimal CatalogPrice, decimal Revenue);

    public static decimal CalcCommission(
        PosCommissionMode mode,
        decimal percent,
        decimal fixedPerUnit,
        decimal revenue,
        decimal qty,
        decimal catalogPrice)
    {
        if (qty <= 0) return 0;
        var amount = mode switch
        {
            PosCommissionMode.PercentOfLine => revenue * Math.Max(0, percent) / 100m,
            PosCommissionMode.FixedPerUnit => Math.Max(0, fixedPerUnit) * qty,
            PosCommissionMode.PercentOfCatalog =>
                Math.Max(0, catalogPrice) * qty * Math.Max(0, percent) / 100m,
            _ => 0m,
        };
        return Math.Round(Math.Max(0, amount), 0, MidpointRounding.AwayFromZero);
    }

    /// <summary>
    /// Chia LineTotal combo theo giá niêm yết × SL thành phần; hết giá thì chia đều.
    /// Phần dư làm tròn dồn vào dòng cuối.
    /// </summary>
    public static List<ComponentShare> AllocateComboRevenue(
        decimal lineTotal,
        decimal comboQty,
        IReadOnlyList<(Guid ProductId, decimal ComponentQty, decimal CatalogPrice)> components)
    {
        var result = new List<ComponentShare>(components.Count);
        if (components.Count == 0 || comboQty <= 0)
            return result;

        var qtyList = components
            .Select(c => Math.Max(0, c.ComponentQty) * comboQty)
            .ToList();
        var weights = components
            .Select((c, i) => Math.Max(0, c.CatalogPrice) * qtyList[i])
            .ToList();
        var weightSum = weights.Sum();
        var remaining = Math.Max(0, lineTotal);

        for (var i = 0; i < components.Count; i++)
        {
            decimal share;
            if (i == components.Count - 1)
                share = remaining;
            else if (weightSum > 0)
                share = Math.Round(lineTotal * weights[i] / weightSum, 0, MidpointRounding.AwayFromZero);
            else
                share = Math.Round(lineTotal / components.Count, 0, MidpointRounding.AwayFromZero);
            if (share > remaining) share = remaining;
            remaining -= share;
            result.Add(new ComponentShare(
                components[i].ProductId, qtyList[i], Math.Max(0, components[i].CatalogPrice), share));
        }

        return result;
    }
}
