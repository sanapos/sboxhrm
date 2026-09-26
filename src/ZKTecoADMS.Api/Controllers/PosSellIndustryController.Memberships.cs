using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Gym / spa: báo cáo thẻ tập, gói buổi sắp hết hạn / đã hết hạn / sắp hết buổi — để nhắc gia hạn.</summary>
public partial class PosSellIndustryController
{
    public record ExpiringPackDto(
        Guid Id, Guid CustomerId, string CustomerName, string? CustomerPhone,
        Guid? ProductId, string PackageName, bool Unlimited,
        int TotalSessions, int RemainingSessions, int UsedSessions,
        DateTime CreatedAt, DateTime? ExpiresAt, int? DaysLeft,
        DateTime? LastUsedAt, bool Renewed, string Status);

    /// <summary>
    /// status: expiring (còn ≤ days ngày hoặc ≤ lowSessions buổi), expired (hết hạn trong expiredDays ngày gần đây), all.
    /// Thẻ đã được gia hạn (có thẻ/gói cùng sản phẩm còn hiệu lực) được đánh dấu Renewed để không nhắc trùng.
    /// </summary>
    [HttpGet("session-balances/expiring")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<IActionResult> GetExpiringPacks(
        [FromQuery] int days = 7,
        [FromQuery] int expiredDays = 30,
        [FromQuery] int lowSessions = 2,
        [FromQuery] string status = "all",
        [FromQuery] string? format = null)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        days = Math.Clamp(days, 0, 365);
        expiredDays = Math.Clamp(expiredDays, 0, 365);
        lowSessions = Math.Clamp(lowSessions, 0, 100);
        var now = DateTime.UtcNow;
        var soon = now.AddDays(days);
        var expiredFrom = now.AddDays(-expiredDays);
        var unlimited = PosCustomerSessionBalance.UnlimitedSessions;

        var rows = await db.PosCustomerSessionBalances.AsNoTracking()
            .Where(b => b.StoreId == storeId && b.Deleted == null)
            .Where(b =>
                (b.ExpiresAt != null && b.ExpiresAt >= expiredFrom && b.ExpiresAt <= soon)
                || (b.TotalSessions < unlimited && b.RemainingSessions <= lowSessions
                    && (b.ExpiresAt == null || b.ExpiresAt > now)))
            .Select(b => new
            {
                b.Id, b.CustomerId,
                CustomerName = b.Customer != null ? b.Customer.Name : "",
                CustomerPhone = b.Customer != null ? b.Customer.Phone : null,
                b.ProductId, b.PackageName, b.TotalSessions, b.RemainingSessions,
                b.CreatedAt, b.ExpiresAt,
                LastUsedAt = b.Transactions
                    .Where(t => t.Deleted == null && t.TransactionType == PosSessionTxnType.Redeem)
                    .Max(t => (DateTime?)(t.UsedAt ?? t.CreatedAt)),
            })
            .ToListAsync();

        // Đã gia hạn: khách còn gói khác cùng sản phẩm, tạo sau và còn hiệu lực.
        var customerIds = rows.Select(r => r.CustomerId).Distinct().ToList();
        var activeOthers = customerIds.Count == 0
            ? []
            : await db.PosCustomerSessionBalances.AsNoTracking()
                .Where(b => b.StoreId == storeId && b.Deleted == null && customerIds.Contains(b.CustomerId)
                    && b.RemainingSessions > lowSessions
                    && (b.ExpiresAt == null || b.ExpiresAt > soon))
                .Select(b => new { b.Id, b.CustomerId, b.ProductId, b.CreatedAt })
                .ToListAsync();

        var list = new List<ExpiringPackDto>();
        foreach (var r in rows)
        {
            var isUnlimited = PosCustomerSessionBalance.IsUnlimitedCount(r.TotalSessions);
            var expired = r.ExpiresAt.HasValue && r.ExpiresAt.Value <= now;
            var st = expired ? "expired"
                : r.ExpiresAt.HasValue && r.ExpiresAt.Value <= soon ? "expiring"
                : "lowSessions";
            if (status == "expired" && st != "expired") continue;
            if (status == "expiring" && st == "expired") continue;
            var renewed = activeOthers.Any(o => o.CustomerId == r.CustomerId && o.Id != r.Id
                && o.ProductId == r.ProductId && o.CreatedAt >= r.CreatedAt);
            int? daysLeft = r.ExpiresAt.HasValue
                ? (int)Math.Floor((r.ExpiresAt.Value.AddHours(7).Date - now.AddHours(7).Date).TotalDays)
                : null;
            list.Add(new ExpiringPackDto(
                r.Id, r.CustomerId, r.CustomerName, r.CustomerPhone, r.ProductId, r.PackageName,
                isUnlimited, r.TotalSessions, r.RemainingSessions, r.TotalSessions - r.RemainingSessions,
                r.CreatedAt, r.ExpiresAt, daysLeft, r.LastUsedAt, renewed, st));
        }

        list = list
            .OrderBy(x => x.Renewed)
            .ThenBy(x => x.Status == "expired" ? 1 : 0)
            .ThenBy(x => x.ExpiresAt ?? DateTime.MaxValue)
            .ThenBy(x => x.RemainingSessions)
            .ToList();
        if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
        {
            return ReportHelpers.ExcelFile("The goi sap het han",
                new[] { "STT", "Khách hàng", "Điện thoại", "Thẻ / gói", "Loại", "Đã dùng", "Còn lại",
                        "Hết hạn", "Còn (ngày)", "Lần tập cuối", "Tình trạng", "Đã gia hạn" },
                (ws, start) =>
                {
                    var r = start;
                    var i = 1;
                    foreach (var x in list)
                    {
                        ws.Cell(r, 1).Value = i++;
                        ws.Cell(r, 2).Value = x.CustomerName;
                        ws.Cell(r, 3).Value = x.CustomerPhone ?? "";
                        ws.Cell(r, 4).Value = x.PackageName;
                        ws.Cell(r, 5).Value = x.Unlimited ? "Thẻ thời gian" : "Gói buổi";
                        ws.Cell(r, 6).Value = x.UsedSessions;
                        ws.Cell(r, 7).Value = x.Unlimited ? "Không giới hạn" : $"{x.RemainingSessions}";
                        ws.Cell(r, 8).Value = x.ExpiresAt is DateTime e ? ReportHelpers.ToVn(e).ToString("dd/MM/yyyy") : "";
                        ws.Cell(r, 9).Value = x.DaysLeft?.ToString() ?? "";
                        ws.Cell(r, 10).Value = x.LastUsedAt is DateTime u ? ReportHelpers.ToVn(u).ToString("dd/MM/yyyy") : "";
                        ws.Cell(r, 11).Value = StatusLabel(x.Status);
                        ws.Cell(r, 12).Value = x.Renewed ? "Có" : "";
                        r++;
                    }
                },
                $"the-goi-sap-het-han-{now.AddHours(7):yyyyMMdd}.xlsx", user: User);
        }

        return Ok(AppResponse<object>.Success(new
        {
            expiringCount = list.Count(x => x.Status == "expiring" && !x.Renewed),
            expiredCount = list.Count(x => x.Status == "expired" && !x.Renewed),
            lowSessionsCount = list.Count(x => x.Status == "lowSessions" && !x.Renewed),
            renewedCount = list.Count(x => x.Renewed),
            items = list.Select(x => new
            {
                customerName = x.CustomerName,
                phone = x.CustomerPhone,
                packageName = x.PackageName,
                kind = x.Unlimited ? "Thẻ thời gian" : "Gói buổi",
                usedSessions = x.UsedSessions,
                remainingSessions = x.Unlimited ? "Không giới hạn" : $"{x.RemainingSessions}",
                expiresAt = x.ExpiresAt.HasValue ? ReportHelpers.ToVn(x.ExpiresAt.Value).ToString("dd/MM/yyyy") : "",
                daysLeft = x.DaysLeft,
                lastUsedAt = x.LastUsedAt.HasValue ? ReportHelpers.ToVn(x.LastUsedAt.Value).ToString("dd/MM/yyyy") : "",
                status = StatusLabel(x.Status),
                renewed = x.Renewed,
                x.Id, x.CustomerId,
            }),
        }));
    }

    static string StatusLabel(string status) => status switch
    {
        "expired" => "Đã hết hạn",
        "expiring" => "Sắp hết hạn",
        _ => "Sắp hết buổi",
    };
}
