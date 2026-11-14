using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Tổng số token Gemini cửa hàng đã dùng: theo ngày, theo tính năng, theo model.</summary>
[ApiController]
[Authorize]
[Route("api/ai/usage")]
public class GeminiUsageController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    /// <summary>Khoảng ngày tối đa xem được một lần — báo cáo dài hơn thì chia nhỏ.</summary>
    public const int MaxDays = 186;

    public sealed record UsageTotalsDto(
        int Calls, long PromptTokens, long AnswerTokens, long ThoughtTokens, long TotalTokens);

    public sealed record UsageBucketDto(string Key, int Calls, long TotalTokens);

    public sealed record UsageReportDto(
        DateTime From, DateTime To, UsageTotalsDto Totals,
        List<UsageBucketDto> ByDay, List<UsageBucketDto> ByFeature, List<UsageBucketDto> ByModel);

    [HttpGet]
    [RequireModulePermission("AIGemini", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<UsageReportDto>>> Get(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var (fromVn, toVn, fromUtc, toUtc) = Range(from, to);
        var rows = db.GeminiUsageLogs.Where(l => l.StoreId == storeId && l.CreatedAt >= fromUtc && l.CreatedAt < toUtc);
        return Ok(AppResponse<UsageReportDto>.Success(
            new UsageReportDto(fromVn, toVn, await TotalsAsync(rows, ct),
                await ByDayAsync(rows, ct),
                await BucketAsync(rows, l => l.Feature, ct),
                await BucketAsync(rows, l => l.Model, ct))));
    }

    /// <summary>Khoảng ngày theo giờ VN (mặc định 30 ngày gần nhất) và cận UTC tương ứng để lọc.</summary>
    internal static (DateTime FromVn, DateTime ToVn, DateTime FromUtc, DateTime ToUtc) Range(DateTime? from, DateTime? to)
    {
        var toVn = (to ?? VnTimeHelper.NowVn()).Date;
        var fromVn = (from ?? toVn.AddDays(-29)).Date;
        if (fromVn > toVn) (fromVn, toVn) = (toVn, fromVn);
        if ((toVn - fromVn).TotalDays > MaxDays - 1) fromVn = toVn.AddDays(-(MaxDays - 1));
        return (fromVn, toVn,
            DateTime.SpecifyKind(fromVn.AddHours(-VnTimeHelper.OffsetHours), DateTimeKind.Unspecified),
            DateTime.SpecifyKind(toVn.AddDays(1).AddHours(-VnTimeHelper.OffsetHours), DateTimeKind.Unspecified));
    }

    static async Task<UsageTotalsDto> TotalsAsync(IQueryable<Domain.Entities.GeminiUsageLog> rows, CancellationToken ct)
    {
        var t = await rows
            .GroupBy(_ => 1)
            .Select(g => new UsageTotalsDto(
                g.Count(),
                g.Sum(x => (long)x.PromptTokens),
                g.Sum(x => (long)x.AnswerTokens),
                g.Sum(x => (long)x.ThoughtTokens),
                g.Sum(x => (long)x.TotalTokens)))
            .FirstOrDefaultAsync(ct);
        return t ?? new UsageTotalsDto(0, 0, 0, 0, 0);
    }

    static async Task<List<UsageBucketDto>> ByDayAsync(IQueryable<Domain.Entities.GeminiUsageLog> rows, CancellationToken ct)
    {
        // Ngày theo giờ VN: lời gọi lúc 02:00 ngày 15 giờ VN là 19:00 ngày 14 UTC.
        var days = await rows
            .GroupBy(l => l.CreatedAt.AddHours(VnTimeHelper.OffsetHours).Date)
            .Select(g => new { Day = g.Key, Calls = g.Count(), Total = g.Sum(x => (long)x.TotalTokens) })
            .ToListAsync(ct);
        return [.. days.OrderBy(d => d.Day)
            .Select(d => new UsageBucketDto(d.Day.ToString("yyyy-MM-dd"), d.Calls, d.Total))];
    }

    static async Task<List<UsageBucketDto>> BucketAsync(
        IQueryable<Domain.Entities.GeminiUsageLog> rows,
        System.Linq.Expressions.Expression<Func<Domain.Entities.GeminiUsageLog, string>> key,
        CancellationToken ct)
    {
        var buckets = await rows
            .GroupBy(key)
            .Select(g => new UsageBucketDto(g.Key, g.Count(), g.Sum(x => (long)x.TotalTokens)))
            .ToListAsync(ct);
        return [.. buckets.OrderByDescending(b => b.TotalTokens)];
    }
}

/// <summary>Token Gemini toàn hệ thống, tách theo cửa hàng — chỉ Super Admin.</summary>
[ApiController]
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/ai-usage")]
public class SystemGeminiUsageController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public sealed record StoreUsageDto(Guid? StoreId, string StoreName, int Calls, long TotalTokens, long ThoughtTokens);

    public sealed record PlatformUsageDto(
        DateTime From, DateTime To, int Calls, long TotalTokens, List<StoreUsageDto> ByStore);

    [HttpGet]
    public async Task<ActionResult<AppResponse<PlatformUsageDto>>> Get(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, CancellationToken ct)
    {
        var (fromVn, toVn, fromUtc, toUtc) = GeminiUsageController.Range(from, to);
        // IgnoreQueryFilters: bộ lọc cửa hàng sẽ giấu dòng của cửa hàng khác.
        var rows = db.GeminiUsageLogs.IgnoreQueryFilters()
            .Where(l => l.CreatedAt >= fromUtc && l.CreatedAt < toUtc);

        var byStore = await rows
            .GroupBy(l => l.StoreId)
            .Select(g => new
            {
                StoreId = g.Key,
                Calls = g.Count(),
                Total = g.Sum(x => (long)x.TotalTokens),
                Thought = g.Sum(x => (long)x.ThoughtTokens),
            })
            .ToListAsync(ct);

        var ids = byStore.Where(s => s.StoreId != null).Select(s => s.StoreId!.Value).ToList();
        var names = await db.Stores.IgnoreQueryFilters()
            .Where(s => ids.Contains(s.Id))
            .Select(s => new { s.Id, s.Name })
            .ToDictionaryAsync(s => s.Id, s => s.Name, ct);

        var list = byStore
            .Select(s => new StoreUsageDto(
                s.StoreId,
                s.StoreId is Guid id ? names.GetValueOrDefault(id) ?? "(cửa hàng đã xóa)" : "(chạy nền / không thuộc cửa hàng)",
                s.Calls, s.Total, s.Thought))
            .OrderByDescending(s => s.TotalTokens)
            .ToList();

        return Ok(AppResponse<PlatformUsageDto>.Success(new PlatformUsageDto(
            fromVn, toVn, list.Sum(s => s.Calls), list.Sum(s => s.TotalTokens), list)));
    }
}
