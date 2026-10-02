using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Tình trạng thiết lập cho trang chủ Thiết lập: mục nào chưa cấu hình / cần chú ý.
/// Khóa theo mã mục của danh mục Thiết lập ở app (shift, holiday, device…). Chỉ trả số đếm, không trả dữ liệu.
/// </summary>
[ApiController]
[Route("api/settings-health")]
[Authorize(Policy = PolicyNames.AtLeastEmployee)]
public class SettingsHealthController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    /// <summary>ok = đã xong · todo = chưa cấu hình · warn = cần chú ý · info = đang dùng mặc định.</summary>
    public sealed record HealthItem(string Key, string Status, string Text);

    public static HealthItem Shift(int active) => active == 0
        ? new("shift", "todo", "Chưa có ca làm việc")
        : new("shift", "ok", $"{active} ca đang dùng");

    public static HealthItem Holiday(int thisYear, int nextYear, int year, int month) =>
        thisYear == 0
            ? new("holiday", "todo", $"Chưa có ngày lễ năm {year}")
            : month >= 11 && nextYear == 0
                ? new("holiday", "warn", $"Chưa có ngày lễ năm {year + 1}")
                : new("holiday", "ok", $"{thisYear} ngày lễ năm {year}");

    public static HealthItem Devices(int total, int offline) =>
        total == 0
            ? new("device", "info", "Chưa kết nối máy chấm công")
            : offline > 0
                ? new("device", "warn", $"{offline}/{total} máy mất kết nối")
                : new("device", "ok", $"{total} máy đang kết nối");

    public static HealthItem Payment(int accounts, bool hasDefault) =>
        accounts == 0
            ? new("payment", "todo", "Chưa có tài khoản nhận tiền")
            : !hasDefault
                ? new("payment", "warn", "Chưa chọn tài khoản nhận tiền mặc định")
                : new("payment", "ok", $"{accounts} tài khoản nhận tiền");

    [HttpGet]
    public async Task<ActionResult<AppResponse<List<HealthItem>>>> Get()
    {
        var storeId = RequiredStoreId;
        var nowVn = DateTime.UtcNow.AddHours(7);
        var y = nowVn.Year;
        var items = new List<HealthItem>();

        var shifts = await db.ShiftTemplates.CountAsync(t => t.StoreId == storeId && t.IsActive);
        items.Add(Shift(shifts));

        var holidays = await db.Holidays.AsNoTracking()
            .Where(h => h.StoreId == storeId || h.StoreId == null)
            .Select(h => new { h.Date, h.IsRecurring })
            .ToListAsync();
        items.Add(Holiday(holidays.Count(h => h.IsRecurring || h.Date.Year == y), holidays.Count(h => h.IsRecurring || h.Date.Year == y + 1),
            y, nowVn.Month));

        var since = DateTime.UtcNow.AddMinutes(-15);
        var devices = await db.Devices.AsNoTracking().Where(d => d.StoreId == storeId)
            .Select(d => new { d.LastOnline }).ToListAsync();
        items.Add(Devices(devices.Count, devices.Count(d => d.LastOnline == null || d.LastOnline < since)));

        var locations = await db.MobileWorkLocations.CountAsync(l => l.StoreId == storeId);
        var pendingPhones = await db.AuthorizedMobileDevices.CountAsync(d => d.StoreId == storeId && !d.IsAuthorized)
            + await db.DeviceChangeRequests.CountAsync(r => r.StoreId == storeId && r.Status == 0);
        items.Add(pendingPhones > 0
            ? new("mobile", "warn", $"{pendingPhones} điện thoại chờ duyệt")
            : locations == 0
                ? new("mobile", "todo", "Chưa có vị trí chấm công")
                : new("mobile", "ok", $"{locations} vị trí chấm công"));

        items.Add(await db.InsuranceSettings.AnyAsync(s => s.StoreId == storeId)
            ? new("insurance", "ok", "Đã cấu hình")
            : new("insurance", "info", "Đang dùng mức mặc định"));
        items.Add(await db.TaxSettings.AnyAsync(s => s.StoreId == storeId)
            ? new("tax", "ok", "Đã cấu hình")
            : new("tax", "info", "Đang dùng biểu thuế mặc định"));

        var penalties = await db.PenaltySettings.CountAsync(s => s.StoreId == storeId);
        items.Add(penalties == 0 ? new("penalty", "info", "Chưa có mức phạt") : new("penalty", "ok", $"{penalties} mức phạt"));
        var allowances = await db.Allowances.CountAsync(a => a.StoreId == storeId);
        items.Add(allowances == 0 ? new("allowance", "info", "Chưa có phụ cấp") : new("allowance", "ok", $"{allowances} phụ cấp"));

        var branches = await db.Branches.CountAsync(b => b.StoreId == storeId);
        items.Add(branches <= 1 ? new("branch", "info", "1 cửa hàng, chưa chia chi nhánh") : new("branch", "ok", $"{branches} chi nhánh"));

        var banks = await db.BankAccounts.AsNoTracking().Where(b => b.StoreId == storeId && b.IsActive)
            .Select(b => b.IsDefault).ToListAsync();
        items.Add(Payment(banks.Count, banks.Any(x => x)));

        var einvoice = await db.PosEInvoiceSettings.AnyAsync(s => s.StoreId == storeId && s.Enabled);
        items.Add(einvoice ? new("einvoice", "ok", "Đã kết nối") : new("einvoice", "info", "Chưa kết nối"));
        var carriers = await db.PosShippingCarrierSettings.CountAsync(s => s.StoreId == storeId && s.Enabled);
        items.Add(carriers == 0 ? new("shipping", "info", "Chưa bật đơn vị giao hàng") : new("shipping", "ok", $"{carriers} đơn vị đang bật"));
        var printers = await db.PosStorePrinters.CountAsync(p => p.StoreId == storeId);
        items.Add(printers == 0 ? new("cloudPrinter", "info", "Chưa có máy in cloud") : new("cloudPrinter", "ok", $"{printers} máy in"));

        return Ok(AppResponse<List<HealthItem>>.Success(items));
    }
}
