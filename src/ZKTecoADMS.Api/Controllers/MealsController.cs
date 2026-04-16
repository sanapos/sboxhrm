using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Meals.CreateMealMenu;
using ZKTecoADMS.Application.Commands.Meals.CreateMealSession;
using ZKTecoADMS.Application.Commands.Meals.DeleteMealSession;
using ZKTecoADMS.Application.Commands.Meals.UpdateMealMenu;
using ZKTecoADMS.Application.Commands.Meals.UpdateMealSession;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Meals;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Queries.Meals.GetEmployeeMealSummary;
using ZKTecoADMS.Application.Queries.Meals.GetMealEstimate;
using ZKTecoADMS.Application.Queries.Meals.GetMealMenu;
using ZKTecoADMS.Application.Queries.Meals.GetMealRecords;
using ZKTecoADMS.Application.Queries.Meals.GetMealSessions;
using ZKTecoADMS.Application.Queries.Meals.GetWeeklyMealMenu;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
using MediatR;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class MealsController(
    IMediator mediator,
    IRepository<MealRegistration> registrationRepository,
    IRepository<MealSession> mealSessionRepository,
    IRepository<MealRecord> mealRecordRepository,
    ISystemNotificationService notificationService
) : AuthenticatedControllerBase
{
    // ══════════ MEAL SESSIONS ══════════

    [HttpGet("sessions")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<MealSessionDto>>>> GetMealSessions()
    {
        var query = new GetMealSessionsQuery(RequiredStoreId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost("sessions")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<MealSessionDto>>> CreateMealSession([FromBody] CreateMealSessionRequest request)
    {
        var command = new CreateMealSessionCommand(
            RequiredStoreId,
            request.Name,
            request.StartTime,
            request.EndTime,
            request.Description,
            request.ShiftTemplateIds);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPut("sessions/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<MealSessionDto>>> UpdateMealSession(Guid id, [FromBody] UpdateMealSessionRequest request)
    {
        var command = new UpdateMealSessionCommand(
            RequiredStoreId,
            id,
            request.Name,
            request.StartTime,
            request.EndTime,
            request.Description,
            request.ShiftTemplateIds);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("sessions/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteMealSession(Guid id)
    {
        var command = new DeleteMealSessionCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    // ══════════ MEAL ESTIMATE ══════════

    [HttpGet("estimate")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<MealSummaryDto>>> GetMealEstimate([FromQuery] DateTime? date)
    {
        var query = new GetMealEstimateQuery(RequiredStoreId, date ?? DateTime.Today);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    // ══════════ MEAL RECORDS ══════════

    [HttpGet("records")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<MealRecordDto>>>> GetMealRecords(
        [FromQuery] DateTime? date,
        [FromQuery] Guid? mealSessionId,
        [FromQuery] PaginationRequest paginationRequest)
    {
        var query = new GetMealRecordsQuery(RequiredStoreId, date ?? DateTime.Today, mealSessionId, paginationRequest);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    // ══════════ MEAL SUMMARY (per employee) ══════════

    [HttpGet("summary")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<EmployeeMealSummaryDto>>>> GetEmployeeMealSummary(
        [FromQuery] DateTime from,
        [FromQuery] DateTime to,
        [FromQuery] Guid? employeeUserId)
    {
        var query = new GetEmployeeMealSummaryQuery(RequiredStoreId, from, to, employeeUserId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    // ══════════ MEAL MENU ══════════

    [HttpGet("menu")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<MealMenuDto>>>> GetMealMenu(
        [FromQuery] DateTime? date,
        [FromQuery] Guid? mealSessionId)
    {
        var query = new GetMealMenuQuery(RequiredStoreId, date ?? DateTime.Today, mealSessionId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("menu/weekly")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<MealMenuDto>>>> GetWeeklyMealMenu([FromQuery] DateTime? weekStartDate)
    {
        var startDate = weekStartDate ?? DateTime.Today.AddDays(-(int)DateTime.Today.DayOfWeek + 1);
        var query = new GetWeeklyMealMenuQuery(RequiredStoreId, startDate);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost("menu")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<MealMenuDto>>> CreateMealMenu([FromBody] CreateMealMenuRequest request)
    {
        var command = new CreateMealMenuCommand(
            RequiredStoreId,
            request.Date,
            request.MealSessionId,
            request.Note,
            request.Items);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPut("menu/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<MealMenuDto>>> UpdateMealMenu(Guid id, [FromBody] UpdateMealMenuRequest request)
    {
        var command = new UpdateMealMenuCommand(
            RequiredStoreId,
            id,
            request.Note,
            request.Items);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    // ══════════ MEAL REGISTRATION (đăng ký suất ăn) ══════════

    /// <summary>
    /// Đăng ký ăn cho 1 ngày + buổi
    /// </summary>
    [HttpPost("register")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<object>>> RegisterMeal([FromBody] MealRegistrationRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;
            var date = request.Date.Date;

            // Validate session exists
            var session = await mealSessionRepository.GetSingleAsync(
                s => s.Id == request.MealSessionId && s.StoreId == storeId && s.IsActive);
            if (session == null)
                return Ok(AppResponse<object>.Error("Buổi ăn không tồn tại"));

            // Check deadline: cannot register after session start time on same day
            if (date == DateTime.UtcNow.Date && DateTime.UtcNow.TimeOfDay >= session.StartTime)
                return Ok(AppResponse<object>.Error("Đã quá hạn đăng ký cho buổi này"));

            // Upsert
            var existing = await registrationRepository.GetSingleAsync(
                r => r.EmployeeUserId == userId && r.MealSessionId == request.MealSessionId && r.Date == date);

            if (existing != null)
            {
                existing.IsRegistered = request.IsRegistered;
                existing.Note = request.Note;
                existing.RegisteredAt = DateTime.UtcNow;
                existing.CancelledAt = request.IsRegistered ? null : DateTime.UtcNow;
                await registrationRepository.UpdateAsync(existing);

                return Ok(AppResponse<object>.Success(new
                {
                    existing.Id,
                    existing.IsRegistered,
                    message = request.IsRegistered ? "Đã đăng ký ăn" : "Đã huỷ đăng ký"
                }));
            }

            var reg = new MealRegistration
            {
                EmployeeUserId = userId,
                EmployeeName = User.FindFirst("FullName")?.Value ?? "",
                MealSessionId = request.MealSessionId,
                Date = date,
                IsRegistered = request.IsRegistered,
                RegisteredAt = DateTime.UtcNow,
                CancelledAt = request.IsRegistered ? null : DateTime.UtcNow,
                Note = request.Note,
                StoreId = storeId
            };
            await registrationRepository.AddAsync(reg);

            return Ok(AppResponse<object>.Success(new
            {
                reg.Id,
                reg.IsRegistered,
                message = request.IsRegistered ? "Đã đăng ký ăn" : "Đã huỷ đăng ký"
            }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<object>.Error(ex.Message));
        }
    }

    /// <summary>
    /// Đăng ký ăn hàng loạt cho nhiều ngày (cả tuần)
    /// </summary>
    [HttpPost("register/batch")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<object>>> BatchRegisterMeal([FromBody] BatchMealRegistrationRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;
            var employeeName = User.FindFirst("FullName")?.Value ?? "";
            var count = 0;

            foreach (var item in request.Registrations)
            {
                var date = item.Date.Date;
                var existing = await registrationRepository.GetSingleAsync(
                    r => r.EmployeeUserId == userId && r.MealSessionId == item.MealSessionId && r.Date == date);

                if (existing != null)
                {
                    existing.IsRegistered = item.IsRegistered;
                    existing.RegisteredAt = DateTime.UtcNow;
                    existing.CancelledAt = item.IsRegistered ? null : DateTime.UtcNow;
                    await registrationRepository.UpdateAsync(existing);
                }
                else
                {
                    await registrationRepository.AddAsync(new MealRegistration
                    {
                        EmployeeUserId = userId,
                        EmployeeName = employeeName,
                        MealSessionId = item.MealSessionId,
                        Date = date,
                        IsRegistered = item.IsRegistered,
                        RegisteredAt = DateTime.UtcNow,
                        Note = item.Note,
                        StoreId = storeId
                    });
                }
                count++;
            }

            return Ok(AppResponse<object>.Success(new { count, message = $"Đã đăng ký {count} suất ăn" }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<object>.Error(ex.Message));
        }
    }

    /// <summary>
    /// Lấy đăng ký ăn của tôi theo tuần
    /// </summary>
    [HttpGet("register/my")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<object>>>> GetMyRegistrations(
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;
            var from = fromDate?.Date ?? DateTime.UtcNow.Date;
            var to = toDate?.Date ?? from.AddDays(7);

            var regs = await registrationRepository.GetAllAsync(
                r => r.EmployeeUserId == userId && r.StoreId == storeId &&
                     r.Date >= from && r.Date <= to);

            var result = regs.Select(r => new
            {
                r.Id,
                r.MealSessionId,
                r.Date,
                r.IsRegistered,
                r.RegisteredAt,
                r.CancelledAt,
                r.Note
            }).OrderBy(r => r.Date).ThenBy(r => r.MealSessionId).ToList();

            return Ok(AppResponse<List<object>>.Success(result.Cast<object>().ToList()));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<List<object>>.Error(ex.Message));
        }
    }

    /// <summary>
    /// Manager: tổng hợp đăng ký ăn theo ngày
    /// </summary>
    [HttpGet("register/summary")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<object>>> GetRegistrationSummary(
        [FromQuery] DateTime? date,
        [FromQuery] Guid? mealSessionId)
    {
        try
        {
            var storeId = RequiredStoreId;
            var targetDate = date?.Date ?? DateTime.UtcNow.Date;

            var regs = await registrationRepository.GetAllAsync(
                r => r.StoreId == storeId && r.Date == targetDate &&
                     (mealSessionId == null || r.MealSessionId == mealSessionId));

            var sessions = await mealSessionRepository.GetAllAsync(
                s => s.StoreId == storeId && s.IsActive);

            var summary = sessions.Select(s =>
            {
                var sessionRegs = regs.Where(r => r.MealSessionId == s.Id).ToList();
                return new
                {
                    MealSessionId = s.Id,
                    MealSessionName = s.Name,
                    s.StartTime,
                    s.EndTime,
                    RegisteredCount = sessionRegs.Count(r => r.IsRegistered),
                    CancelledCount = sessionRegs.Count(r => !r.IsRegistered),
                    Employees = sessionRegs.Where(r => r.IsRegistered).Select(r => new
                    {
                        r.EmployeeUserId,
                        r.EmployeeName,
                        r.RegisteredAt,
                        r.Note
                    }).ToList()
                };
            }).ToList();

            return Ok(AppResponse<object>.Success(new
            {
                Date = targetDate,
                TotalRegistered = summary.Sum(s => s.RegisteredCount),
                Sessions = summary
            }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<object>.Error(ex.Message));
        }
    }

    // ══════════ QR MEAL CHECK-IN (chấm cơm bằng QR từ mobile) ══════════

    /// <summary>
    /// Nhân viên tự chấm cơm bằng QR code (thay thế quẹt thẻ trên máy)
    /// </summary>
    [HttpPost("checkin/qr")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<object>>> QrMealCheckIn([FromBody] QrMealCheckInRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId;
            var now = DateTime.UtcNow;

            // Find matching active session by time or by explicit ID
            MealSession? session;
            if (request.MealSessionId.HasValue)
            {
                session = await mealSessionRepository.GetSingleAsync(
                    s => s.Id == request.MealSessionId.Value && s.StoreId == storeId && s.IsActive);
            }
            else
            {
                var timeOfDay = now.TimeOfDay;
                var sessions = await mealSessionRepository.GetAllAsync(
                    s => s.StoreId == storeId && s.IsActive);
                session = sessions.FirstOrDefault(s => timeOfDay >= s.StartTime && timeOfDay <= s.EndTime)
                       ?? sessions.OrderBy(s => Math.Abs((timeOfDay - s.StartTime).TotalMinutes)).FirstOrDefault();
            }

            if (session == null)
                return Ok(AppResponse<object>.Error("Không tìm thấy buổi ăn phù hợp"));

            // Check time window: allow check-in from 15min before start to end
            var timeNow = now.TimeOfDay;
            var earlyStart = session.StartTime.Subtract(TimeSpan.FromMinutes(15));
            if (timeNow < earlyStart || timeNow > session.EndTime)
                return Ok(AppResponse<object>.Error($"Chưa đến giờ chấm cơm ({session.StartTime:hh\\:mm} - {session.EndTime:hh\\:mm})"));

            // Check duplicate
            var date = now.Date;
            var exists = await mealRecordRepository.ExistsAsync(
                r => r.EmployeeUserId == userId && r.MealSessionId == session.Id && r.Date == date);
            if (exists)
                return Ok(AppResponse<object>.Error("Bạn đã chấm cơm cho buổi này rồi"));

            var record = new MealRecord
            {
                EmployeeUserId = userId,
                MealSessionId = session.Id,
                MealTime = now,
                Date = date,
                StoreId = storeId,
                PIN = request.QrCode
            };
            await mealRecordRepository.AddAsync(record);

            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: userId,
                    type: NotificationType.Success,
                    title: "Chấm cơm QR thành công",
                    message: $"Đã ghi nhận {session.Name} lúc {now:HH:mm}",
                    relatedEntityId: record.Id,
                    relatedEntityType: "MealRecord",
                    categoryCode: "meal",
                    storeId: storeId);
            }
            catch { }

            return Ok(AppResponse<object>.Success(new
            {
                record.Id,
                MealSessionName = session.Name,
                record.MealTime,
                message = $"Chấm cơm thành công - {session.Name}"
            }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<object>.Error(ex.Message));
        }
    }
}

// ══════════ REQUEST DTOs ══════════

public class MealRegistrationRequest
{
    public Guid MealSessionId { get; set; }
    public DateTime Date { get; set; }
    public bool IsRegistered { get; set; } = true;
    public string? Note { get; set; }
}

public class BatchMealRegistrationRequest
{
    public List<MealRegistrationRequest> Registrations { get; set; } = [];
}

public class QrMealCheckInRequest
{
    public Guid? MealSessionId { get; set; }
    public string? QrCode { get; set; }
}
