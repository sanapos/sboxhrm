using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Meals.CreateMealMenu;
using ZKTecoADMS.Application.Commands.Meals.CreateMealSession;
using ZKTecoADMS.Application.Commands.Meals.DeleteMealMenu;
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
    IRepository<MealDebt> mealDebtRepository,
    IRepository<MealDish> mealDishRepository,
    ISystemNotificationService notificationService
) : AuthenticatedControllerBase
{
    // ══════════ MEAL DISHES (Master list) ══════════

    [HttpGet("dishes")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<MealDishDto>>>> GetMealDishes()
    {
        var storeId = RequiredStoreId;
        var dishes = await mealDishRepository.GetAllAsync(
            filter: d => d.StoreId == storeId && d.IsActive,
            orderBy: q => q.OrderBy(d => d.Category).ThenBy(d => d.SortOrder).ThenBy(d => d.Name));
        var dtos = dishes.Select(d => new MealDishDto
        {
            Id = d.Id,
            Name = d.Name,
            Category = d.Category,
            SortOrder = d.SortOrder,
            IsActive = d.IsActive,
        }).ToList();
        return Ok(AppResponse<List<MealDishDto>>.Success(dtos));
    }

    [HttpPost("dishes")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<MealDishDto>>> CreateMealDish([FromBody] CreateMealDishRequest request)
    {
        var dish = new MealDish
        {
            Name = request.Name.Trim(),
            Category = request.Category?.Trim(),
            SortOrder = request.SortOrder,
            IsActive = true,
            StoreId = RequiredStoreId,
        };
        await mealDishRepository.AddAsync(dish);
        var dto = new MealDishDto
        {
            Id = dish.Id,
            Name = dish.Name,
            Category = dish.Category,
            SortOrder = dish.SortOrder,
            IsActive = dish.IsActive,
        };
        return Ok(AppResponse<MealDishDto>.Success(dto));
    }

    [HttpPut("dishes/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<MealDishDto>>> UpdateMealDish(Guid id, [FromBody] UpdateMealDishRequest request)
    {
        var dish = await mealDishRepository.GetByIdAsync(id);
        if (dish == null || dish.StoreId != RequiredStoreId)
            return NotFound(AppResponse<MealDishDto>.Fail("Không tìm thấy món ăn"));
        dish.Name = request.Name.Trim();
        dish.Category = request.Category?.Trim();
        dish.SortOrder = request.SortOrder;
        await mealDishRepository.UpdateAsync(dish);
        var dto = new MealDishDto
        {
            Id = dish.Id,
            Name = dish.Name,
            Category = dish.Category,
            SortOrder = dish.SortOrder,
            IsActive = dish.IsActive,
        };
        return Ok(AppResponse<MealDishDto>.Success(dto));
    }

    [HttpDelete("dishes/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteMealDish(Guid id)
    {
        var dish = await mealDishRepository.GetByIdAsync(id);
        if (dish == null || dish.StoreId != RequiredStoreId)
            return NotFound(AppResponse<bool>.Fail("Không tìm thấy món ăn"));
        dish.IsActive = false;
        await mealDishRepository.UpdateAsync(dish);
        return Ok(AppResponse<bool>.Success(true));
    }

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
            request.PricePerMeal,
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
            request.PricePerMeal,
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

    [HttpDelete("menu/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteMealMenu(Guid id)
    {
        var command = new DeleteMealMenuCommand(RequiredStoreId, id);
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

    // ══════════ MEAL DEBT MANAGEMENT (công nợ suất ăn) ══════════

    /// <summary>
    /// Tổng hợp công nợ suất ăn theo kỳ
    /// </summary>
    [HttpGet("debt/summary")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<List<MealDebtSummaryDto>>>> GetDebtSummary(
        [FromQuery] string? period,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to)
    {
        try
        {
            var storeId = RequiredStoreId;
            var targetPeriod = period ?? DateTime.UtcNow.ToString("yyyy-MM");
            var fromDate = from ?? new DateTime(DateTime.UtcNow.Year, DateTime.UtcNow.Month, 1);
            var toDate = to ?? fromDate.AddMonths(1).AddDays(-1);

            // Get all meal records in period
            var records = await mealRecordRepository.GetAllAsync(
                r => r.StoreId == storeId && r.Date >= fromDate && r.Date <= toDate,
                includeProperties: new[] { "MealSession", "EmployeeUser" });

            // Get sessions for pricing
            var sessions = await mealSessionRepository.GetAllAsync(s => s.StoreId == storeId && s.IsActive);
            var sessionPrices = sessions.ToDictionary(s => s.Id, s => s.PricePerMeal);

            // Get debt records
            var debts = await mealDebtRepository.GetAllAsync(
                d => d.StoreId == storeId && d.Period == targetPeriod);

            // Group by employee
            var grouped = records.GroupBy(r => r.EmployeeUserId).Select(g =>
            {
                var totalMeals = g.Count();
                var totalCharged = g.Sum(r => sessionPrices.GetValueOrDefault(r.MealSessionId, 0));
                var empDebts = debts.Where(d => d.EmployeeUserId == g.Key);
                var totalPaid = empDebts.Where(d => d.Type == 1).Sum(d => d.Amount);
                var first = g.First();

                return new MealDebtSummaryDto
                {
                    EmployeeUserId = g.Key,
                    EmployeeName = first.EmployeeUser?.FullName ?? first.PIN ?? "",
                    EmployeeCode = first.PIN,
                    TotalMeals = totalMeals,
                    TotalCharged = totalCharged,
                    TotalPaid = totalPaid,
                    Balance = totalCharged - totalPaid,
                };
            }).OrderBy(s => s.EmployeeName).ToList();

            return Ok(AppResponse<List<MealDebtSummaryDto>>.Success(grouped));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<List<MealDebtSummaryDto>>.Error(ex.Message));
        }
    }

    /// <summary>
    /// Lịch sử giao dịch công nợ (charge/payment) của 1 nhân viên
    /// </summary>
    [HttpGet("debt/history")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<MealDebtDto>>>> GetDebtHistory(
        [FromQuery] Guid? employeeUserId,
        [FromQuery] string? period)
    {
        try
        {
            var storeId = RequiredStoreId;
            var targetUserId = employeeUserId ?? CurrentUserId;
            var targetPeriod = period ?? DateTime.UtcNow.ToString("yyyy-MM");

            var debts = await mealDebtRepository.GetAllAsync(
                d => d.StoreId == storeId && d.EmployeeUserId == targetUserId &&
                     (period == null || d.Period == targetPeriod),
                includeProperties: new[] { "MealSession" });

            var result = debts.OrderByDescending(d => d.Date).Select(d => new MealDebtDto
            {
                Id = d.Id,
                EmployeeUserId = d.EmployeeUserId,
                EmployeeName = d.EmployeeName,
                Type = d.Type,
                Amount = d.Amount,
                Date = d.Date,
                MealSessionId = d.MealSessionId,
                MealSessionName = d.MealSession?.Name,
                Period = d.Period,
                Note = d.Note,
                RecordedByName = d.RecordedByName,
                CreatedAt = d.CreatedAt,
            }).ToList();

            return Ok(AppResponse<List<MealDebtDto>>.Success(result));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<List<MealDebtDto>>.Error(ex.Message));
        }
    }

    /// <summary>
    /// Ghi nhận thanh toán / trừ công nợ
    /// </summary>
    [HttpPost("debt")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<MealDebtDto>>> CreateDebt([FromBody] CreateMealDebtRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var recorderName = User.FindFirst("FullName")?.Value ?? "";

            var debt = new MealDebt
            {
                EmployeeUserId = request.EmployeeUserId,
                EmployeeName = "", // will be resolved
                Type = request.Type,
                Amount = request.Amount,
                Date = DateTime.UtcNow,
                Period = request.Period ?? DateTime.UtcNow.ToString("yyyy-MM"),
                Note = request.Note,
                RecordedByUserId = CurrentUserId,
                RecordedByName = recorderName,
                StoreId = storeId,
            };

            await mealDebtRepository.AddAsync(debt);

            return Ok(AppResponse<MealDebtDto>.Success(new MealDebtDto
            {
                Id = debt.Id,
                EmployeeUserId = debt.EmployeeUserId,
                EmployeeName = debt.EmployeeName,
                Type = debt.Type,
                Amount = debt.Amount,
                Date = debt.Date,
                Period = debt.Period,
                Note = debt.Note,
                RecordedByName = debt.RecordedByName,
                CreatedAt = debt.CreatedAt,
            }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<MealDebtDto>.Error(ex.Message));
        }
    }

    /// <summary>
    /// Tự động tính công nợ cho cả tháng dựa trên meal records
    /// </summary>
    [HttpPost("debt/batch-charge")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<object>>> BatchChargeMeals([FromBody] BatchChargeRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var period = request.Period;
            var year = int.Parse(period.Split('-')[0]);
            var month = int.Parse(period.Split('-')[1]);
            var fromDate = new DateTime(year, month, 1);
            var toDate = fromDate.AddMonths(1).AddDays(-1);
            var recorderName = User.FindFirst("FullName")?.Value ?? "";

            // Get all records in period
            var records = await mealRecordRepository.GetAllAsync(
                r => r.StoreId == storeId && r.Date >= fromDate && r.Date <= toDate,
                includeProperties: new[] { "MealSession", "EmployeeUser" });

            var sessions = await mealSessionRepository.GetAllAsync(s => s.StoreId == storeId);
            var sessionPrices = sessions.ToDictionary(s => s.Id, s => s.PricePerMeal);

            // Delete existing charges for this period (re-calculate)
            var existingCharges = await mealDebtRepository.GetAllAsync(
                d => d.StoreId == storeId && d.Period == period && d.Type == 0);
            foreach (var c in existingCharges)
                await mealDebtRepository.DeleteAsync(c);

            // Create charges per employee
            var grouped = records.GroupBy(r => r.EmployeeUserId);
            var count = 0;
            foreach (var g in grouped)
            {
                var total = g.Sum(r => sessionPrices.GetValueOrDefault(r.MealSessionId, 0));
                if (total <= 0) continue;

                var first = g.First();
                await mealDebtRepository.AddAsync(new MealDebt
                {
                    EmployeeUserId = g.Key,
                    EmployeeName = first.EmployeeUser?.FullName ?? "",
                    Type = 0, // Charge
                    Amount = total,
                    Date = DateTime.UtcNow,
                    Period = period,
                    Note = $"Tiền ăn tháng {month}/{year}: {g.Count()} suất",
                    RecordedByUserId = CurrentUserId,
                    RecordedByName = recorderName,
                    StoreId = storeId,
                });
                count++;
            }

            return Ok(AppResponse<object>.Success(new { count, message = $"Đã tính công nợ cho {count} nhân viên" }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<object>.Error(ex.Message));
        }
    }

    // ══════════ MEAL RECORDS – MANUAL CRUD (quản lý chấm cơm) ══════════

    /// <summary>
    /// Manager: thêm chấm cơm thủ công cho nhân viên
    /// </summary>
    [HttpPost("records")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<MealRecordDto>>> CreateMealRecord([FromBody] CreateMealRecordRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var session = await mealSessionRepository.GetSingleAsync(
                s => s.Id == request.MealSessionId && s.StoreId == storeId && s.IsActive);
            if (session == null)
                return Ok(AppResponse<MealRecordDto>.Error("Buổi ăn không tồn tại"));

            var record = new MealRecord
            {
                EmployeeUserId = request.EmployeeUserId,
                MealSessionId = request.MealSessionId,
                MealTime = request.MealTime ?? DateTime.UtcNow,
                Date = request.Date.Date,
                StoreId = storeId,
                PIN = request.PIN,
            };
            await mealRecordRepository.AddAsync(record);

            return Ok(AppResponse<MealRecordDto>.Success(new MealRecordDto
            {
                Id = record.Id,
                EmployeeUserId = record.EmployeeUserId,
                MealSessionId = record.MealSessionId,
                MealSessionName = session.Name,
                MealTime = record.MealTime,
                Date = record.Date,
                StoreId = storeId,
                CreatedAt = record.CreatedAt,
            }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<MealRecordDto>.Error(ex.Message));
        }
    }

    /// <summary>
    /// Manager: sửa bản ghi chấm cơm
    /// </summary>
    [HttpPut("records/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<MealRecordDto>>> UpdateMealRecord(Guid id, [FromBody] UpdateMealRecordRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var record = await mealRecordRepository.GetByIdAsync(id);
            if (record == null || record.StoreId != storeId)
                return NotFound(AppResponse<MealRecordDto>.Fail("Không tìm thấy bản ghi"));

            if (request.MealSessionId.HasValue)
                record.MealSessionId = request.MealSessionId.Value;
            if (request.MealTime.HasValue)
                record.MealTime = request.MealTime.Value;
            if (request.Date.HasValue)
                record.Date = request.Date.Value.Date;

            await mealRecordRepository.UpdateAsync(record);

            var session = await mealSessionRepository.GetByIdAsync(record.MealSessionId);
            return Ok(AppResponse<MealRecordDto>.Success(new MealRecordDto
            {
                Id = record.Id,
                EmployeeUserId = record.EmployeeUserId,
                MealSessionId = record.MealSessionId,
                MealSessionName = session?.Name,
                MealTime = record.MealTime,
                Date = record.Date,
                StoreId = storeId,
                CreatedAt = record.CreatedAt,
            }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<MealRecordDto>.Error(ex.Message));
        }
    }

    /// <summary>
    /// Manager: xóa bản ghi chấm cơm
    /// </summary>
    [HttpDelete("records/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteMealRecord(Guid id)
    {
        try
        {
            var storeId = RequiredStoreId;
            var record = await mealRecordRepository.GetByIdAsync(id);
            if (record == null || record.StoreId != storeId)
                return NotFound(AppResponse<bool>.Fail("Không tìm thấy bản ghi"));
            await mealRecordRepository.DeleteAsync(record);
            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<bool>.Error(ex.Message));
        }
    }

    // ══════════ REGISTRATION MANAGEMENT (quản lý đăng ký ăn) ══════════

    /// <summary>
    /// Manager: lấy danh sách đăng ký ăn chi tiết theo ngày (toàn bộ nhân viên)
    /// </summary>
    [HttpGet("registrations")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<List<MealRegistrationDto>>>> GetRegistrations(
        [FromQuery] DateTime? date,
        [FromQuery] Guid? mealSessionId)
    {
        try
        {
            var storeId = RequiredStoreId;
            var targetDate = date?.Date ?? DateTime.UtcNow.Date;

            var regs = await registrationRepository.GetAllAsync(
                r => r.StoreId == storeId && r.Date == targetDate &&
                     r.IsRegistered &&
                     (mealSessionId == null || r.MealSessionId == mealSessionId));

            var result = regs.OrderBy(r => r.EmployeeName).Select(r => new MealRegistrationDto
            {
                Id = r.Id,
                EmployeeUserId = r.EmployeeUserId,
                EmployeeName = r.EmployeeName,
                MealSessionId = r.MealSessionId,
                Date = r.Date,
                IsRegistered = r.IsRegistered,
                RegisteredAt = r.RegisteredAt,
                CancelledAt = r.CancelledAt,
                Note = r.Note,
            }).ToList();

            return Ok(AppResponse<List<MealRegistrationDto>>.Success(result));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<List<MealRegistrationDto>>.Error(ex.Message));
        }
    }

    /// <summary>
    /// Manager: đăng ký ăn cho nhân viên
    /// </summary>
    [HttpPost("registrations")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<MealRegistrationDto>>> CreateRegistration([FromBody] ManagerMealRegistrationRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var date = request.Date.Date;

            // Upsert
            var existing = await registrationRepository.GetSingleAsync(
                r => r.EmployeeUserId == request.EmployeeUserId && r.MealSessionId == request.MealSessionId && r.Date == date);

            if (existing != null)
            {
                existing.IsRegistered = true;
                existing.RegisteredAt = DateTime.UtcNow;
                existing.CancelledAt = null;
                existing.Note = request.Note;
                await registrationRepository.UpdateAsync(existing);
                return Ok(AppResponse<MealRegistrationDto>.Success(new MealRegistrationDto
                {
                    Id = existing.Id, EmployeeUserId = existing.EmployeeUserId,
                    EmployeeName = existing.EmployeeName, MealSessionId = existing.MealSessionId,
                    Date = existing.Date, IsRegistered = true, RegisteredAt = existing.RegisteredAt,
                    Note = existing.Note,
                }));
            }

            var reg = new MealRegistration
            {
                EmployeeUserId = request.EmployeeUserId,
                EmployeeName = request.EmployeeName ?? "",
                MealSessionId = request.MealSessionId,
                Date = date,
                IsRegistered = true,
                RegisteredAt = DateTime.UtcNow,
                Note = request.Note,
                StoreId = storeId,
            };
            await registrationRepository.AddAsync(reg);
            return Ok(AppResponse<MealRegistrationDto>.Success(new MealRegistrationDto
            {
                Id = reg.Id, EmployeeUserId = reg.EmployeeUserId,
                EmployeeName = reg.EmployeeName, MealSessionId = reg.MealSessionId,
                Date = reg.Date, IsRegistered = true, RegisteredAt = reg.RegisteredAt,
                Note = reg.Note,
            }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<MealRegistrationDto>.Error(ex.Message));
        }
    }

    /// <summary>
    /// Manager: hủy đăng ký ăn
    /// </summary>
    [HttpDelete("registrations/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteRegistration(Guid id)
    {
        try
        {
            var storeId = RequiredStoreId;
            var reg = await registrationRepository.GetByIdAsync(id);
            if (reg == null || reg.StoreId != storeId)
                return NotFound(AppResponse<bool>.Fail("Không tìm thấy đăng ký"));
            await registrationRepository.DeleteAsync(reg);
            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<bool>.Error(ex.Message));
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

public class CreateMealRecordRequest
{
    public Guid EmployeeUserId { get; set; }
    public Guid MealSessionId { get; set; }
    public DateTime Date { get; set; }
    public DateTime? MealTime { get; set; }
    public string? PIN { get; set; }
}

public class UpdateMealRecordRequest
{
    public Guid? MealSessionId { get; set; }
    public DateTime? MealTime { get; set; }
    public DateTime? Date { get; set; }
}

public class ManagerMealRegistrationRequest
{
    public Guid EmployeeUserId { get; set; }
    public string? EmployeeName { get; set; }
    public Guid MealSessionId { get; set; }
    public DateTime Date { get; set; }
    public string? Note { get; set; }
}
