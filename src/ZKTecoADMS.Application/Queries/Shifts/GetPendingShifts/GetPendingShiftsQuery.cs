using ZKTecoADMS.Application.DTOs.Shifts;

namespace ZKTecoADMS.Application.Queries.Shifts.GetPendingShifts;

public record GetPendingShiftsQuery(Guid StoreId, Guid? ManagerId, PaginationRequest PaginationRequest, List<Guid>? SubordinateUserIds = null) : IQuery<AppResponse<PagedResult<ShiftDto>>>;
