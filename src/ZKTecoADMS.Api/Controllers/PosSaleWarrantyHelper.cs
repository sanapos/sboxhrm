using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

public static class PosSaleWarrantyHelper
{
    public record SerialInput(string SerialNumber, string? Imei = null);

    public static bool NeedsRegistration(PosProduct product) =>
        product.ProductType == PosProductType.Goods &&
        (product.RequiresSerial || (product.WarrantyMonths ?? 0) > 0);

    public static async Task<string?> ValidateSerialsAsync(
        ZKTecoDbContext db,
        Guid storeId,
        IReadOnlyList<(PosSalesController.SaleLineDto Dto, PosProduct Product)> lines)
    {
        var normalized = new List<(PosSalesController.SaleLineDto Dto, PosProduct Product, List<SerialInput> Serials)>();

        foreach (var (dto, product) in lines)
        {
            if (!NeedsRegistration(product)) continue;

            var serials = NormalizeSerialInputs(dto.SerialNumbers, dto.SerialImeis);
            var unitCount = (int)Math.Ceiling(dto.Qty);
            if (product.RequiresSerial)
            {
                if (dto.Qty != unitCount)
                    return $"Số lượng phải là số nguyên khi nhập seri: {product.Name}";
                if (serials.Count != unitCount)
                    return $"Nhập đủ {unitCount} seri cho {product.Name}";
            }
            else if (serials.Count == 0)
            {
                for (var i = 0; i < unitCount; i++)
                    serials.Add(new SerialInput(BuildAutoSerial(product.ProductCode, i + 1)));
            }
            else if (serials.Count != unitCount)
            {
                return $"Số seri không khớp số lượng: {product.Name}";
            }

            foreach (var s in serials)
            {
                if (string.IsNullOrWhiteSpace(s.SerialNumber))
                    return $"Seri không được để trống: {product.Name}";
            }

            normalized.Add((dto, product, serials));
        }

        if (normalized.Count == 0) return null;

        var allSerials = normalized
            .SelectMany(x => x.Serials.Select(s => s.SerialNumber.Trim()))
            .ToList();
        if (allSerials.Count != allSerials.Distinct(StringComparer.OrdinalIgnoreCase).Count())
            return "Seri máy bị trùng trong đơn hàng";

        var dupes = await db.PosProductWarrantyRegistrations.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null &&
                        r.Status == PosWarrantyStatus.Active &&
                        allSerials.Contains(r.SerialNumber))
            .Select(r => r.SerialNumber)
            .ToListAsync();
        if (dupes.Count > 0)
            return $"Seri đã được đăng ký bảo hành: {string.Join(", ", dupes)}";

