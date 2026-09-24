using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;

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
        var names = await EmployeeNamesAsync(rows.Select(a => a.EmployeeId));
        var items = rows.Select(a => new QuoteActivityDto(
            a.Id,
            a.Kind,
            a.Content,
            a.NextFollowUpAt,
            a.EmployeeId,
            a.EmployeeId is Guid eid ? names.GetValueOrDefault(eid) : null,
            a.CreatedBy,
            a.CreatedAt,
            ResolvePotentialScore(a.PotentialScore, a.Content))).ToList();
        return Ok(AppResponse<object>.Success(new { items }));
    }

    [HttpPost("{id:guid}/activities")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<QuoteActivityDto>>> CreateActivity(
        Guid id, [FromBody] CreateQuoteActivityDto dto)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes
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
