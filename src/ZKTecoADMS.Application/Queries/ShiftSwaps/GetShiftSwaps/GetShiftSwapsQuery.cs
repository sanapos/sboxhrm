using ZKTecoADMS.Application.DTOs.ShiftSwaps;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.ShiftSwaps.GetShiftSwaps;

public record GetShiftSwapsQuery(
    Guid StoreId,
    Guid UserId,
    bool IsManager,
    PaginationRequest PaginationRequest,
    ShiftSwapStatus? Status = null) : IQuery<AppResponse<PagedResult<ShiftSwapRequestDto>>>;
