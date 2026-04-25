using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

// ══════════════════════════════════════════════════════════════
//  PUBLIC: GET /api/app-pages/{type}  (no auth required)
// ══════════════════════════════════════════════════════════════
[ApiController]
[Route("api/app-pages")]
[AllowAnonymous]
public class AppPagesPublicController(ZKTecoDbContext db) : ControllerBase
{
    [HttpGet("{type}")]
    public async Task<ActionResult<AppResponse<object>>> Get(string type)
    {
        var page = await db.AppPages
            .Where(p => p.Type == type.ToLower() && p.IsPublished)
            .OrderByDescending(p => p.UpdatedAt ?? p.CreatedAt)
            .FirstOrDefaultAsync();

        if (page == null)
            return Ok(AppResponse<object>.Success(new
            {
                type = type.ToLower(),
                title = type switch
                {
                    "terms" => "Điều khoản sử dụng",
                    "privacy" => "Chính sách bảo mật",
                    "help" => "Trợ giúp",
                    _ => type
                },
                content = "(Chưa có nội dung)",
                updatedAt = (DateTime?)null
            }));

        return Ok(AppResponse<object>.Success(new
        {
            type = page.Type,
            title = page.Title,
            content = page.Content ?? string.Empty,
            updatedAt = page.UpdatedAt ?? page.CreatedAt,
            updatedByName = page.UpdatedByName
        }));
    }
}

// ══════════════════════════════════════════════════════════════
//  SUPERADMIN: /api/system-admin/app-pages
// ══════════════════════════════════════════════════════════════
[ApiController]
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/app-pages")]
public class AppPagesAdminController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public record AppPageUpdateDto(string Title, string? Content, bool IsPublished = true);

    [HttpGet]
    public async Task<ActionResult<AppResponse<object>>> GetAll()
    {
        var pages = await db.AppPages
            .OrderBy(p => p.Type)
            .ThenByDescending(p => p.UpdatedAt ?? p.CreatedAt)
            .Select(p => new
            {
                p.Id, p.Type, p.Title, p.Content, p.IsPublished,
                p.UpdatedByName,
                updatedAt = p.UpdatedAt ?? p.CreatedAt
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(pages));
    }

    [HttpGet("{type}")]
    public async Task<ActionResult<AppResponse<object>>> GetByType(string type)
    {
        var page = await db.AppPages
            .Where(p => p.Type == type.ToLower())
            .OrderByDescending(p => p.UpdatedAt ?? p.CreatedAt)
            .FirstOrDefaultAsync();

        if (page == null) return Ok(AppResponse<object>.Success(new { type, content = "" }));

        return Ok(AppResponse<object>.Success(new
        {
            page.Id, page.Type, page.Title, page.Content, page.IsPublished,
            page.UpdatedByName, updatedAt = page.UpdatedAt ?? page.CreatedAt
        }));
    }

    [HttpPut("{type}")]
    public async Task<ActionResult<AppResponse<object>>> Upsert(string type, [FromBody] AppPageUpdateDto dto)
    {
        var normalizedType = type.ToLower();
        var page = await db.AppPages.FirstOrDefaultAsync(p => p.Type == normalizedType);

        if (page == null)
        {
            page = new AppPage { Id = Guid.NewGuid(), Type = normalizedType };
            db.AppPages.Add(page);
        }

        page.Title = dto.Title;
        page.Content = dto.Content;
        page.IsPublished = dto.IsPublished;
        page.UpdatedAt = DateTime.UtcNow;
        page.UpdatedByName = User.Identity?.Name ?? "SuperAdmin";

        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { page.Id, page.Type, page.Title, page.UpdatedAt }));
    }
}

// ══════════════════════════════════════════════════════════════
//  PUBLIC: POST /api/app-reports  (any logged-in user)
//  SUPERADMIN: GET/PUT /api/system-admin/app-reports
// ══════════════════════════════════════════════════════════════
[ApiController]
[Route("api/app-reports")]
[Authorize]
public class AppBugReportController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public record BugReportCreateDto(
        string Type,
        string Title,
        string Content,
        string? AppVersion,
        string? DeviceInfo);

    [HttpPost]
    public async Task<ActionResult<AppResponse<object>>> Submit([FromBody] BugReportCreateDto dto)
    {
        // Tìm tên cửa hàng nếu có StoreId
        string? storeName = null;
        var storeId = CurrentStoreId;
        if (storeId.HasValue)
        {
            storeName = await db.Stores
                .Where(s => s.Id == storeId.Value)
                .Select(s => s.Name)
                .FirstOrDefaultAsync();
        }

        var report = new AppBugReport
        {
            Id = Guid.NewGuid(),
            UserId = CurrentUserId.ToString(),
            UserName = User.Identity?.Name ?? CurrentUserEmail,
            UserEmail = CurrentUserEmail,
            StoreName = storeName,
            Type = dto.Type,
            Title = dto.Title,
            Content = dto.Content,
            AppVersion = dto.AppVersion,
            DeviceInfo = dto.DeviceInfo,
            Status = "New",
            CreatedAt = DateTime.UtcNow
        };

        db.AppBugReports.Add(report);
        await db.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { report.Id }));
    }
}

[ApiController]
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/app-reports")]
public class AppBugReportAdminController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public record BugReportNoteDto(string Status, string? AdminNote);

    [HttpGet]
    public async Task<ActionResult<AppResponse<object>>> GetAll(
        [FromQuery] string? status,
        [FromQuery] string? type,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var q = db.AppBugReports.AsQueryable();
        if (!string.IsNullOrEmpty(status)) q = q.Where(r => r.Status == status);
        if (!string.IsNullOrEmpty(type)) q = q.Where(r => r.Type == type);

        var total = await q.CountAsync();
        var items = await q
            .OrderByDescending(r => r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new
            {
                r.Id, r.Type, r.Title, r.Content, r.Status,
                r.UserName, r.UserEmail, r.StoreName,
                r.AppVersion, r.DeviceInfo,
                r.AdminNote, r.ResolvedAt,
                r.CreatedAt
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("stats")]
    public async Task<ActionResult<AppResponse<object>>> Stats()
    {
        var stats = await db.AppBugReports
            .GroupBy(r => r.Status)
            .Select(g => new { status = g.Key, count = g.Count() })
            .ToListAsync();

        var byType = await db.AppBugReports
            .GroupBy(r => r.Type)
            .Select(g => new { type = g.Key, count = g.Count() })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { byStatus = stats, byType }));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<AppResponse<object>>> UpdateStatus(
        Guid id, [FromBody] BugReportNoteDto dto)
    {
        var report = await db.AppBugReports.FindAsync(id);
        if (report == null) return NotFound();

        report.Status = dto.Status;
        report.AdminNote = dto.AdminNote;
        report.UpdatedAt = DateTime.UtcNow;
        if (dto.Status == "Resolved") report.ResolvedAt = DateTime.UtcNow;

        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { report.Id, report.Status }));
    }
}
