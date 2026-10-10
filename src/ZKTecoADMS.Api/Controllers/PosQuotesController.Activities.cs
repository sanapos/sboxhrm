using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosQuotesController
{
    public record QuoteActivityDto(
        Guid Id,
        string Kind,
        string Content,
        DateTime? NextFollowUpAt,
        Guid? EmployeeId,
        string? EmployeeName,
        string? CreatedBy,
        DateTime CreatedAt,
        int? PotentialScore);

    public record CreateQuoteActivityDto(
        string Kind,
        string Content,
        DateTime? NextFollowUpAt,
        int? PotentialScore = null);

    [HttpGet("{id:guid}/activities")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListActivities(Guid id)
    {
        var storeId = RequiredStoreId;
        if (!await QuoteAccessible(storeId, id))
            return NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá"));
        var rows = await dbContext.PosQuoteActivities.AsNoTracking()
            .Where(a => a.QuoteId == id && a.StoreId == storeId && a.Deleted == null)
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync();
        var items = await MapActivitiesAsync(rows);
        return Ok(AppResponse<object>.Success(new { items }));
    }

    /// <summary>Người ghi = họ tên (nhân viên → tài khoản), trạng thái cũ ghi tiếng Anh đổi sang tiếng Việt.</summary>
    async Task<List<QuoteActivityDto>> MapActivitiesAsync(List<PosQuoteActivity> rows)
    {
        var names = await EmployeeNamesAsync(rows.Select(a => a.EmployeeId));
        var byEmail = await UserNamesByEmailAsync(rows.Select(a => a.CreatedBy));
        return rows.Select(a => new QuoteActivityDto(
            a.Id,
            a.Kind,
            LegacyStatusText(a.Content),
            a.NextFollowUpAt,
            a.EmployeeId,
            (a.EmployeeId is Guid eid ? names.GetValueOrDefault(eid) : null)
                ?? (a.CreatedBy != null ? byEmail.GetValueOrDefault(a.CreatedBy) : null),
            a.CreatedBy,
            a.CreatedAt,
            ResolvePotentialScore(a.PotentialScore, a.Content))).ToList();
    }

    static string LegacyStatusText(string content)
    {
        const string prefix = "Cập nhật trạng thái: ";
        if (!content.StartsWith(prefix, StringComparison.Ordinal)) return content;
        return Enum.TryParse<PosQuoteStatus>(content[prefix.Length..].Trim(), out var st)
            ? "Trạng thái: " + StatusVi(st)
            : content;
    }

    /// <summary>
    /// Lịch sử của khách trên báo giá này: các báo giá khác của cùng khách (theo mã khách, không có thì theo SĐT)
    /// và các lần chăm sóc trên những báo giá đó — xem lại đã báo gì, đã hẹn gì trước khi gọi lại.
    /// </summary>
    [HttpGet("{id:guid}/customer-history")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> CustomerHistory(Guid id)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá"));
        var phone = (quote.CustomerPhone ?? "").Trim();
        if (quote.CustomerId == null && phone.Length < 6)
            return Ok(AppResponse<object>.Success(new { quotes = Array.Empty<object>(), activities = Array.Empty<object>() }));
        var q = ApplyOwnScope(dbContext.PosQuotes.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Id != id));
        q = quote.CustomerId is Guid cid
            ? q.Where(x => x.CustomerId == cid || (x.CustomerId == null && phone.Length >= 6 && x.CustomerPhone == phone))
            : q.Where(x => x.CustomerPhone == phone);
        var others = await q.OrderByDescending(x => x.CreatedAt).Take(30)
            .Select(x => new { x.Id, x.QuoteNo, x.Status, x.CommercialStage, x.Total, x.CreatedAt, x.Revision })
            .ToListAsync();
        var otherIds = others.Select(x => x.Id).ToList();
        var acts = otherIds.Count == 0 ? new List<PosQuoteActivity>() : await dbContext.PosQuoteActivities.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Deleted == null && otherIds.Contains(a.QuoteId)
                        && a.Kind != "Created" && a.Kind != "Status")
            .OrderByDescending(a => a.CreatedAt).Take(50)
            .ToListAsync();
        var mapped = await MapActivitiesAsync(acts);
        var noById = others.ToDictionary(x => x.Id, x => x.QuoteNo);
        return Ok(AppResponse<object>.Success(new
        {
            quotes = others.Select(x => new
            {
                x.Id, x.QuoteNo, status = x.Status.ToString(), statusText = StatusVi(x.Status),
                commercialStage = x.CommercialStage.ToString(), x.Total, x.CreatedAt, x.Revision,
            }),
            activities = acts.Zip(mapped, (a, m) => new { activity = m, quoteId = a.QuoteId, quoteNo = noById.GetValueOrDefault(a.QuoteId) }),
        }));
    }

    /// <summary>
    /// Theo dõi chăm sóc khách tiềm năng: báo giá đang theo đuổi (nháp / đã gửi / đã sửa) với điểm
    /// thang 10, xu hướng, lịch hẹn quá hạn / hôm nay, khách lâu chưa liên hệ. <paramref name="all"/> = true
    /// lấy cả báo giá đã chốt / từ chối / hết hạn.
    /// </summary>
    [HttpGet("care-overview")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> CareOverview([FromQuery] bool all = false)
    {
        var storeId = RequiredStoreId;
        var q = ApplyOwnScope(dbContext.PosQuotes.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null));
        if (!all)
            q = q.Where(x => x.Status == PosQuoteStatus.Draft
                || x.Status == PosQuoteStatus.Sent
                || x.Status == PosQuoteStatus.Revised);
        var quotes = await q.OrderByDescending(x => x.UpdatedAt ?? x.CreatedAt)
            .Take(500)
            .ToListAsync();
        var ids = quotes.Select(x => x.Id).ToList();
        var acts = await dbContext.PosQuoteActivities.AsNoTracking()
            .Where(a => ids.Contains(a.QuoteId) && a.StoreId == storeId && a.Deleted == null)
            .ToListAsync();
        var names = await EmployeeNamesAsync(quotes.Select(x => x.QuotedByEmployeeId));
        var (summary, items) = PosQuoteCareBoard.Build(quotes, acts, names, DateTime.UtcNow);
        return Ok(AppResponse<object>.Success(new { summary, items }));
    }

    [HttpPost("{id:guid}/activities")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<QuoteActivityDto>>> CreateActivity(
        Guid id, [FromBody] CreateQuoteActivityDto dto)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<QuoteActivityDto>.Fail("Không tìm thấy báo giá"));
        if (!CanMutateOwn(quote))
            return StatusCode(403, AppResponse<QuoteActivityDto>.Fail(
                "Không có quyền ghi lịch trên báo giá của nhân viên khác"));
        var kind = NormalizeActivityKind(dto.Kind);
        var content = (dto.Content ?? "").Trim();
        if (content.Length == 0)
            return BadRequest(AppResponse<QuoteActivityDto>.Fail("Nhập nội dung làm việc với khách"));
        var score = ResolvePotentialScore(dto.PotentialScore, content);
        if (dto.PotentialScore is int raw && (raw < 0 || raw > 10))
            return BadRequest(AppResponse<QuoteActivityDto>.Fail("Điểm tiềm năng phải từ 0 đến 10"));
        var act = new PosQuoteActivity
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            QuoteId = quote.Id,
            Kind = kind,
            Content = content,
            NextFollowUpAt = dto.NextFollowUpAt,
            EmployeeId = EmployeeId,
            CreatedBy = CurrentUserEmail,
            IsActive = true,
            PotentialScore = score,
        };
        dbContext.PosQuoteActivities.Add(act);
        if (score is int s)
            quote.PotentialScore = s;
        quote.UpdatedAt = DateTime.UtcNow;
        quote.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        var names = await EmployeeNamesAsync([act.EmployeeId]);
        return Ok(AppResponse<QuoteActivityDto>.Success(new QuoteActivityDto(
            act.Id, act.Kind, act.Content, act.NextFollowUpAt, act.EmployeeId,
            act.EmployeeId is Guid eid ? names.GetValueOrDefault(eid) : null,
            act.CreatedBy, act.CreatedAt, score)));
    }

    static int? ResolvePotentialScore(int? column, string? content)
    {
        if (column is int n && n >= 0 && n <= 10) return n;
        if (string.IsNullOrWhiteSpace(content)) return null;
        var m = System.Text.RegularExpressions.Regex.Match(
            content, @"^\[\[TN:(\d{1,2})\]\]");
        if (!m.Success) return null;
        return int.TryParse(m.Groups[1].Value, out var parsed) && parsed is >= 0 and <= 10
            ? parsed
            : null;
    }

    static string NormalizeActivityKind(string? raw)
    {
        var k = (raw ?? "").Trim();
        return k.ToLowerInvariant() switch
        {
            "call" or "goi" => "Call",
            "meeting" or "gap" => "Meeting",
            "followup" or "follow-up" or "hen" => "FollowUp",
            "created" => "Created",
            "edit" => "Edit",
            "status" => "Status",
            _ => "Note",
        };
    }
}
