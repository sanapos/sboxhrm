using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.AdvanceRequests;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.AdvanceRequests;

// Get All Advance Requests Query (for Admin/Manager)
public record GetAdvanceRequestsQuery(
    Guid StoreId,
    int Page = 1,
    int PageSize = 10,
    Guid? EmployeeUserId = null,
    AdvanceRequestStatus? Status = null,
    DateTime? FromDate = null,
    DateTime? ToDate = null) : IQuery<AppResponse<PagedResult<AdvanceRequestDto>>>;

public class GetAdvanceRequestsHandler(
    IRepository<AdvanceRequest> advanceRequestRepository
) : IQueryHandler<GetAdvanceRequestsQuery, AppResponse<PagedResult<AdvanceRequestDto>>>
{
    public async Task<AppResponse<PagedResult<AdvanceRequestDto>>> Handle(GetAdvanceRequestsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Always filter by StoreId for multi-tenant data isolation
            Expression<Func<AdvanceRequest, bool>> filter = a =>
                a.StoreId == request.StoreId &&
                (!request.EmployeeUserId.HasValue || a.EmployeeUserId == request.EmployeeUserId.Value) &&
                (!request.Status.HasValue || a.Status == request.Status.Value) &&
                (!request.FromDate.HasValue || a.RequestDate >= request.FromDate.Value) &&
                (!request.ToDate.HasValue || a.RequestDate <= request.ToDate.Value);

            var totalCount = await advanceRequestRepository.CountAsync(filter, cancellationToken);

            var items = await advanceRequestRepository.GetAllWithIncludeAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(a => a.RequestDate),
                includes: q => q.Include(a => a.EmployeeUser).Include(a => a.Employee).Include(a => a.ApprovedBy).Include(a => a.ApprovalRecords),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var result = new PagedResult<AdvanceRequestDto>(
                items.Adapt<List<AdvanceRequestDto>>(),
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<AdvanceRequestDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<AdvanceRequestDto>>.Error(ex.Message);
        }
    }
}

// Get Advance Request by Id Query
public record GetAdvanceRequestByIdQuery(Guid StoreId, Guid Id) : IQuery<AppResponse<AdvanceRequestDto>>;

public class GetAdvanceRequestByIdHandler(
    IRepository<AdvanceRequest> advanceRequestRepository
) : IQueryHandler<GetAdvanceRequestByIdQuery, AppResponse<AdvanceRequestDto>>
{
    public async Task<AppResponse<AdvanceRequestDto>> Handle(GetAdvanceRequestByIdQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var advanceRequest = await advanceRequestRepository.GetSingleAsync(
                a => a.Id == request.Id && a.StoreId == request.StoreId, 
                includeProperties: ["EmployeeUser", "Employee", "ApprovedBy", "ApprovalRecords"],
                cancellationToken: cancellationToken);
            
            if (advanceRequest == null)
            {
                return AppResponse<AdvanceRequestDto>.Error("Advance request not found");
            }

            return AppResponse<AdvanceRequestDto>.Success(advanceRequest.Adapt<AdvanceRequestDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<AdvanceRequestDto>.Error(ex.Message);
        }
    }
}

// Get My Advance Requests Query (for Employee)
public record GetMyAdvanceRequestsQuery(
    Guid StoreId,
    Guid EmployeeUserId,
    int Page = 1,
    int PageSize = 10,
    AdvanceRequestStatus? Status = null) : IQuery<AppResponse<PagedResult<AdvanceRequestDto>>>;

public class GetMyAdvanceRequestsHandler(
    IRepository<AdvanceRequest> advanceRequestRepository
) : IQueryHandler<GetMyAdvanceRequestsQuery, AppResponse<PagedResult<AdvanceRequestDto>>>
{
    public async Task<AppResponse<PagedResult<AdvanceRequestDto>>> Handle(GetMyAdvanceRequestsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Always filter by StoreId for multi-tenant data isolation
            Expression<Func<AdvanceRequest, bool>> filter = a => 
                a.StoreId == request.StoreId && 
                a.EmployeeUserId == request.EmployeeUserId &&
                (!request.Status.HasValue || a.Status == request.Status.Value);

            var totalCount = await advanceRequestRepository.CountAsync(filter, cancellationToken);

            var items = await advanceRequestRepository.GetAllWithIncludeAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(a => a.RequestDate),
                includes: q => q.Include(a => a.EmployeeUser).Include(a => a.Employee).Include(a => a.ApprovedBy).Include(a => a.ApprovalRecords),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var result = new PagedResult<AdvanceRequestDto>(
                items.Adapt<List<AdvanceRequestDto>>(),
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<AdvanceRequestDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<AdvanceRequestDto>>.Error(ex.Message);
        }
    }
}
