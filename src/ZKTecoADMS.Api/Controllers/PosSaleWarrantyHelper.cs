using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

public static class PosSaleWarrantyHelper
{
    public record SerialInput(string SerialNumber, string? Imei = null);

    /// <summary>Chuẩn hóa seri: bỏ khoảng trắng đầu/cuối, viết hoa — để unique index và tra cứu hoạt động đúng.</summary>
    public static string NormalizeSerial(string? serial) => (serial ?? string.Empty).Trim().ToUpperInvariant();

    public static bool NeedsRegistration(PosProduct product) =>
        product.ProductType == PosProductType.Goods &&
        (product.RequiresSerial || (product.WarrantyMonths ?? 0) > 0);

    public static async Task<string?> ValidateSerialsAsync(
        ZKTecoDbContext db,
        Guid storeId,
        IReadOnlyList<(PosSalesController.SaleLineDto Dto, PosProduct Product)> lines,
        Guid? branchId = null,
        Guid? hqBranchId = null)
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
            .SelectMany(x => x.Serials.Select(s => NormalizeSerial(s.SerialNumber)))
            .ToList();
        if (allSerials.Count != allSerials.Distinct().Count())
            return "Seri máy bị trùng trong đơn hàng";

        // So khớp không phân biệt hoa/thường (dữ liệu cũ có thể đã lưu chữ thường).
        var dupes = await db.PosProductWarrantyRegistrations.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null &&
                        r.Status == PosWarrantyStatus.Active &&
                        allSerials.Contains(r.SerialNumber.ToUpper()))
            .Select(r => r.SerialNumber)
            .ToListAsync();
        if (dupes.Count > 0)
            return $"Seri đã được đăng ký bảo hành: {string.Join(", ", dupes)}";

        // Hàng đã nhập seri vào kho: chỉ được bán đúng các máy đang trong kho.
        var stockErr = await PosSerialRegistry.ValidateForSaleAsync(db, storeId,
            normalized.Select(x => (x.Product, x.Serials.Select(s => NormalizeSerial(s.SerialNumber)).ToList())).ToList(),
            branchId, hqBranchId);
        if (stockErr != null) return stockErr;

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
                // Dùng order.Id (bất biến) thay vì order.OrderNo — OrderNo có thể bị đổi lại khi
                // CreateSale retry do đụng unique index (IX_PosSaleOrders_StoreId_OrderNo), nhưng
                // entity WarrantyRegistration này đã được add vào change tracker với seri cũ từ
                // trước đó, không được cập nhật lại → seri "AUTO-{OrderNo cũ}..." bị trùng với đơn
                // khác đã chiếm OrderNo đó và insert thành công trước, gây lỗi 500 không được catch.
                for (var u = 0; u < unitCount; u++)
                    serials.Add(new SerialInput(BuildAutoSerial(order.Id, i + 1, u + 1)));
            }

            if (product.RequiresSerial)
                await PosSerialRegistry.MarkSoldAsync(db, storeId, order.Id, product.Id,
                    serials.Select(x => x.SerialNumber), saleDate);

            var months = product.WarrantyMonths ?? 0;
            foreach (var s in serials)
            {
                var serial = NormalizeSerial(s.SerialNumber);
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
            .AsTracking()
            .Where(r => r.StoreId == storeId && r.SaleOrderId == saleOrderId &&
                        r.Deleted == null && r.Status == PosWarrantyStatus.Active)
            .ToListAsync();
        foreach (var r in regs)
        {
            r.Status = PosWarrantyStatus.Voided;
            r.UpdatedAt = now;
            r.UpdatedBy = updatedBy;
        }
        await PosSerialRegistry.RestoreAsync(db, storeId, saleOrderId);
    }

    /// <summary>
    /// Đánh dấu các máy khách trả. Có chọn seri → chỉ đúng các seri đó; không chọn → chỉ chấp nhận khi
    /// không mơ hồ (trả hết số máy còn bảo hành, hoặc hàng không bắt buộc seri). Trả về lỗi (null nếu ổn).
    /// </summary>
    public static async Task<string?> MarkReturnedAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid saleOrderId,
        IReadOnlyList<(Guid ProductId, Guid? VariantId, decimal Qty)> returnLines,
        IReadOnlyDictionary<(Guid ProductId, Guid? VariantId), List<string>>? serialsByKey,
        string updatedBy)
    {
        var now = DateTime.UtcNow;
        foreach (var g in returnLines.GroupBy(l => (l.ProductId, l.VariantId)))
        {
            var toReturn = g.Sum(x => (int)Math.Ceiling(x.Qty));
            if (toReturn <= 0) continue;
            var (productId, variantId) = g.Key;

            var active = await db.PosProductWarrantyRegistrations
                .AsTracking()
                .Where(r => r.StoreId == storeId && r.SaleOrderId == saleOrderId &&
                            r.ProductId == productId && r.VariantId == variantId &&
                            r.Deleted == null && r.Status == PosWarrantyStatus.Active)
                .OrderBy(r => r.CreatedAt)
                .ToListAsync();
            if (active.Count == 0) continue;

            List<string>? picked = null;
            serialsByKey?.TryGetValue((productId, variantId), out picked);
            var wanted = (picked ?? [])
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Select(NormalizeSerial).Distinct().ToList();

            List<PosProductWarrantyRegistration> toMark;
            if (wanted.Count > 0)
            {
                if (wanted.Count != toReturn)
                    return $"Chọn đúng {toReturn} seri máy trả lại (đang chọn {wanted.Count})";
                toMark = active.Where(r => wanted.Contains(NormalizeSerial(r.SerialNumber))).ToList();
                if (toMark.Count != wanted.Count)
                {
                    var found = toMark.Select(r => NormalizeSerial(r.SerialNumber)).ToHashSet();
                    return $"Seri không thuộc đơn này hoặc đã trả/hủy: {string.Join(", ", wanted.Where(w => !found.Contains(w)))}";
                }
            }
            else
            {
                var requiresSerial = await db.PosProducts.AsNoTracking()
                    .Where(p => p.Id == productId).Select(p => p.RequiresSerial).FirstOrDefaultAsync();
                if (requiresSerial && active.Count > toReturn)
                    return "Đơn có nhiều máy — hãy chọn seri máy khách trả lại";
                toMark = active.Take(toReturn).ToList();
            }

            foreach (var r in toMark)
            {
                r.Status = PosWarrantyStatus.Returned;
                r.UpdatedAt = now;
                r.UpdatedBy = updatedBy;
            }
            await PosSerialRegistry.RestoreAsync(db, storeId, saleOrderId, toMark.Select(r => r.SerialNumber));
        }
        return null;
    }

    /// <summary>Hoàn bảo hành khi hủy phiếu trả. Lỗi nếu seri đó đã được bán/đăng ký bảo hành lại cho đơn khác.</summary>
    public static async Task<string?> UnmarkReturnedAsync(
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
                .AsTracking()
                .Where(r => r.StoreId == storeId && r.SaleOrderId == saleOrderId &&
                            r.ProductId == productId && r.VariantId == variantId &&
                            r.Deleted == null && r.Status == PosWarrantyStatus.Returned)
                .OrderByDescending(r => r.UpdatedAt)
                .Take(toRestore)
                .ToListAsync();
            if (returned.Count == 0) continue;

            var ids = returned.Select(r => r.Id).ToList();
            var serials = returned.Select(r => NormalizeSerial(r.SerialNumber)).ToList();
            var clash = await db.PosProductWarrantyRegistrations.AsNoTracking()
                .Where(r => r.StoreId == storeId && r.Deleted == null && r.Status == PosWarrantyStatus.Active
                            && !ids.Contains(r.Id) && serials.Contains(r.SerialNumber.ToUpper()))
                .Select(r => r.SerialNumber)
                .ToListAsync();
            if (clash.Count > 0)
                return $"Không thể hủy trả: seri {string.Join(", ", clash)} đã được bán / đăng ký bảo hành cho đơn khác";

            foreach (var r in returned)
            {
                r.Status = PosWarrantyStatus.Active;
                r.UpdatedAt = now;
                r.UpdatedBy = updatedBy;
            }
            await PosSerialRegistry.MarkSoldAsync(db, storeId, saleOrderId, productId,
                returned.Select(r => r.SerialNumber), now);
        }
        return null;
    }

    public static async Task<Dictionary<Guid, List<string>>> GetSerialsByLineAsync(
        ZKTecoDbContext db, Guid storeId, IEnumerable<Guid> lineIds)
    {
        var ids = lineIds.Distinct().ToList();
        if (ids.Count == 0) return new Dictionary<Guid, List<string>>();

        var rows = await db.PosProductWarrantyRegistrations.AsNoTracking()
            .Where(r => r.StoreId == storeId && ids.Contains(r.SaleOrderLineId) && r.Deleted == null &&
                        !r.SerialNumber.StartsWith("AUTO-"))
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

    private static string BuildAutoSerial(Guid orderId, int lineIndex, int unitIndex) =>
        $"AUTO-{orderId:N}-L{lineIndex}-{unitIndex}";
}
