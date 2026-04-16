using System.Linq.Expressions;
using ZKTecoADMS.Application.DTOs.ShiftSalaryLevels;
using ZKTecoADMS.Application.DTOs.Commons;

namespace ZKTecoADMS.Application.Queries.ShiftSalaryLevels;

// Get All ShiftSalaryLevels Query (with optional shiftTemplateId filter)
public record GetShiftSalaryLevelsQuery(
    Guid StoreId,
    Guid? ShiftTemplateId = null,
    bool? IsActive = null,
    int Page = 1,
    int PageSize = 100) : IQuery<AppResponse<PagedResult<ShiftSalaryLevelDto>>>;

public class GetShiftSalaryLevelsHandler(
    IRepository<ShiftSalaryLevel> repository
) : IQueryHandler<GetShiftSalaryLevelsQuery, AppResponse<PagedResult<ShiftSalaryLevelDto>>>
{
    public async Task<AppResponse<PagedResult<ShiftSalaryLevelDto>>> Handle(GetShiftSalaryLevelsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            Expression<Func<ShiftSalaryLevel, bool>> filter = e =>
                e.StoreId == request.StoreId &&
                (!request.ShiftTemplateId.HasValue || e.ShiftTemplateId == request.ShiftTemplateId.Value) &&
                (!request.IsActive.HasValue || e.IsActive == request.IsActive.Value);

            var totalCount = await repository.CountAsync(filter, cancellationToken);

            var items = await repository.GetAllAsync(
                filter: filter,
                orderBy: q => q.OrderBy(e => e.SortOrder).ThenByDescending(e => e.CreatedAt),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var result = new PagedResult<ShiftSalaryLevelDto>(
                items.Adapt<List<ShiftSalaryLevelDto>>(),
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<ShiftSalaryLevelDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<ShiftSalaryLevelDto>>.Error(ex.Message);
        }
    }
}

// Get ShiftSalaryLevel by Id Query
public record GetShiftSalaryLevelByIdQuery(Guid StoreId, Guid Id) : IQuery<AppResponse<ShiftSalaryLevelDto>>;

public class GetShiftSalaryLevelByIdHandler(
    IRepository<ShiftSalaryLevel> repository
) : IQueryHandler<GetShiftSalaryLevelByIdQuery, AppResponse<ShiftSalaryLevelDto>>
{
    public async Task<AppResponse<ShiftSalaryLevelDto>> Handle(GetShiftSalaryLevelByIdQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var entity = await repository.GetSingleAsync(
                e => e.Id == request.Id && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (entity == null)
            {
                return AppResponse<ShiftSalaryLevelDto>.Error("Shift salary level not found");
            }

            return AppResponse<ShiftSalaryLevelDto>.Success(entity.Adapt<ShiftSalaryLevelDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<ShiftSalaryLevelDto>.Error(ex.Message);
        }
    }
}
