using System.Linq.Expressions;
using System.Text.Json;
using ZKTecoADMS.Application.DTOs.Allowances;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Allowances;

// Get All Allowances Query
public record GetAllowancesQuery(
    Guid StoreId,
    int Page = 1,
    int PageSize = 10,
    AllowanceType? Type = null,
    bool? IsActive = null,
    string? SearchTerm = null) : IQuery<AppResponse<PagedResult<AllowanceDto>>>;

public class GetAllowancesHandler(
    IRepository<Allowance> allowanceRepository
) : IQueryHandler<GetAllowancesQuery, AppResponse<PagedResult<AllowanceDto>>>
{
    public async Task<AppResponse<PagedResult<AllowanceDto>>> Handle(GetAllowancesQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Always filter by StoreId for multi-tenant data isolation
            Expression<Func<Allowance, bool>> filter = a => 
                a.StoreId == request.StoreId &&
                (!request.Type.HasValue || a.Type == request.Type.Value) &&
                (!request.IsActive.HasValue || a.IsActive == request.IsActive.Value) &&
                (string.IsNullOrEmpty(request.SearchTerm) || 
                    a.Name.Contains(request.SearchTerm) || 
                    (a.Code != null && a.Code.Contains(request.SearchTerm)));

            var totalCount = await allowanceRepository.CountAsync(filter, cancellationToken);

            var items = await allowanceRepository.GetAllAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(a => a.CreatedAt),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var dtos = items.Select(a =>
            {
                var dto = a.Adapt<AllowanceDto>();
                dto.EmployeeIds = string.IsNullOrEmpty(a.EmployeeIds) ? null : JsonSerializer.Deserialize<List<string>>(a.EmployeeIds);
                return dto;
            }).ToList();

            var result = new PagedResult<AllowanceDto>(
                dtos,
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<AllowanceDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<AllowanceDto>>.Error(ex.Message);
        }
    }
}

// Get Allowance by Id Query
public record GetAllowanceByIdQuery(Guid StoreId, Guid Id) : IQuery<AppResponse<AllowanceDto>>;

public class GetAllowanceByIdHandler(
    IRepository<Allowance> allowanceRepository
) : IQueryHandler<GetAllowanceByIdQuery, AppResponse<AllowanceDto>>
{
    public async Task<AppResponse<AllowanceDto>> Handle(GetAllowanceByIdQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var allowance = await allowanceRepository.GetSingleAsync(
                a => a.Id == request.Id && a.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (allowance == null)
            {
                return AppResponse<AllowanceDto>.Error("Allowance not found");
            }

            var dto = allowance.Adapt<AllowanceDto>();
            dto.EmployeeIds = string.IsNullOrEmpty(allowance.EmployeeIds) ? null : JsonSerializer.Deserialize<List<string>>(allowance.EmployeeIds);
            return AppResponse<AllowanceDto>.Success(dto);
        }
        catch (Exception ex)
        {
            return AppResponse<AllowanceDto>.Error(ex.Message);
        }
    }
}
