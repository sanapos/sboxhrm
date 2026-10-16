using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Chính sách công nợ khách của cửa hàng (PosStoreSellSettings.ExtraJson → "debt"):
/// hạn mức nợ mặc định, hạn thanh toán (ngày), có chặn bán nợ khi vượt hạn mức / có đơn quá hạn hay chỉ cảnh báo.
/// Khách có hạn mức / hạn riêng (PosCustomer.DebtLimit / PaymentTermDays) thì dùng số riêng.
/// </summary>
internal sealed record PosDebtPolicy(decimal? DefaultLimit, int TermDays, bool BlockOverLimit, bool BlockOverdue)
{
    public static readonly PosDebtPolicy None = new(null, 0, false, false);

    public static PosDebtPolicy Parse(string? extraJson)
    {
        if (string.IsNullOrWhiteSpace(extraJson)) return None;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            if (!doc.RootElement.TryGetProperty("debt", out var d) || d.ValueKind != JsonValueKind.Object) return None;
            decimal? limit = d.TryGetProperty("defaultLimit", out var l) && l.ValueKind == JsonValueKind.Number && l.GetDecimal() > 0
                ? l.GetDecimal() : null;
            var term = d.TryGetProperty("termDays", out var t) && t.ValueKind == JsonValueKind.Number ? Math.Max(0, t.GetInt32()) : 0;
            bool B(string k) => d.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.True;
            return new PosDebtPolicy(limit, term, B("blockOverLimit"), B("blockOverdue"));
        }
        catch
        {
            return None;
        }
    }

    public static async Task<PosDebtPolicy> LoadAsync(ZKTecoDbContext db, Guid storeId) =>
        Parse(await db.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => s.ExtraJson).FirstOrDefaultAsync());

    /// <summary>Hạn mức của khách: riêng (>0) → mặc định cửa hàng → không giới hạn (null).</summary>
    public decimal? LimitFor(PosCustomer c) => c.DebtLimit is > 0 ? c.DebtLimit : DefaultLimit;

    /// <summary>Hạn thanh toán (ngày) của khách: riêng (>0) → mặc định cửa hàng; 0 = không theo dõi quá hạn.</summary>
    public int TermFor(PosCustomer c) => c.PaymentTermDays is > 0 ? c.PaymentTermDays.Value : TermDays;

    /// <summary>Đơn nợ lâu nhất của khách (số ngày theo giờ VN, số đơn).</summary>
    public static async Task<(int OldestDays, string? OldestNo)> OldestOpenAsync(ZKTecoDbContext db, Guid storeId, Guid customerId)
    {
        var oldest = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.CustomerId == customerId && o.Deleted == null &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee > o.PaidAmount)
            .OrderBy(o => o.SaleDate ?? o.CreatedAt)
            .Select(o => new { o.OrderNo, At = o.SaleDate ?? o.CreatedAt })
            .FirstOrDefaultAsync();
        return oldest == null ? (0, null) : (AgeDaysVn(oldest.At), oldest.OrderNo);
    }

    /// <summary>Số ngày từ ngày (giờ VN) của mốc UTC tới hôm nay (giờ VN).</summary>
    public static int AgeDaysVn(DateTime utc) =>
        Math.Max(0, (VnTimeHelper.NowVn().Date - VnTimeHelper.UtcToVn(utc).Date).Days);

    /// <summary>
    /// Kiểm tra lúc hoàn tất đơn có ghi nợ: vượt hạn mức / có đơn quá hạn → lỗi nếu cửa hàng bật chặn.
    /// Chỉ cảnh báo (không chặn) thì màn bán tự hỏi xác nhận trước khi gửi.
    /// </summary>
    public static async Task<string?> CheckSaleAsync(ZKTecoDbContext db, Guid storeId, PosSaleOrder order)
    {
        if (!order.CustomerId.HasValue) return null;
        var due = order.PayableTotal - order.PaidAmount;
        if (due <= 0.5m) return null;
        var policy = await LoadAsync(db, storeId);
        if (!policy.BlockOverLimit && !policy.BlockOverdue) return null;
        var c = await db.PosCustomers.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == order.CustomerId && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return null;
        var limit = policy.LimitFor(c);
        if (policy.BlockOverLimit && limit is decimal lim && c.CurrentDebt + due > lim)
            return $"Vượt hạn mức nợ của «{c.Name}»: nợ hiện tại {c.CurrentDebt:N0}đ + đơn này {due:N0}đ > hạn mức {lim:N0}đ. " +
                   "Thu thêm tiền / thu nợ cũ, hoặc nâng hạn mức ở hồ sơ khách.";
        var term = policy.TermFor(c);
        if (policy.BlockOverdue && term > 0)
        {
            var (days, no) = await OldestOpenAsync(db, storeId, c.Id);
            if (days > term)
                return $"«{c.Name}» có đơn nợ quá hạn ({no}, {days} ngày > hạn {term} ngày) — thu nợ trước khi bán nợ thêm.";
        }
        return null;
    }
}
