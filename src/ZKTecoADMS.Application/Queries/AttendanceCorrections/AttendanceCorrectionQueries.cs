using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.AttendanceCorrections;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.AttendanceCorrections;

// Get All Attendance Corrections Query (for Admin/Manager)
public record GetAttendanceCorrectionsQuery(
    Guid StoreId,
    int Page = 1,
    int PageSize = 10,
    Guid? EmployeeUserId = null,
    CorrectionStatus? Status = null,
    DateTime? FromDate = null,
    DateTime? ToDate = null) : IQuery<AppResponse<PagedResult<AttendanceCorrectionRequestDto>>>;

public class GetAttendanceCorrectionsHandler(
    IRepository<AttendanceCorrectionRequest> correctionRepository
) : IQueryHandler<GetAttendanceCorrectionsQuery, AppResponse<PagedResult<AttendanceCorrectionRequestDto>>>
{
    public async Task<AppResponse<PagedResult<AttendanceCorrectionRequestDto>>> Handle(GetAttendanceCorrectionsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Always filter by StoreId for multi-tenant data isolation
            Expression<Func<AttendanceCorrectionRequest, bool>> filter = a =>
                a.StoreId == request.StoreId &&
                (!request.EmployeeUserId.HasValue || a.EmployeeUserId == request.EmployeeUserId.Value) &&
                (!request.Status.HasValue || a.Status == request.Status.Value) &&
                (!request.FromDate.HasValue || a.CreatedAt >= request.FromDate.Value) &&
                (!request.ToDate.HasValue || a.CreatedAt <= request.ToDate.Value);

            var totalCount = await correctionRepository.CountAsync(filter, cancellationToken);

            var items = await correctionRepository.GetAllWithIncludeAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(a => a.CreatedAt),
                includes: q => q.Include(a => a.EmployeeUser).Include(a => a.ApprovedBy).Include(a => a.ApprovalRecords),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var result = new PagedResult<AttendanceCorrectionRequestDto>(
                items.Adapt<List<AttendanceCorrectionRequestDto>>(),
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<AttendanceCorrectionRequestDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<AttendanceCorrectionRequestDto>>.Error(ex.Message);
        }
    }
}

// Get Attendance Correction by Id Query
public record GetAttendanceCorrectionByIdQuery(Guid StoreId, Guid Id) : IQuery<AppResponse<AttendanceCorrectionRequestDto>>;

public class GetAttendanceCorrectionByIdHandler(
    IRepository<AttendanceCorrectionRequest> correctionRepository
) : IQueryHandler<GetAttendanceCorrectionByIdQuery, AppResponse<AttendanceCorrectionRequestDto>>
{
    public async Task<AppResponse<AttendanceCorrectionRequestDto>> Handle(GetAttendanceCorrectionByIdQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var correction = await correctionRepository.GetSingleAsync(
                a => a.Id == request.Id && a.StoreId == request.StoreId,
                includeProperties: ["EmployeeUser", "ApprovedBy", "ApprovalRecords"],
                cancellationToken: cancellationToken);
            
            if (correction == null)
            {
                return AppResponse<AttendanceCorrectionRequestDto>.Error("Attendance correction request not found");
            }

            return AppResponse<AttendanceCorrectionRequestDto>.Success(correction.Adapt<AttendanceCorrectionRequestDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<AttendanceCorrectionRequestDto>.Error(ex.Message);
        }
    }
}

// Get My Attendance Corrections Query (for Employee)
public record GetMyAttendanceCorrectionsQuery(
    Guid StoreId,
    Guid EmployeeUserId,
    int Page = 1,
    int PageSize = 10,
    CorrectionStatus? Status = null) : IQuery<AppResponse<PagedResult<AttendanceCorrectionRequestDto>>>;

public class GetMyAttendanceCorrectionsHandler(
    IRepository<AttendanceCorrectionRequest> correctionRepository
) : IQueryHandler<GetMyAttendanceCorrectionsQuery, AppResponse<PagedResult<AttendanceCorrectionRequestDto>>>
{
    public async Task<AppResponse<PagedResult<AttendanceCorrectionRequestDto>>> Handle(GetMyAttendanceCorrectionsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Always filter by StoreId for multi-tenant data isolation
            Expression<Func<AttendanceCorrectionRequest, bool>> filter = a => 
                a.StoreId == request.StoreId &&
                a.EmployeeUserId == request.EmployeeUserId &&
                (!request.Status.HasValue || a.Status == request.Status.Value);

            var totalCount = await correctionRepository.CountAsync(filter, cancellationToken);

            var items = await correctionRepository.GetAllWithIncludeAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(a => a.CreatedAt),
                includes: q => q.Include(a => a.EmployeeUser).Include(a => a.ApprovedBy).Include(a => a.ApprovalRecords),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var result = new PagedResult<AttendanceCorrectionRequestDto>(
                items.Adapt<List<AttendanceCorrectionRequestDto>>(),
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<AttendanceCorrectionRequestDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<AttendanceCorrectionRequestDto>>.Error(ex.Message);
        }
    }
}
