using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Khách lưu trú theo lượt nhận phòng (khách sạn) + sổ khách lưu trú để khai báo tạm trú.
/// </summary>
[ApiController]
[Route("api/pos/stay-guests")]
[Authorize]
public class PosStayGuestsController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record StayGuestDto(
        Guid Id, Guid ResourceSessionId, string FullName, string IdType, string? IdNumber,
        DateTime? DateOfBirth, string? Gender, string? Nationality, string? Address,
        string? Phone, string? Note, bool IsPrimary);

    public record StayGuestSaveDto(
        Guid ResourceSessionId, string FullName, string? IdType, string? IdNumber,
        DateTime? DateOfBirth, string? Gender, string? Nationality, string? Address,
        string? Phone, string? Note, bool IsPrimary = false);

    public record RegisterRowDto(
        Guid Id, string RoomCode, string RoomName, DateTime CheckInAt, DateTime? CheckOutAt,
        string FullName, string IdType, string? IdNumber, DateTime? DateOfBirth, string? Gender,
        string? Nationality, string? Address, string? Phone, bool IsPrimary, string? Note);

    static StayGuestDto Map(PosStayGuest g) => new(
        g.Id, g.ResourceSessionId, g.FullName, g.IdType, g.IdNumber, g.DateOfBirth, g.Gender,
        g.Nationality, g.Address, g.Phone, g.Note, g.IsPrimary);

    [HttpGet]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<StayGuestDto>>>> List([FromQuery] Guid sessionId)
    {
        var storeId = RequiredStoreId;
        var rows = await dbContext.PosStayGuests.AsNoTracking()
            .Where(g => g.StoreId == storeId && g.ResourceSessionId == sessionId)
            .OrderByDescending(g => g.IsPrimary).ThenBy(g => g.CreatedAt)
            .ToListAsync();
        return Ok(AppResponse<List<StayGuestDto>>.Success(rows.Select(Map).ToList()));
    }

    [HttpPost]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<StayGuestDto>>> Create([FromBody] StayGuestSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var err = Validate(dto);
        if (err != null) return BadRequest(AppResponse<StayGuestDto>.Fail(err));
        var sessionOk = await dbContext.PosResourceSessions.AsNoTracking()
            .AnyAsync(s => s.Id == dto.ResourceSessionId && s.StoreId == storeId && s.Deleted == null);
        if (!sessionOk) return NotFound(AppResponse<StayGuestDto>.Fail("Không tìm thấy lượt nhận phòng"));

        var g = new PosStayGuest
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ResourceSessionId = dto.ResourceSessionId,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = CurrentUserEmail,
            IsActive = true,
        };
        Apply(g, dto);
        if (g.IsPrimary)
            await ClearOtherPrimaryAsync(storeId, g.ResourceSessionId, g.Id);
        else if (!await dbContext.PosStayGuests.AnyAsync(x => x.StoreId == storeId && x.ResourceSessionId == g.ResourceSessionId))
            g.IsPrimary = true; // khách đầu tiên = người đứng tên
        dbContext.PosStayGuests.Add(g);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<StayGuestDto>.Success(Map(g)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<StayGuestDto>>> Update(Guid id, [FromBody] StayGuestSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var err = Validate(dto);
        if (err != null) return BadRequest(AppResponse<StayGuestDto>.Fail(err));
        var g = await dbContext.PosStayGuests.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (g == null) return NotFound(AppResponse<StayGuestDto>.Fail("Không tìm thấy khách"));
        Apply(g, dto);
        g.UpdatedAt = DateTime.UtcNow;
        g.UpdatedBy = CurrentUserEmail;
        if (g.IsPrimary) await ClearOtherPrimaryAsync(storeId, g.ResourceSessionId, g.Id);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<StayGuestDto>.Success(Map(g)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var g = await dbContext.PosStayGuests.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (g == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy khách"));
        g.Deleted = DateTime.UtcNow;
        g.DeletedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id }));
    }

    /// <summary>
    /// Sổ khách lưu trú: mọi khách có lượt ở giao với kỳ (theo giờ Việt Nam). <c>format=excel</c> xuất file
    /// để khai báo tạm trú. Chứa số giấy tờ → cần quyền Sửa bán hàng (quản lý).
    /// </summary>
    [HttpGet("register")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<IActionResult> Register(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? format = null)
    {
        var storeId = RequiredStoreId;
        var (fromLocal, toLocal, utcStart, utcEnd) = ReportHelpers.VnRange(from, to);
        var rows = await dbContext.PosStayGuests.AsNoTracking()
            .Where(g => g.StoreId == storeId
                && g.ResourceSession != null
                && g.ResourceSession.StartedAt < utcEnd
                && (g.ResourceSession.EndedAt == null || g.ResourceSession.EndedAt >= utcStart))
            .OrderBy(g => g.ResourceSession!.StartedAt).ThenByDescending(g => g.IsPrimary)
            .Select(g => new RegisterRowDto(
                g.Id,
                g.ResourceSession!.Resource != null ? g.ResourceSession.Resource.Code : "",
                g.ResourceSession.Resource != null ? g.ResourceSession.Resource.Name : "",
                g.ResourceSession.StartedAt, g.ResourceSession.EndedAt,
                g.FullName, g.IdType, g.IdNumber, g.DateOfBirth, g.Gender, g.Nationality,
                g.Address, g.Phone, g.IsPrimary, g.Note))
            .ToListAsync();

        if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
        {
            return ReportHelpers.ExcelFile("So khach luu tru",
                new[] { "STT", "Phòng", "Nhận phòng", "Trả phòng", "Họ tên", "Giấy tờ", "Số giấy tờ",
                        "Ngày sinh", "Giới tính", "Quốc tịch", "Địa chỉ", "Điện thoại", "Ghi chú" },
                (ws, start) =>
                {
                    var r = start;
                    var i = 1;
                    foreach (var g in rows)
                    {
                        ws.Cell(r, 1).Value = i++;
                        ws.Cell(r, 2).Value = string.IsNullOrWhiteSpace(g.RoomName) ? g.RoomCode : g.RoomName;
                        ws.Cell(r, 3).Value = ReportHelpers.ToVn(g.CheckInAt).ToString("dd/MM/yyyy HH:mm");
                        ws.Cell(r, 4).Value = g.CheckOutAt is DateTime o ? ReportHelpers.ToVn(o).ToString("dd/MM/yyyy HH:mm") : "Đang ở";
                        ws.Cell(r, 5).Value = g.FullName + (g.IsPrimary ? " (đứng tên)" : "");
                        ws.Cell(r, 6).Value = g.IdType;
                        ws.Cell(r, 7).Value = g.IdNumber ?? "";
                        ws.Cell(r, 8).Value = g.DateOfBirth?.ToString("dd/MM/yyyy") ?? "";
                        ws.Cell(r, 9).Value = g.Gender ?? "";
                        ws.Cell(r, 10).Value = g.Nationality ?? "";
                        ws.Cell(r, 11).Value = g.Address ?? "";
                        ws.Cell(r, 12).Value = g.Phone ?? "";
                        ws.Cell(r, 13).Value = g.Note ?? "";
                        r++;
                    }
                },
                $"so-khach-luu-tru-{fromLocal:yyyyMMdd}-{toLocal:yyyyMMdd}.xlsx", user: User);
        }
        return Ok(AppResponse<object>.Success(new { from = fromLocal, to = toLocal, total = rows.Count, items = rows }));
    }

    static string? Validate(StayGuestSaveDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.FullName)) return "Nhập họ tên khách";
        if (dto.FullName.Trim().Length > 200) return "Họ tên quá dài";
        if (dto.DateOfBirth is DateTime d && (d.Year < 1900 || d > DateTime.UtcNow)) return "Ngày sinh không hợp lệ";
        return null;
    }

    static void Apply(PosStayGuest g, StayGuestSaveDto dto)
    {
        static string? T(string? v, int max) =>
            string.IsNullOrWhiteSpace(v) ? null : (v.Trim().Length > max ? v.Trim()[..max] : v.Trim());
        g.FullName = T(dto.FullName, 200)!;
        g.IdType = T(dto.IdType, 30) ?? "CCCD";
        g.IdNumber = T(dto.IdNumber, 50);
        g.DateOfBirth = dto.DateOfBirth?.Date;
        g.Gender = T(dto.Gender, 20);
        g.Nationality = T(dto.Nationality, 100) ?? "Việt Nam";
        g.Address = T(dto.Address, 500);
        g.Phone = T(dto.Phone, 30);
        g.Note = T(dto.Note, 500);
        g.IsPrimary = dto.IsPrimary;
    }

    async Task ClearOtherPrimaryAsync(Guid storeId, Guid sessionId, Guid keepId)
    {
        var others = await dbContext.PosStayGuests.AsTracking()
            .Where(x => x.StoreId == storeId && x.ResourceSessionId == sessionId && x.Id != keepId && x.IsPrimary)
            .ToListAsync();
        foreach (var o in others) o.IsPrimary = false;
    }
}
