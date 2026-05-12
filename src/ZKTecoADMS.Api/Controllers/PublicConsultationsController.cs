using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using System.Text.RegularExpressions;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PublicConsultationsController : ControllerBase
{
    private readonly ZKTecoDbContext _dbContext;
    private readonly ILogger<PublicConsultationsController> _logger;

    public PublicConsultationsController(
        ZKTecoDbContext dbContext,
        ILogger<PublicConsultationsController> logger)
    {
        _dbContext = dbContext;
        _logger = logger;
    }

    public record CreateConsultationRequestDto(
        string Name,
        string Phone,
        string? Company,
        string? Province,
        string? InterestedPlan,
        string? Notes,
        string? Website
    );

    public record ConsultationRequestDto(
        Guid Id,
        string Name,
        string Phone,
        string? Company,
        string? Province,
        string? InterestedPlan,
        string Status,
        string Source,
        string? Notes,
        string? AdminNote,
        DateTime CreatedAt
    );

    [HttpPost]
    [EnableRateLimiting("public-form")]
    public async Task<ActionResult<AppResponse<ConsultationRequestDto>>> Create([FromBody] CreateConsultationRequestDto dto)
    {
        try
        {
            var name = dto.Name?.Trim() ?? string.Empty;
            var phone = dto.Phone?.Trim() ?? string.Empty;
            var company = string.IsNullOrWhiteSpace(dto.Company) ? null : dto.Company.Trim();
            var province = string.IsNullOrWhiteSpace(dto.Province) ? null : dto.Province.Trim();
            var interestedPlan = string.IsNullOrWhiteSpace(dto.InterestedPlan) ? null : dto.InterestedPlan.Trim();
            var notes = string.IsNullOrWhiteSpace(dto.Notes) ? null : dto.Notes.Trim();
            var website = string.IsNullOrWhiteSpace(dto.Website) ? null : dto.Website.Trim();
            var normalizedPhone = Regex.Replace(phone, "[^0-9]", string.Empty);

            if (string.IsNullOrWhiteSpace(name))
            {
                return BadRequest(AppResponse<ConsultationRequestDto>.Fail("Vui lòng nhập họ và tên"));
            }

            if (!string.IsNullOrEmpty(website))
            {
                return BadRequest(AppResponse<ConsultationRequestDto>.Fail("Yêu cầu không hợp lệ"));
            }

            if (string.IsNullOrWhiteSpace(normalizedPhone) || normalizedPhone.Length < 9 || normalizedPhone.Length > 15)
            {
                return BadRequest(AppResponse<ConsultationRequestDto>.Fail("Số điện thoại không hợp lệ"));
            }

            var duplicateWindow = DateTime.UtcNow.AddMinutes(-10);
            var hasRecentDuplicate = await _dbContext.ConsultationRequests
                .AnyAsync(x => x.NormalizedPhone == normalizedPhone && x.CreatedAt >= duplicateWindow);

            if (hasRecentDuplicate)
            {
                return Conflict(AppResponse<ConsultationRequestDto>.Fail("Bạn vừa gửi yêu cầu gần đây. Vui lòng chờ ít phút rồi thử lại."));
            }

            var request = new ConsultationRequest
            {
                Id = Guid.NewGuid(),
                Name = name,
                Phone = phone,
                NormalizedPhone = normalizedPhone,
                Company = company,
                Province = province,
                InterestedPlan = interestedPlan,
                Notes = notes,
                Status = "New",
                Source = "LandingPage",
                ClientIp = HttpContext.Connection.RemoteIpAddress?.ToString(),
                UserAgent = Request.Headers.UserAgent.ToString(),
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = "PublicLanding"
            };

            _dbContext.ConsultationRequests.Add(request);
            await _dbContext.SaveChangesAsync();

            return Ok(AppResponse<ConsultationRequestDto>.Success(new ConsultationRequestDto(
                request.Id,
                request.Name,
                request.Phone,
                request.Company,
                request.Province,
                request.InterestedPlan,
                request.Status,
                request.Source,
                request.Notes,
                request.AdminNote,
                request.CreatedAt
            )));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating public consultation request");
            return StatusCode(500, AppResponse<ConsultationRequestDto>.Fail("Không thể gửi yêu cầu tư vấn lúc này"));
        }
    }
}

[ApiController]
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/consultation-requests")]
public class ConsultationRequestsAdminController : AuthenticatedControllerBase
{
    private readonly ZKTecoDbContext _dbContext;

    public ConsultationRequestsAdminController(ZKTecoDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public record UpdateConsultationRequestDto(string Status, string? AdminNote);

    [HttpGet]
    public async Task<ActionResult<AppResponse<object>>> GetAll(
        [FromQuery] string? status,
        [FromQuery] string? search,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var normalizedSearch = search?.Trim().ToLower();
        var query = _dbContext.ConsultationRequests.AsQueryable();

        if (!string.IsNullOrWhiteSpace(status))
        {
            query = query.Where(x => x.Status == status);
        }

        if (!string.IsNullOrWhiteSpace(normalizedSearch))
        {
            query = query.Where(x =>
                x.Name.ToLower().Contains(normalizedSearch) ||
                x.Phone.Contains(normalizedSearch) ||
                (x.Company != null && x.Company.ToLower().Contains(normalizedSearch)) ||
                (x.Province != null && x.Province.ToLower().Contains(normalizedSearch)) ||
                (x.InterestedPlan != null && x.InterestedPlan.ToLower().Contains(normalizedSearch)));
        }

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(x => x.CreatedAt)
            .Skip((Math.Max(page, 1) - 1) * Math.Max(pageSize, 1))
            .Take(Math.Clamp(pageSize, 1, 200))
            .Select(x => new
            {
                x.Id,
                x.Name,
                x.Phone,
                x.Company,
                x.Province,
                x.InterestedPlan,
                x.Status,
                x.Source,
                x.Notes,
                x.AdminNote,
                x.ClientIp,
                x.UserAgent,
                x.CreatedAt,
                x.UpdatedAt,
                x.UpdatedBy
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<AppResponse<object>>> Update(Guid id, [FromBody] UpdateConsultationRequestDto dto)
    {
        var request = await _dbContext.ConsultationRequests.FirstOrDefaultAsync(x => x.Id == id);
        if (request == null)
        {
            return NotFound(AppResponse<object>.Fail("Không tìm thấy yêu cầu tư vấn"));
        }

        request.Status = string.IsNullOrWhiteSpace(dto.Status) ? request.Status : dto.Status.Trim();
        request.AdminNote = string.IsNullOrWhiteSpace(dto.AdminNote) ? null : dto.AdminNote.Trim();
        request.UpdatedAt = DateTime.UtcNow;
        request.UpdatedBy = CurrentUserEmail ?? User.Identity?.Name ?? "SuperAdmin";

        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { request.Id, request.Status, request.AdminNote }));
    }

    [HttpDelete("{id:guid}")]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var request = await _dbContext.ConsultationRequests.FirstOrDefaultAsync(x => x.Id == id);
        if (request == null)
        {
            return NotFound(AppResponse<object>.Fail("Không tìm thấy yêu cầu tư vấn"));
        }

        _dbContext.ConsultationRequests.Remove(request);
        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { request.Id }));
    }
}