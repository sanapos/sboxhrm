using ZKTecoADMS.Application.DTOs.Shifts;

namespace ZKTecoADMS.Application.Queries.Shifts.GetShiftsByManager;

public record GetShiftsByManagerQuery(Guid StoreId, Guid ManagerId, PaginationRequest PaginationRequest, List<Guid>? SubordinateUserIds = null) : IQuery<AppResponse<PagedResult<ShiftDto>>>;
