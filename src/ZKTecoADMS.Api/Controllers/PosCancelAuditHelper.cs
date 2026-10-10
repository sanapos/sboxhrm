using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Ghi «Lịch sử hủy / trả» cho các đường hủy trước đây không để lại dấu vết:
/// hủy đơn tạm đang có món (trả bàn / dọn bàn), xóa đơn, hủy phiếu trả hàng.
/// Các đường này cập nhật thẳng DB (ExecuteUpdate) nên cũng lọt khỏi «Lịch sử thao tác» — ghi bù vào đó luôn.
/// </summary>
internal static class PosCancelAuditHelper
{
    public const string KitchenVoid = "KitchenVoid";
    public const string SaleCancel = "SaleCancel";
    public const string SaleReturn = "SaleReturn";
    public const string DraftCancel = "DraftCancel";
    public const string OrderDelete = "OrderDelete";
    public const string ReturnCancel = "ReturnCancel";

    public static readonly string[] All = [KitchenVoid, SaleCancel, SaleReturn, DraftCancel, OrderDelete, ReturnCancel];

    /// <summary>
    /// Thêm một dòng nhật ký, cắt chữ theo độ dài cột (Lý do 80, Tên hàng 200, Ghi chú 500…).
    /// Trước đây lý do / tên hàng dài làm lỗi 500: hủy đơn đã hủy xong nhưng báo lỗi, trả hàng thì hỏng cả giao dịch.
    /// </summary>
    public static PosCancelReturnAudit Add(ZKTecoDbContext db, PosCancelReturnAudit a)
    {
        a.ActionType = Clip(a.ActionType, 40) ?? "";
        a.Reason = Clip(a.Reason, 80);
        a.DetailNote = Clip(a.DetailNote, 500);
        a.OrderNo = Clip(a.OrderNo, 40);
        a.ResourceName = Clip(a.ResourceName, 120);
        a.ProductName = Clip(a.ProductName, 200);
        a.UnitName = Clip(a.UnitName, 40);
        a.Actor = Clip(a.Actor, 200);
        a.DeviceName = Clip(a.DeviceName, 120);
        db.PosCancelReturnAudits.Add(a);
        return a;
    }

    /// <summary>Phiếu hủy món bếp: cùng giới hạn cột.</summary>
    public static void ClipSlip(PosKitchenVoidSlip s)
    {
        s.ProductName = Clip(s.ProductName, 200) ?? "";
        s.OrderNo = Clip(s.OrderNo, 40);
        s.ResourceName = Clip(s.ResourceName, 120);
        s.UnitName = Clip(s.UnitName, 40);
        s.LineNote = Clip(s.LineNote, 300);
        s.Reason = Clip(s.Reason, 80);
        s.DetailNote = Clip(s.DetailNote, 500);
        s.VoidedBy = Clip(s.VoidedBy, 200);
        s.DeviceName = Clip(s.DeviceName, 120);
    }

    public static string? Clip(string? v, int max)
    {
        if (v == null) return null;
        v = v.Trim();
        if (v.Length == 0) return null;
        return v.Length <= max ? v : v[..(max - 1)] + "…";
    }

    /// <summary>Tóm tắt món: «Cà phê sữa, Trà đào +3 món».</summary>
    public static string? ProductSummary(IReadOnlyList<string> names, int take = 3)
    {
        var list = names.Where(n => !string.IsNullOrWhiteSpace(n)).Select(n => n.Trim()).ToList();
        if (list.Count == 0) return null;
        var head = string.Join(", ", list.Take(take));
        return Clip(list.Count > take ? $"{head} +{list.Count - take} món" : head, 200);
    }

    /// <summary>Tên bàn / phòng (đơn chỉ lưu id).</summary>
    public static async Task<string?> ResourceNameAsync(ZKTecoDbContext db, Guid storeId, Guid? resourceId)
    {
        if (resourceId is not Guid rid) return null;
        return await db.PosServiceResources.AsNoTracking()
            .Where(r => r.Id == rid && r.StoreId == storeId)
            .Select(r => r.Name)
            .FirstOrDefaultAsync();
    }

    /// <summary>Phiên bàn đã in tạm tính chưa (hủy sau tạm tính = cần soát).</summary>
    public static async Task<bool> AfterProvisionalBillAsync(ZKTecoDbContext db, Guid storeId, Guid? sessionId)
    {
        if (sessionId is not Guid sid) return false;
        return await db.PosResourceSessions.AsNoTracking()
            .AnyAsync(s => s.Id == sid && s.StoreId == storeId && s.Deleted == null && s.BillRequested);
    }

    /// <summary>
    /// Hủy / xóa đơn tạm đang có món. Đơn trống (HĐ tách trống, bàn chưa gọi món) không ghi — không có gì để soát.
    /// </summary>
    public static async Task AddOrderRemovalAsync(
        ZKTecoDbContext db,
        HttpContext http,
        Guid storeId,
        PosSaleOrder order,
        string actionType,
        string? actor,
        string? reason = null)
    {
        var lines = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.SaleOrderId == order.Id && l.Deleted == null)
            .Select(l => new { l.ProductName, l.Qty, l.LineTotal })
            .ToListAsync();
        MarkDeleted(http, order);
        if (lines.Count == 0 && order.Total <= 0) return;

        var now = DateTime.UtcNow;
        Add(db, new PosCancelReturnAudit
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ActionType = actionType,
            Reason = reason,
            AfterProvisionalBill = await AfterProvisionalBillAsync(db, storeId, order.ResourceSessionId),
            SaleOrderId = order.Id,
            OrderNo = order.OrderNo,
            ResourceSessionId = order.ResourceSessionId,
            ServiceResourceId = order.ServiceResourceId,
            ResourceName = await ResourceNameAsync(db, storeId, order.ServiceResourceId),
            ProductName = ProductSummary(lines.Select(l => l.ProductName).ToList()),
            Qty = lines.Sum(l => l.Qty),
            Amount = lines.Count > 0 ? lines.Sum(l => l.LineTotal) : order.Total,
            OccurredAt = now,
            Actor = actor,
            IsActive = true,
            CreatedAt = now,
            CreatedBy = actor,
        });
    }

    /// <summary>ExecuteUpdate không qua ChangeTracker → tự báo «Xóa đơn …» cho Lịch sử thao tác.</summary>
    public static void MarkDeleted(HttpContext http, PosSaleOrder order) =>
        Filters.ActivityTrail.Deleted(http, nameof(PosSaleOrder), order.Id, order.OrderNo);
}
