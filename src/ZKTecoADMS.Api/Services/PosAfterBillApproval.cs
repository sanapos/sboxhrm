using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// «Sau tạm tính cần quản lý duyệt»: khi cửa hàng bật (chỉ có tác dụng khi đang «Cho phép tạm tính»), nhân viên
/// không tự hủy món, hủy / xóa đơn, hủy hóa đơn hay thu ít hơn số tiền đã in tạm tính cho khách. Chủ / quản lý
/// làm trực tiếp được; nhân viên cần quản lý nhập mật khẩu trên máy → máy chủ cấp mã duyệt 5 phút (header
/// <see cref="Header"/>) để làm tiếp. Mã gắn với cửa hàng, ký bằng DataProtection (không sửa / giả được).
/// </summary>
public static class PosAfterBillApproval
{
    public const string Header = "X-Pos-Approval";
    public const string Purpose = "after-bill";
    /// <summary>Đầu câu lỗi — app nhận ra để mở hộp «Quản lý duyệt».</summary>
    public const string DeniedPrefix = "Cần quản lý duyệt";
    public const string ApproverItemKey = "pos-after-bill-approver";
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(5);
    /// <summary>Thu thấp hơn tạm tính dưới mức này coi như làm tròn.</summary>
    public const decimal Tolerance = 1000m;

    const string ProtectorPurpose = "ZKTecoADMS.Pos.AfterBillApproval.v1";

    static readonly string[] ManagerRoles =
        ["StoreOwner", "Admin", "Director", "SuperAdmin", "Manager", "DepartmentHead", "Agent"];

    public static bool IsManagerRole(string? role) =>
        role != null && ManagerRoles.Contains(role, StringComparer.OrdinalIgnoreCase);

    /// <summary>Đọc ExtraJson «afterBillApproval.enabled» (mặc định TẮT).</summary>
    public static bool ParseEnabled(string? extraJson)
    {
        if (string.IsNullOrWhiteSpace(extraJson)) return false;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            return doc.RootElement.ValueKind == JsonValueKind.Object
                   && doc.RootElement.TryGetProperty("afterBillApproval", out var o)
                   && o.ValueKind == JsonValueKind.Object
                   && o.TryGetProperty("enabled", out var e)
                   && e.ValueKind == JsonValueKind.True;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    /// <summary>Chỉ có tác dụng khi cửa hàng đang cho phép tạm tính.</summary>
    public static bool Enabled(PosStoreSellSettings? s) => s?.AllowProvisionalBill == true && ParseEnabled(s.ExtraJson);

    static ITimeLimitedDataProtector Protector(IServiceProvider sp) =>
        sp.GetRequiredService<IDataProtectionProvider>().CreateProtector(ProtectorPurpose).ToTimeLimitedDataProtector();

    public static string Issue(IServiceProvider sp, Guid storeId, string approver) =>
        Protector(sp).Protect($"{storeId:N}|{approver}", Lifetime);

    /// <summary>Email quản lý đã duyệt nếu mã hợp lệ, còn hạn, đúng cửa hàng; ngược lại null.</summary>
    public static string? Validate(IServiceProvider sp, Guid storeId, string? token)
    {
        if (string.IsNullOrWhiteSpace(token)) return null;
        try
        {
            var raw = Protector(sp).Unprotect(token.Trim());
            var i = raw.IndexOf('|');
            if (i <= 0 || raw[..i] != storeId.ToString("N")) return null;
            var who = raw[(i + 1)..];
            return who.Length == 0 ? null : who;
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>
    /// Kiểm tra một thao tác giảm tiền. Trả câu lỗi khi phải có quản lý duyệt; null = được làm
    /// (chưa bật / chưa tạm tính / người gọi là quản lý / có mã duyệt hợp lệ — người duyệt lưu vào HttpContext.Items).
    /// </summary>
    public static async Task<string?> DenyAsync(
        ZKTecoDbContext db, HttpContext http, Guid storeId, Guid? sessionId, string? callerRole, string action,
        bool alreadyAfterBill = false)
    {
        if (IsManagerRole(callerRole)) return null;
        if (!alreadyAfterBill)
        {
            if (sessionId is not Guid sid) return null;
            var after = await db.PosResourceSessions.AsNoTracking()
                .AnyAsync(s => s.Id == sid && s.StoreId == storeId && s.Deleted == null
                    && (s.BillRequested || s.BillRequestedAt != null));
            if (!after) return null;
        }
        var settings = await db.PosStoreSellSettings.AsNoTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null);
        if (!Enabled(settings)) return null;
        var approver = Validate(http.RequestServices, storeId, http.Request.Headers[Header].ToString());
        if (approver != null)
        {
            http.Items[ApproverItemKey] = approver;
            return null;
        }
        return DenyPrefixed(action);
    }

    static string DenyPrefixed(string action) =>
        $"{DeniedPrefix}: {action} sau khi đã in tạm tính cho khách. Gọi chủ / quản lý nhập mật khẩu để duyệt.";

    /// <summary>
    /// Thanh toán: tổng tiền thu của bàn (đơn này + các hóa đơn tách đã thu) thấp hơn số tiền lớn nhất đã in
    /// tạm tính → cần duyệt.
    /// </summary>
    public static async Task<string?> DenyPaymentBelowBillAsync(
        ZKTecoDbContext db, HttpContext http, Guid storeId, PosSaleOrder order, string? callerRole)
    {
        if (order.ResourceSessionId is not Guid sid || IsManagerRole(callerRole)) return null;
        var printed = await db.PosResourceSessions.AsNoTracking()
            .Where(s => s.Id == sid && s.StoreId == storeId && s.Deleted == null)
            .Select(s => s.BillRequestedTotal)
            .FirstOrDefaultAsync();
        if (printed is not > 0) return null;
        var otherPaid = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.Id != order.Id
                && o.ResourceSessionId == sid && o.Status == PosSaleOrderStatus.Completed)
            .SumAsync(o => (decimal?)o.Total) ?? 0m;
        var stillOpen = await db.PosSaleOrders.AsNoTracking()
            .AnyAsync(o => o.StoreId == storeId && o.Deleted == null && o.Id != order.Id
                && o.ResourceSessionId == sid && o.Status == PosSaleOrderStatus.Draft && o.Total > 0);
        // Còn hóa đơn tách chưa thu → chưa so được tổng (thu nốt hóa đơn cuối mới kiểm).
        if (stillOpen) return null;
        var paid = otherPaid + order.Total;
        if (paid >= printed.Value - Tolerance) return null;
        return await DenyAsync(db, http, storeId, sid, callerRole,
            $"thu {Money(paid)} thấp hơn phiếu tạm tính {Money(printed.Value)}", alreadyAfterBill: true);
    }

    static string Money(decimal v) =>
        v.ToString("#,##0", System.Globalization.CultureInfo.InvariantCulture).Replace(',', '.') + "đ";

    /// <summary>Ghi chú «Quản lý duyệt: …» cho nhật ký hủy / trả (nếu có).</summary>
    public static string? ApproverNote(HttpContext http, string? existing)
    {
        if (http.Items[ApproverItemKey] is not string who) return existing;
        var note = $"Quản lý duyệt: {who}";
        return string.IsNullOrWhiteSpace(existing) ? note : $"{existing} · {note}";
    }
}
