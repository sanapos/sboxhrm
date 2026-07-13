using ZKTecoADMS.Application.DTOs.BusinessTrip;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.BusinessTrip;

public record GetBusinessTripCasesQuery(
    Guid StoreId,
    int Page = 1,
    int PageSize = 20,
    Guid? EmployeeUserId = null,
    BusinessTripCaseStatus? Status = null,
    DateTime? FromDate = null,
    DateTime? ToDate = null,
    Guid? CategoryId = null) : IQuery<AppResponse<PagedResult<BusinessTripCaseDto>>>;

public class GetBusinessTripCasesHandler(IRepository<BusinessTripCase> caseRepository)
    : IQueryHandler<GetBusinessTripCasesQuery, AppResponse<PagedResult<BusinessTripCaseDto>>>
{
    public async Task<AppResponse<PagedResult<BusinessTripCaseDto>>> Handle(GetBusinessTripCasesQuery request, CancellationToken ct)
    {
        var from = request.FromDate?.Date;
        var toExclusive = request.ToDate?.Date.AddDays(1);

        var items = await caseRepository.GetAllAsync(
            c => c.StoreId == request.StoreId
                 && (!request.EmployeeUserId.HasValue || c.EmployeeUserId == request.EmployeeUserId)
                 && (request.Status.HasValue
                     ? c.Status == request.Status
                     : c.Status != BusinessTripCaseStatus.Cancelled)
                 && (!from.HasValue || (c.TripFromDate ?? c.CreatedAt) >= from.Value)
                 && (!toExclusive.HasValue || (c.TripFromDate ?? c.CreatedAt) < toExclusive.Value)
                 && (!request.CategoryId.HasValue
                     || (c.SettlementClaim != null
                         && c.SettlementClaim.Lines.Any(l => l.CategoryId == request.CategoryId))),
            orderBy: q => q.OrderByDescending(c => c.CreatedAt),
            includeProperties: BusinessTripCaseLoader.ListIncludes,
            skip: (request.Page - 1) * request.PageSize,
            take: request.PageSize,
            cancellationToken: ct);

        var total = await caseRepository.CountAsync(
            c => c.StoreId == request.StoreId
                 && (!request.EmployeeUserId.HasValue || c.EmployeeUserId == request.EmployeeUserId)
                 && (request.Status.HasValue
                     ? c.Status == request.Status
                     : c.Status != BusinessTripCaseStatus.Cancelled)
                 && (!from.HasValue || (c.TripFromDate ?? c.CreatedAt) >= from.Value)
                 && (!toExclusive.HasValue || (c.TripFromDate ?? c.CreatedAt) < toExclusive.Value)
                 && (!request.CategoryId.HasValue
                     || (c.SettlementClaim != null
                         && c.SettlementClaim.Lines.Any(l => l.CategoryId == request.CategoryId))),
            ct);

        return AppResponse<PagedResult<BusinessTripCaseDto>>.Success(new PagedResult<BusinessTripCaseDto>(
            items.Select(BusinessTripMapper.ToDto).ToList(), total, request.Page, request.PageSize));
    }
}

public record GetBusinessTripCaseByIdQuery(
    Guid StoreId,
    Guid Id,
    Guid CurrentUserId,
    bool IsPrivileged) : IQuery<AppResponse<BusinessTripCaseDto>>;

public class GetBusinessTripCaseByIdHandler(IRepository<BusinessTripCase> caseRepository)
    : IQueryHandler<GetBusinessTripCaseByIdQuery, AppResponse<BusinessTripCaseDto>>
{
    public async Task<AppResponse<BusinessTripCaseDto>> Handle(GetBusinessTripCaseByIdQuery request, CancellationToken ct)
    {
        var entity = await BusinessTripCaseLoader.LoadAsync(caseRepository, request.Id, request.StoreId, ct);
        if (entity == null)
            return AppResponse<BusinessTripCaseDto>.Error("Không tìm thấy hồ sơ công tác");

        var deny = BusinessTripAccess.DenyIfCannotAccess(entity, request.CurrentUserId, request.IsPrivileged);
        if (deny != null)
            return AppResponse<BusinessTripCaseDto>.Error(deny);

        return AppResponse<BusinessTripCaseDto>.Success(BusinessTripMapper.ToDto(entity));
    }
}

public record GetBusinessTripExpenseCategoriesQuery(Guid StoreId) : IQuery<AppResponse<List<BusinessTripExpenseCategoryDto>>>;

public class GetBusinessTripExpenseCategoriesHandler(IRepository<BusinessTripExpenseCategory> categoryRepository)
    : IQueryHandler<GetBusinessTripExpenseCategoriesQuery, AppResponse<List<BusinessTripExpenseCategoryDto>>>
{
    public async Task<AppResponse<List<BusinessTripExpenseCategoryDto>>> Handle(
        GetBusinessTripExpenseCategoriesQuery request, CancellationToken ct)
    {
        var items = await categoryRepository.GetAllAsync(
            c => c.StoreId == request.StoreId && c.IsActive,
            orderBy: q => q.OrderBy(c => c.SortOrder).ThenBy(c => c.Name),
            cancellationToken: ct);
        return AppResponse<List<BusinessTripExpenseCategoryDto>>.Success(
            items.Select(BusinessTripMapper.ToCategoryDto).ToList());
    }
}

public record GetPendingBusinessTripApprovalsQuery(Guid StoreId, Guid UserId, bool SettlementOnly = false)
    : IQuery<AppResponse<List<BusinessTripCaseDto>>>;

public class GetPendingBusinessTripApprovalsHandler(IRepository<BusinessTripCase> caseRepository)
    : IQueryHandler<GetPendingBusinessTripApprovalsQuery, AppResponse<List<BusinessTripCaseDto>>>
{
    public async Task<AppResponse<List<BusinessTripCaseDto>>> Handle(
        GetPendingBusinessTripApprovalsQuery request, CancellationToken ct)
    {
        var all = await caseRepository.GetAllAsync(
            c => c.StoreId == request.StoreId,
            orderBy: q => q.OrderByDescending(c => c.UpdatedAt),
            includeProperties: BusinessTripCaseLoader.CaseIncludesPublic,
            take: 200,
            cancellationToken: ct);

        var filtered = all.Where(c =>
            (!request.SettlementOnly && c.AdvanceClaim != null && c.AdvanceClaim.Status == AdvanceRequestStatus.Pending
             && c.AdvanceClaim.ApprovalRecords.Any(r =>
                 r.Status == ApprovalStatus.Pending && r.AssignedUserId == request.UserId))
            || (request.SettlementOnly && c.SettlementClaim != null && c.SettlementClaim.Status == AdvanceRequestStatus.Pending
                && c.SettlementClaim.ApprovalRecords.Any(r =>
                    r.Status == ApprovalStatus.Pending && r.AssignedUserId == request.UserId)))
            .Take(100)
            .Select(BusinessTripMapper.ToDto)
            .ToList();

        return AppResponse<List<BusinessTripCaseDto>>.Success(filtered);
    }
}