        return null;
    }

    public static async Task RegisterOnSaleAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        IReadOnlyList<PosSaleOrderLine> orderLines,
        IReadOnlyList<PosSalesController.SaleLineDto> dtoLines,
        IReadOnlyDictionary<Guid, PosProduct> products,
        string createdBy)
    {
        if (orderLines.Count != dtoLines.Count) return;

        var saleDate = order.SaleDate ?? DateTime.UtcNow;

        for (var i = 0; i < dtoLines.Count; i++)
        {
            var dto = dtoLines[i];
            var line = orderLines[i];
            if (!products.TryGetValue(dto.ProductId, out var product) || !NeedsRegistration(product))
                continue;

            var serials = NormalizeSerialInputs(dto.SerialNumbers, dto.SerialImeis);
            var unitCount = (int)Math.Ceiling(dto.Qty);
            if (serials.Count == 0)
            {
                for (var u = 0; u < unitCount; u++)
                    serials.Add(new SerialInput(BuildAutoSerial(order.OrderNo, i + 1, u + 1)));
            }

            var months = product.WarrantyMonths ?? 0;
            foreach (var s in serials)
            {
                var serial = s.SerialNumber.Trim();
                db.PosProductWarrantyRegistrations.Add(new PosProductWarrantyRegistration
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    SaleOrderId = order.Id,
                    SaleOrderLineId = line.Id,
                    ProductId = line.ProductId,
                    VariantId = line.VariantId,
                    CustomerId = order.CustomerId,
                    SerialNumber = serial,
                    Imei = string.IsNullOrWhiteSpace(s.Imei) ? null : s.Imei.Trim(),
                    WarrantyMonths = months,
                    SaleDate = saleDate,
                    WarrantyExpiry = months > 0 ? saleDate.AddMonths(months) : saleDate,
                    Status = PosWarrantyStatus.Active,
                    IsActive = true,
                    CreatedBy = createdBy,
                });
            }
        }

        await Task.CompletedTask;
    }

    public static async Task VoidOrderAsync(
        ZKTecoDbContext db, Guid storeId, Guid saleOrderId, string updatedBy)
    {
        var now = DateTime.UtcNow;
        var regs = await db.PosProductWarrantyRegistrations
            .Where(r => r.StoreId == storeId && r.SaleOrderId == saleOrderId &&
                        r.Deleted == null && r.Status == PosWarrantyStatus.Active)
            .ToListAsync();
        foreach (var r in regs)
        {
            r.Status = PosWarrantyStatus.Voided;
            r.UpdatedAt = now;
            r.UpdatedBy = updatedBy;
        }
    }

    public static async Task MarkReturnedAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid saleOrderId,
        IReadOnlyList<(Guid ProductId, Guid? VariantId, decimal Qty)> returnLines,
        string updatedBy)
    {
        var now = DateTime.UtcNow;
        foreach (var (productId, variantId, qty) in returnLines)
        {
            var toReturn = (int)Math.Ceiling(qty);
            if (toReturn <= 0) continue;

            var active = await db.PosProductWarrantyRegistrations
                .Where(r => r.StoreId == storeId && r.SaleOrderId == saleOrderId &&
                            r.ProductId == productId && r.VariantId == variantId &&
                            r.Deleted == null && r.Status == PosWarrantyStatus.Active)
                .OrderBy(r => r.CreatedAt)
                .Take(toReturn)
                .ToListAsync();

            foreach (var r in active)
            {
                r.Status = PosWarrantyStatus.Returned;
                r.UpdatedAt = now;
                r.UpdatedBy = updatedBy;
            }
        }
    }

    public static async Task UnmarkReturnedAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid saleOrderId,
        IReadOnlyList<(Guid ProductId, Guid? VariantId, decimal Qty)> returnLines,
        string updatedBy)
    {
        var now = DateTime.UtcNow;
        foreach (var (productId, variantId, qty) in returnLines)
        {
            var toRestore = (int)Math.Ceiling(qty);
            if (toRestore <= 0) continue;

            var returned = await db.PosProductWarrantyRegistrations
                .Where(r => r.StoreId == storeId && r.SaleOrderId == saleOrderId &&
                            r.ProductId == productId && r.VariantId == variantId &&
                            r.Deleted == null && r.Status == PosWarrantyStatus.Returned)
                .OrderByDescending(r => r.UpdatedAt)
                .Take(toRestore)
                .ToListAsync();

            foreach (var r in returned)
            {
                r.Status = PosWarrantyStatus.Active;
                r.UpdatedAt = now;
                r.UpdatedBy = updatedBy;
            }
        }
    }

    public static async Task<Dictionary<Guid, List<string>>> GetSerialsByLineAsync(
        ZKTecoDbContext db, Guid storeId, IEnumerable<Guid> lineIds)
    {
        var ids = lineIds.Distinct().ToList();
        if (ids.Count == 0) return new Dictionary<Guid, List<string>>();

        var rows = await db.PosProductWarrantyRegistrations.AsNoTracking()
            .Where(r => r.StoreId == storeId && ids.Contains(r.SaleOrderLineId) && r.Deleted == null)
            .OrderBy(r => r.SerialNumber)
            .Select(r => new { r.SaleOrderLineId, r.SerialNumber, r.Imei, r.Status })
            .ToListAsync();

        return rows.GroupBy(r => r.SaleOrderLineId)
            .ToDictionary(
                g => g.Key,
                g => g.Select(x =>
                {
                    var label = x.SerialNumber;
                    if (!string.IsNullOrWhiteSpace(x.Imei))
                        label += $" (IMEI: {x.Imei})";
                    if (x.Status != PosWarrantyStatus.Active)
                        label += $" [{x.Status}]";
                    return label;
                }).ToList());
    }

    private static List<SerialInput> NormalizeSerialInputs(
        List<string>? serials, List<string>? imeis)
    {
        if (serials == null || serials.Count == 0) return [];

        var result = new List<SerialInput>();
        for (var i = 0; i < serials.Count; i++)
        {
            var sn = serials[i]?.Trim();
            if (string.IsNullOrEmpty(sn)) continue;
            string? imei = null;
            if (imeis != null && i < imeis.Count)
                imei = string.IsNullOrWhiteSpace(imeis[i]) ? null : imeis[i].Trim();
            result.Add(new SerialInput(sn, imei));
        }

        return result;
    }

    private static string BuildAutoSerial(string prefix, int index) =>
        $"AUTO-{prefix}-{index}";

    private static string BuildAutoSerial(string orderNo, int lineIndex, int unitIndex) =>
        $"AUTO-{orderNo}-L{lineIndex}-{unitIndex}";
}
