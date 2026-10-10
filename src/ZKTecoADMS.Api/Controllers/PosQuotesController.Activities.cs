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
    public async Task<ActionResult<AppResponse<object>>> CareOverview(
        [FromQuery] bool all = false, [FromQuery] string? scope = null)
    {
        var storeId = RequiredStoreId;
        var q = ApplyOwnScope(dbContext.PosQuotes.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null));
        // pipeline: báo giá đang theo đuổi · aftersale: khách đã chốt (chăm sóc sau bán / bảo hành) · all
        var sc = (scope ?? (all ? "all" : "pipeline")).Trim().ToLowerInvariant();
        if (sc == "pipeline")
            q = q.Where(x => x.Status == PosQuoteStatus.Draft
                || x.Status == PosQuoteStatus.Sent
                || x.Status == PosQuoteStatus.Revised);
        else if (sc == "aftersale")
            q = q.Where(x => x.Status == PosQuoteStatus.Accepted);
        var quotes = await q.OrderByDescending(x => x.UpdatedAt ?? x.CreatedAt)
            .Take(2000)
            .ToListAsync();
        var ids = quotes.Select(x => x.Id).ToList();
        var acts = await dbContext.PosQuoteActivities.AsNoTracking()
            .Where(a => ids.Contains(a.QuoteId) && a.StoreId == storeId && a.Deleted == null)
            .ToListAsync();
        var names = await EmployeeNamesAsync(quotes.Select(x => x.QuotedByEmployeeId));
        // Sau bán: 30 ngày chưa hỏi thăm mới coi là «lâu chưa liên hệ» (đang chào hàng: 7 ngày).
        var (summary, items) = PosQuoteCareBoard.Build(quotes, acts, names, DateTime.UtcNow,
            sc == "aftersale" ? 30 : PosQuoteCareBoard.StaleDays);
        return Ok(AppResponse<object>.Success(new { summary, items, scope = sc }));
    }

    public record UpdateQuoteActivityDto(string? Kind, string? Content, DateTime? NextFollowUpAt, int? PotentialScore,
        bool ClearFollowUp = false);

    /// <summary>Lần ghi do người dùng ghi (không phải hệ thống) — người ghi hoặc quản lý mới sửa / xoá được.</summary>
    async Task<(PosQuote? Quote, PosQuoteActivity? Act, ActionResult? Error)> LoadOwnActivityAsync(Guid id, Guid actId)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null || !OwnsOrManages(quote))
            return (null, null, NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá")));
        var act = await dbContext.PosQuoteActivities.AsTracking()
            .FirstOrDefaultAsync(a => a.Id == actId && a.QuoteId == id && a.StoreId == storeId && a.Deleted == null);
        if (act == null) return (null, null, NotFound(AppResponse<object>.Fail("Không tìm thấy lần ghi")));
        if (PosQuoteCareBoard.SystemKinds.Contains(act.Kind))
            return (null, null, BadRequest(AppResponse<object>.Fail("Ghi chép tự động của hệ thống — không sửa / xoá")));
        var mine = (act.EmployeeId != null && act.EmployeeId == EmployeeId)
                   || string.Equals(act.CreatedBy, CurrentUserEmail, StringComparison.OrdinalIgnoreCase);
        if (!mine && !CanViewAllQuotes)
            return (null, null, StatusCode(403, AppResponse<object>.Fail("Chỉ người ghi hoặc quản lý được sửa / xoá")));
        return (quote, act, null);
    }

    /// <summary>Điểm tiềm năng của báo giá = điểm của lần chấm gần nhất còn lại.</summary>
    async Task RefreshQuoteScoreAsync(PosQuote quote)
    {
        var rows = await dbContext.PosQuoteActivities.AsNoTracking()
            .Where(a => a.QuoteId == quote.Id && a.Deleted == null)
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync();
        quote.PotentialScore = rows.Select(PosQuoteCareBoard.ScoreOf).FirstOrDefault(s => s != null);
    }

    [HttpPut("{id:guid}/activities/{actId:guid}")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult> UpdateActivity(Guid id, Guid actId, [FromBody] UpdateQuoteActivityDto dto)
    {
        var (quote, act, error) = await LoadOwnActivityAsync(id, actId);
        if (error != null) return error;
        if (dto.PotentialScore is int raw && (raw < 0 || raw > 10))
            return BadRequest(AppResponse<object>.Fail("Điểm tiềm năng phải từ 0 đến 10"));
        if (dto.Content != null)
        {
            var content = dto.Content.Trim();
            if (content.Length == 0) return BadRequest(AppResponse<object>.Fail("Nhập nội dung làm việc với khách"));
            act!.Content = content;
        }
        if (dto.Kind != null)
        {
            var k = NormalizeActivityKind(dto.Kind);
            if (PosQuoteCareBoard.SystemKinds.Contains(k)) return BadRequest(AppResponse<object>.Fail("Loại không hợp lệ"));
            act!.Kind = k;
        }
        if (dto.ClearFollowUp || dto.NextFollowUpAt != null)
        {
            act!.NextFollowUpAt = dto.ClearFollowUp ? null : dto.NextFollowUpAt;
            act.ReminderSentAt = null; // đổi hẹn → nhắc lại theo giờ mới
        }
        if (dto.PotentialScore is int s) act!.PotentialScore = s;
        act!.UpdatedAt = DateTime.UtcNow;
        act.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        await RefreshQuoteScoreAsync(quote!);
        await dbContext.SaveChangesAsync();
        var mapped = await MapActivitiesAsync([act]);
        return Ok(AppResponse<QuoteActivityDto>.Success(mapped[0]));
    }

    [HttpDelete("{id:guid}/activities/{actId:guid}")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult> DeleteActivity(Guid id, Guid actId)
    {
        var (quote, act, error) = await LoadOwnActivityAsync(id, actId);
        if (error != null) return error;
        act!.Deleted = DateTime.UtcNow;
        act.DeletedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        await RefreshQuoteScoreAsync(quote!);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    /// <summary>
    /// Hiệu quả chăm sóc theo nhân viên trong <paramref name="days"/> ngày: số lần chăm sóc, khách đang theo,
    /// hẹn quá hạn, báo giá mới, khách chốt, tỉ lệ chốt, điểm tiềm năng trung bình. Nhân viên chỉ thấy mình.
    /// </summary>
    [HttpGet("care-staff")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> CareStaff([FromQuery] int days = 30)
    {
        var storeId = RequiredStoreId;
        days = Math.Clamp(days, 7, 365);
        var since = DateTime.UtcNow.AddDays(-days);
        var quotes = await ApplyOwnScope(dbContext.PosQuotes.AsNoTracking()
                .Where(x => x.StoreId == storeId && x.Deleted == null))
            .Where(x => x.CreatedAt >= since || x.Status == PosQuoteStatus.Draft
                        || x.Status == PosQuoteStatus.Sent || x.Status == PosQuoteStatus.Revised)
            .Take(5000)
            .ToListAsync();
        var ids = quotes.Select(x => x.Id).ToList();
        var acts = await dbContext.PosQuoteActivities.AsNoTracking()
            .Where(a => ids.Contains(a.QuoteId) && a.StoreId == storeId && a.Deleted == null)
            .ToListAsync();
        var names = await EmployeeNamesAsync(quotes.Select(x => x.QuotedByEmployeeId).Concat(acts.Select(a => a.EmployeeId)));
        var open = quotes.Where(x => x.Status is PosQuoteStatus.Draft or PosQuoteStatus.Sent or PosQuoteStatus.Revised).ToList();
        var (_, careItems) = PosQuoteCareBoard.Build(open, acts, names, DateTime.UtcNow);
        string Key(Guid? emp, string? by) => emp is Guid e ? e.ToString() : "u:" + (by ?? "");
        var rows = quotes.GroupBy(x => Key(x.QuotedByEmployeeId, x.QuotedBy)).Select(g =>
        {
            var first = g.First();
            var created = g.Where(x => x.CreatedAt >= since).ToList();
            var accepted = created.Count(x => x.Status == PosQuoteStatus.Accepted);
            var decided = created.Count(x => x.Status is PosQuoteStatus.Accepted or PosQuoteStatus.Rejected
                or PosQuoteStatus.Expired or PosQuoteStatus.Cancelled);
            var qIds = g.Select(x => x.Id).ToHashSet();
            var contacts = acts.Count(a => qIds.Contains(a.QuoteId) && a.CreatedAt >= since
                                           && !PosQuoteCareBoard.SystemKinds.Contains(a.Kind));
            var mineCare = careItems.Where(i => qIds.Contains(i.QuoteId)).ToList();
            var scored = mineCare.Where(i => i.Score != null).ToList();
            return new
            {
                employeeId = first.QuotedByEmployeeId,
                name = first.QuotedByEmployeeId is Guid eid ? names.GetValueOrDefault(eid) ?? first.QuotedBy : first.QuotedBy,
                openQuotes = mineCare.Count,
                pipelineValue = mineCare.Sum(i => i.Total),
                contacts,
                overdue = mineCare.Count(i => i.FollowUp == "overdue"),
                stale = mineCare.Count(i => i.Stale),
                createdQuotes = created.Count,
                accepted,
                conversionRate = decided > 0 ? Math.Round(accepted * 100.0 / decided, 1) : (double?)null,
                acceptedValue = created.Where(x => x.Status == PosQuoteStatus.Accepted).Sum(x => x.Total),
                averageScore = scored.Count > 0 ? Math.Round(scored.Average(i => i.Score!.Value), 1) : (double?)null,
            };
        }).OrderByDescending(r => r.acceptedValue).ThenByDescending(r => r.contacts).ToList();
        var byEmail = await UserNamesByEmailAsync(rows.Where(r => r.name != null && r.name.Contains('@')).Select(r => r.name));
        return Ok(AppResponse<object>.Success(new
        {
            days,
            items = rows.Select(r => r with { name = r.name != null && byEmail.TryGetValue(r.name, out var n) ? n : r.name }),
        }));
    }

    /// <summary>Báo giá + lịch chăm sóc của MỘT khách (hồ sơ khách hàng POS): theo mã khách và SĐT của khách.</summary>
    [HttpGet("customer-care")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> CustomerCare([FromQuery] Guid? customerId, [FromQuery] string? phone)
    {
        var storeId = RequiredStoreId;
        var p = PosQuoteDocumentHtml.NormalizePhone(phone);
        if (customerId == null && p == null)
            return Ok(AppResponse<object>.Success(new { quotes = Array.Empty<object>(), activities = Array.Empty<object>() }));
        if (customerId is Guid cid && p == null)
            p = PosQuoteDocumentHtml.NormalizePhone(await dbContext.PosCustomers.AsNoTracking()
                .Where(c => c.Id == cid && c.StoreId == storeId).Select(c => c.Phone).FirstOrDefaultAsync());
        var q = ApplyOwnScope(dbContext.PosQuotes.AsNoTracking().Where(x => x.StoreId == storeId && x.Deleted == null));
        var cands = await q.Where(x => (customerId != null && x.CustomerId == customerId)
                                       || (p != null && x.CustomerPhone != null))
            .OrderByDescending(x => x.CreatedAt).Take(500).ToListAsync();
        // SĐT lưu nhiều kiểu (+84 / dấu cách) → so sau khi chuẩn hoá.
        var quotes = cands.Where(x => (customerId != null && x.CustomerId == customerId)
                                      || (p != null && PosQuoteDocumentHtml.NormalizePhone(x.CustomerPhone) == p))
            .Take(50).ToList();
        var ids = quotes.Select(x => x.Id).ToList();
        var acts = ids.Count == 0 ? new List<PosQuoteActivity>() : await dbContext.PosQuoteActivities.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Deleted == null && ids.Contains(a.QuoteId) && a.Kind != "Created")
            .OrderByDescending(a => a.CreatedAt).Take(100)
            .ToListAsync();
        var mapped = await MapActivitiesAsync(acts);
        var noById = quotes.ToDictionary(x => x.Id, x => x.QuoteNo);
        return Ok(AppResponse<object>.Success(new
        {
            quotes = quotes.Select(x => new
            {
                x.Id, x.QuoteNo, status = x.Status.ToString(), statusText = StatusVi(x.Status),
                commercialStage = x.CommercialStage.ToString(), x.Total, x.CreatedAt, x.PotentialScore,
            }),
            activities = acts.Zip(mapped, (a, m) => new { activity = m, quoteId = a.QuoteId, quoteNo = noById.GetValueOrDefault(a.QuoteId) }),
        }));
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
