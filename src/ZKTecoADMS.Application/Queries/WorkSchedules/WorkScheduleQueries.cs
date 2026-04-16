using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.WorkSchedules;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.WorkSchedules;

// Get All Work Schedules Query (for Admin/Manager)
public record GetWorkSchedulesQuery(
    Guid StoreId,
    int Page = 1,
    int PageSize = 50,
    Guid? EmployeeUserId = null,
    DateTime? FromDate = null,
    DateTime? ToDate = null,
    Guid? ShiftId = null,
    bool? IsDayOff = null) : IQuery<AppResponse<PagedResult<WorkScheduleDto>>>;

public class GetWorkSchedulesHandler(
    IRepository<WorkSchedule> workScheduleRepository
) : IQueryHandler<GetWorkSchedulesQuery, AppResponse<PagedResult<WorkScheduleDto>>>
{
    public async Task<AppResponse<PagedResult<WorkScheduleDto>>> Handle(GetWorkSchedulesQuery request, CancellationToken cancellationToken)
    {
        try
        {
            Expression<Func<WorkSchedule, bool>> filter = w => w.StoreId == request.StoreId;

            if (request.EmployeeUserId.HasValue || request.ShiftId.HasValue || 
                request.FromDate.HasValue || request.ToDate.HasValue || request.IsDayOff.HasValue)
            {
                filter = w => 
                    w.StoreId == request.StoreId &&
                    (!request.EmployeeUserId.HasValue || w.EmployeeUserId == request.EmployeeUserId.Value) &&
                    (!request.ShiftId.HasValue || w.ShiftId == request.ShiftId.Value) &&
                    (!request.FromDate.HasValue || w.Date >= request.FromDate.Value) &&
                    (!request.ToDate.HasValue || w.Date <= request.ToDate.Value) &&
                    (!request.IsDayOff.HasValue || w.IsDayOff == request.IsDayOff.Value);
            }

            var totalCount = await workScheduleRepository.CountAsync(filter, cancellationToken);

            var items = await workScheduleRepository.GetAllWithIncludeAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(w => w.Date),
                includes: q => q.Include(w => w.Employee).Include(w => w.Shift),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var result = new PagedResult<WorkScheduleDto>(
                items.Adapt<List<WorkScheduleDto>>(),
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<WorkScheduleDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<WorkScheduleDto>>.Error(ex.Message);
        }
    }
}

// Get Work Schedule by Id Query
public record GetWorkScheduleByIdQuery(Guid StoreId, Guid Id) : IQuery<AppResponse<WorkScheduleDto>>;

public class GetWorkScheduleByIdHandler(
    IRepository<WorkSchedule> workScheduleRepository
) : IQueryHandler<GetWorkScheduleByIdQuery, AppResponse<WorkScheduleDto>>
{
    public async Task<AppResponse<WorkScheduleDto>> Handle(GetWorkScheduleByIdQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var schedule = await workScheduleRepository.GetSingleAsync(
                filter: w => w.Id == request.Id && w.StoreId == request.StoreId,
                includeProperties: ["Employee", "Shift"],
                cancellationToken: cancellationToken);
            
            if (schedule == null)
            {
                return AppResponse<WorkScheduleDto>.Error("Work schedule not found");
            }

            return AppResponse<WorkScheduleDto>.Success(schedule.Adapt<WorkScheduleDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<WorkScheduleDto>.Error(ex.Message);
        }
    }
}

// Get My Work Schedules Query (for Employee)
public record GetMyWorkSchedulesQuery(
    Guid StoreId,
    Guid EmployeeUserId,
    int Page = 1,
    int PageSize = 50,
    DateTime? FromDate = null,
    DateTime? ToDate = null) : IQuery<AppResponse<PagedResult<WorkScheduleDto>>>;

public class GetMyWorkSchedulesHandler(
    IRepository<WorkSchedule> workScheduleRepository,
    IRepository<Employee> employeeRepository
) : IQueryHandler<GetMyWorkSchedulesQuery, AppResponse<PagedResult<WorkScheduleDto>>>
{
    public async Task<AppResponse<PagedResult<WorkScheduleDto>>> Handle(GetMyWorkSchedulesQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // CurrentUserId is ApplicationUser.Id, but EmployeeUserId column stores Employee.Id
            var employee = await employeeRepository.GetSingleAsync(
                filter: e => (e.ApplicationUserId == request.EmployeeUserId || e.Id == request.EmployeeUserId) && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (employee == null)
                return AppResponse<PagedResult<WorkScheduleDto>>.Success(new PagedResult<WorkScheduleDto>([], 0, request.Page, request.PageSize));

            var employeeId = employee.Id;
            Expression<Func<WorkSchedule, bool>> filter = w => w.EmployeeUserId == employeeId && w.StoreId == request.StoreId;

            if (request.FromDate.HasValue || request.ToDate.HasValue)
            {
                var fromDate = request.FromDate;
                var toDate = request.ToDate;
                filter = w => w.EmployeeUserId == employeeId &&
                             w.StoreId == request.StoreId &&
                             (!fromDate.HasValue || w.Date >= fromDate.Value) &&
                             (!toDate.HasValue || w.Date <= toDate.Value);
            }

            var totalCount = await workScheduleRepository.CountAsync(filter, cancellationToken);

            var items = await workScheduleRepository.GetAllWithIncludeAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(w => w.Date),
                includes: q => q.Include(w => w.Employee).Include(w => w.Shift),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var result = new PagedResult<WorkScheduleDto>(
                items.Adapt<List<WorkScheduleDto>>(),
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<WorkScheduleDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<WorkScheduleDto>>.Error(ex.Message);
        }
    }
}

// Get My Schedule Registrations Query (for employees)
public record GetMyScheduleRegistrationsQuery(
    Guid StoreId,
    Guid EmployeeUserId,
    int Page = 1,
    int PageSize = 50,
    DateTime? FromDate = null,
    DateTime? ToDate = null) : IQuery<AppResponse<PagedResult<ScheduleRegistrationDto>>>;

public class GetMyScheduleRegistrationsHandler(
    IRepository<ScheduleRegistration> registrationRepository,
    IRepository<Employee> employeeRepository
) : IQueryHandler<GetMyScheduleRegistrationsQuery, AppResponse<PagedResult<ScheduleRegistrationDto>>>
{
    public async Task<AppResponse<PagedResult<ScheduleRegistrationDto>>> Handle(GetMyScheduleRegistrationsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var employee = await employeeRepository.GetSingleAsync(
                filter: e => (e.ApplicationUserId == request.EmployeeUserId || e.Id == request.EmployeeUserId) && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (employee == null)
                return AppResponse<PagedResult<ScheduleRegistrationDto>>.Success(new PagedResult<ScheduleRegistrationDto>([], 0, request.Page, request.PageSize));

            var employeeId = employee.Id;
            Expression<Func<ScheduleRegistration, bool>> filter = r => r.EmployeeUserId == employeeId && r.StoreId == request.StoreId;

            if (request.FromDate.HasValue || request.ToDate.HasValue)
            {
                var fromDate = request.FromDate;
                var toDate = request.ToDate;
                filter = r => r.EmployeeUserId == employeeId &&
                             r.StoreId == request.StoreId &&
                             (!fromDate.HasValue || r.Date >= fromDate.Value) &&
                             (!toDate.HasValue || r.Date <= toDate.Value);
            }

            var totalCount = await registrationRepository.CountAsync(filter, cancellationToken);

            var items = await registrationRepository.GetAllWithIncludeAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(r => r.Date),
                includes: q => q.Include(r => r.Employee).Include(r => r.Shift).Include(r => r.ApprovedBy),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var result = new PagedResult<ScheduleRegistrationDto>(
                items.Adapt<List<ScheduleRegistrationDto>>(),
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<ScheduleRegistrationDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<ScheduleRegistrationDto>>.Error(ex.Message);
        }
    }
}

// Get Schedule Registrations Query
public record GetScheduleRegistrationsQuery(
    Guid StoreId,
    int Page = 1,
    int PageSize = 50,
    Guid? EmployeeUserId = null,
    ScheduleRegistrationStatus? Status = null,
    DateTime? FromDate = null,
    DateTime? ToDate = null) : IQuery<AppResponse<PagedResult<ScheduleRegistrationDto>>>;

public class GetScheduleRegistrationsHandler(
    IRepository<ScheduleRegistration> registrationRepository
) : IQueryHandler<GetScheduleRegistrationsQuery, AppResponse<PagedResult<ScheduleRegistrationDto>>>
{
    public async Task<AppResponse<PagedResult<ScheduleRegistrationDto>>> Handle(GetScheduleRegistrationsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            Expression<Func<ScheduleRegistration, bool>> filter = r => r.StoreId == request.StoreId;

            if (request.EmployeeUserId.HasValue || request.Status.HasValue || 
                request.FromDate.HasValue || request.ToDate.HasValue)
            {
                filter = r => 
                    r.StoreId == request.StoreId &&
                    (!request.EmployeeUserId.HasValue || r.EmployeeUserId == request.EmployeeUserId.Value) &&
                    (!request.Status.HasValue || r.Status == request.Status.Value) &&
                    (!request.FromDate.HasValue || r.Date >= request.FromDate.Value) &&
                    (!request.ToDate.HasValue || r.Date <= request.ToDate.Value);
            }

            var totalCount = await registrationRepository.CountAsync(filter, cancellationToken);

            var items = await registrationRepository.GetAllWithIncludeAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(r => r.Date),
                includes: q => q.Include(r => r.Employee).Include(r => r.Shift).Include(r => r.ApprovedBy),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var result = new PagedResult<ScheduleRegistrationDto>(
                items.Adapt<List<ScheduleRegistrationDto>>(),
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<ScheduleRegistrationDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<ScheduleRegistrationDto>>.Error(ex.Message);
        }
    }
}
