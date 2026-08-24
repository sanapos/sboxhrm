using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/cashier-shifts")]
[Authorize]
public class PosCashierShiftsController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public class OpenShiftDto
    {
        public decimal OpeningCash { get; set; }
        public string? Note { get; set; }
    }
    public class CloseShiftDto
    {
        public decimal CountedCash { get; set; }
        public string? Note { get; set; }
    }

    public record ShiftDto(
        Guid Id,
        DateTime OpenedAt,
        string? OpenedByName,
        decimal OpeningCash,
        DateTime? ClosedAt,
        string? ClosedByName,
        decimal? CountedCash,
        decimal? ExpectedCash,
        decimal? Difference,
        string Status,
        string? Note,
        bool Enabled);

    /// <summary>
    /// Danh sách ca trong khoảng ngày (phục vụ tổng kết cuối ngày / đối chiếu két).
    /// Không thay thế EOD: EOD vẫn cộng đơn bán theo ngày; mỗi ca là phiếu đếm két riêng.
    /// </summary>
    [HttpGet]
    [RequireModulePermission("PosCashierShift", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string? openedBy,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = dayStartHour;
        if (hour == null)
        {
            hour = await db.PosStoreSellSettings.AsNoTracking()
                .Where(s => s.StoreId == storeId && s.Deleted == null)
                .Select(s => (int?)s.ReportDayStartHour)
                .FirstOrDefaultAsync() ?? 0;
        }
        var (fromUtc, toUtc, _, _) = VnTimeHelper.ResolvePosBusinessRange(from, to, hour.Value);

        var q = db.PosCashierShifts.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null
                && s.OpenedAt >= fromUtc && s.OpenedAt < toUtc);

        // Thu ngân thường chỉ xem ca của mình; quản lý/admin xem cả cửa hàng (hoặc lọc openedBy).
        if (!IsAdmin && !IsManager)
        {
            q = q.Where(s => s.OpenedByUserId == CurrentUserId);
        }
        else if (!string.IsNullOrWhiteSpace(openedBy))
        {
            var by = openedBy.Trim();
            q = q.Where(s => s.OpenedByName == by || s.CreatedBy == by);
        }

        var rows = await q.OrderBy(s => s.OpenedAt).ToListAsync();
        var list = new List<object>(rows.Count);
        foreach (var s in rows)
        {
            var expected = s.ExpectedCash ?? await ExpectedCashAsync(storeId, s);
            list.Add(Map(s, expected));
        }

        return Ok(AppResponse<object>.Success(new
        {
            enabled = await IsEnabledAsync(storeId),
            items = list,
            count = list.Count,
        }));
    }

    [HttpGet("current")]
    [RequireModulePermission("PosCashierShift", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Current()
    {
        var storeId = RequiredStoreId;
        var userId = CurrentUserId;
        var enabled = await IsEnabledAsync(storeId);
        // Mỗi thu ngân (tài khoản) một ca mở — nhiều máy/nhiều người cùng cửa hàng được.
        var open = await db.PosCashierShifts.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null && s.Status == "Open"
                && s.OpenedByUserId == userId)
            .OrderByDescending(s => s.OpenedAt)
            .FirstOrDefaultAsync();
        if (open == null)
        {
            return Ok(AppResponse<object>.Success(new
            {
                enabled,
                open = false,
                shift = (object?)null,
            }));
        }
        var expected = await ExpectedCashAsync(storeId, open);
        return Ok(AppResponse<object>.Success(new
        {
            enabled,
            open = true,
            shift = Map(open, expected),
        }));
    }

    [HttpPost("open")]
    [RequireModulePermission("PosCashierShift", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Open([FromBody] OpenShiftDto? dto)
    {
        var storeId = RequiredStoreId;
        var userId = CurrentUserId;
        if (!await IsEnabledAsync(storeId))
            return BadRequest(AppResponse<object>.Fail("Chưa bật ca thu ngân trong thiết lập POS"));
        var exists = await db.PosCashierShifts.AsNoTracking()
            .AnyAsync(s => s.StoreId == storeId && s.Deleted == null && s.Status == "Open"
                && s.OpenedByUserId == userId);
        if (exists)
            return BadRequest(AppResponse<object>.Fail("Bạn đang có ca mở — đóng ca trước khi mở ca mới"));

        var now = DateTime.UtcNow;
        var shift = new PosCashierShift
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            OpenedAt = now,
            OpenedByUserId = userId,
            OpenedByName = CurrentUserEmail,
            OpeningCash = Math.Max(0, dto?.OpeningCash ?? 0),
            Note = dto?.Note?.Trim(),
            Status = "Open",
            IsActive = true,
            CreatedAt = now,
            CreatedBy = CurrentUserEmail,
        };
        db.PosCashierShifts.Add(shift);
        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException ex) when (IsOpenShiftConflict(ex))
        {
            return BadRequest(AppResponse<object>.Fail("Bạn đang có ca mở — đóng ca trước khi mở ca mới"));
        }
        return Ok(AppResponse<object>.Success(new
        {
            enabled = true,
            open = true,
            shift = Map(shift, shift.OpeningCash),
        }));
    }

    [HttpPost("{id:guid}/close")]
    [RequireModulePermission("PosCashierShift", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Close(Guid id, [FromBody] CloseShiftDto? dto)
    {
        var storeId = RequiredStoreId;
        var shift = await db.PosCashierShifts.AsTracking()
            .FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (shift == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy ca"));
        if (shift.Status != "Open")
            return BadRequest(AppResponse<object>.Fail("Ca đã đóng"));
        // Chỉ đóng ca của chính mình (trừ admin cửa hàng).
        if (shift.OpenedByUserId != CurrentUserId && !IsAdmin && !IsManager)
            return BadRequest(AppResponse<object>.Fail("Chỉ đóng được ca của chính bạn"));

        var expected = await ExpectedCashAsync(storeId, shift);
        var counted = Math.Max(0, dto?.CountedCash ?? 0);
        var now = DateTime.UtcNow;
        shift.ClosedAt = now;
        shift.ClosedByUserId = CurrentUserId;
        shift.ClosedByName = CurrentUserEmail;
        shift.CountedCash = counted;
        shift.ExpectedCash = expected;
        shift.Difference = counted - expected;
        shift.Status = "Closed";
        if (!string.IsNullOrWhiteSpace(dto?.Note))
            shift.Note = dto!.Note.Trim();
        shift.UpdatedAt = now;
        shift.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            enabled = true,
            open = false,
            shift = Map(shift, expected),
        }));
    }

    async Task<bool> IsEnabledAsync(Guid storeId) =>
        await db.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => s.EnableCashierShift)
            .FirstOrDefaultAsync();

    /// <summary>Kỳ vọng = đầu ca + đơn tiền mặt do chính thu ngân này bán trong ca.</summary>
    async Task<decimal> ExpectedCashAsync(Guid storeId, PosCashierShift shift)
    {
        var from = shift.OpenedAt;
        var to = shift.ClosedAt ?? DateTime.UtcNow;
        var byEmail = (shift.OpenedByName ?? "").Trim();
        var cashSales = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Completed
                && o.SaleDate != null
                && o.SaleDate >= from && o.SaleDate <= to
                && o.PaymentMethod != null
                && o.PaymentMethod == "Tiền mặt"
                && byEmail != ""
                && (o.SoldBy == byEmail || o.CreatedBy == byEmail))
            .SumAsync(o => (decimal?)o.PaidAmount) ?? 0;
        return shift.OpeningCash + cashSales;
    }

    static bool IsOpenShiftConflict(Exception ex)
    {
        for (var e = ex; e != null; e = e.InnerException)
        {
            if (e is Npgsql.PostgresException { SqlState: "23505" })
                return true;
            if (e.Message.Contains("IX_PosCashierShifts_Store_OneOpen", StringComparison.Ordinal)
                || e.Message.Contains("IX_PosCashierShifts_Store_User_OneOpen", StringComparison.Ordinal))
                return true;
        }
        return false;
    }

    static ShiftDto Map(PosCashierShift s, decimal expected) => new(
        s.Id, s.OpenedAt, s.OpenedByName, s.OpeningCash,
        s.ClosedAt, s.ClosedByName, s.CountedCash, expected,
        s.CountedCash.HasValue ? s.CountedCash.Value - expected : null,
        s.Status, s.Note, true);
}
