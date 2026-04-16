using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.ShiftSwaps;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.ShiftSwaps.GetShiftSwaps;

public class GetShiftSwapsHandler(
    IRepository<ShiftSwapRequest> shiftSwapRepository
) : IQueryHandler<GetShiftSwapsQuery, AppResponse<PagedResult<ShiftSwapRequestDto>>>
{
    public async Task<AppResponse<PagedResult<ShiftSwapRequestDto>>> Handle(
        GetShiftSwapsQuery request,
        CancellationToken cancellationToken)
    {
        try
        {
            var swapRequests = await shiftSwapRepository.GetAllWithIncludeAsync(
                filter: r => r.StoreId == request.StoreId
                    && r.IsActive
                    && (!request.Status.HasValue || r.Status == request.Status.Value)
                    && (request.IsManager || r.RequesterUserId == request.UserId || r.TargetUserId == request.UserId),
                orderBy: q => q.OrderByDescending(r => r.CreatedAt),
                includes: q => q
                    .Include(r => r.RequesterUser)
                    .Include(r => r.TargetUser)
                    .Include(r => r.RequesterShift)
                    .Include(r => r.TargetShift)
                    .Include(r => r.ApprovedByManager)!,
                skip: (request.PaginationRequest.PageNumber - 1) * request.PaginationRequest.PageSize,
                take: request.PaginationRequest.PageSize,
                cancellationToken: cancellationToken);

            var totalCount = await shiftSwapRepository.CountAsync(
                filter: r => r.StoreId == request.StoreId
                    && r.IsActive
                    && (!request.Status.HasValue || r.Status == request.Status.Value)
                    && (request.IsManager || r.RequesterUserId == request.UserId || r.TargetUserId == request.UserId),
                cancellationToken: cancellationToken);

            var dtos = swapRequests.Select(r => new ShiftSwapRequestDto
            {
                Id = r.Id,
                StoreId = r.StoreId,
                RequesterUserId = r.RequesterUserId,
                RequesterName = r.RequesterUser != null 
                    ? $"{r.RequesterUser.LastName} {r.RequesterUser.FirstName}" 
                    : "N/A",
                RequesterDate = r.RequesterDate,
                RequesterShiftId = r.RequesterShiftId,
                RequesterShiftName = FormatShiftName(r.RequesterShift),
                TargetUserId = r.TargetUserId,
                TargetName = r.TargetUser != null 
                    ? $"{r.TargetUser.LastName} {r.TargetUser.FirstName}" 
                    : "N/A",
                TargetDate = r.TargetDate,
                TargetShiftId = r.TargetShiftId,
                TargetShiftName = FormatShiftName(r.TargetShift),
                Reason = r.Reason,
                Status = r.Status,
                StatusText = GetStatusText(r.Status),
                TargetAccepted = r.TargetAccepted,
                TargetResponseDate = r.TargetResponseDate,
                ApprovedByManagerId = r.ApprovedByManagerId,
                ApprovedByManagerName = r.ApprovedByManager != null 
                    ? $"{r.ApprovedByManager.LastName} {r.ApprovedByManager.FirstName}" 
                    : null,
                ManagerApprovalDate = r.ManagerApprovalDate,
                RejectionReason = r.RejectionReason,
                Note = r.Note,
                CreatedAt = r.CreatedAt,
                UpdatedAt = r.UpdatedAt
            }).ToList();

            var pagedResult = new PagedResult<ShiftSwapRequestDto>(
                dtos,
                totalCount,
                request.PaginationRequest.PageNumber,
                request.PaginationRequest.PageSize);

            return AppResponse<PagedResult<ShiftSwapRequestDto>>.Success(pagedResult);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<ShiftSwapRequestDto>>.Error(
                $"Lỗi khi lấy danh sách yêu cầu đổi ca: {ex.Message}");
        }
    }

    private static string GetStatusText(ShiftSwapStatus status)
    {
        return status switch
        {
            ShiftSwapStatus.Pending => "Chờ xác nhận",
            ShiftSwapStatus.TargetAccepted => "Chờ quản lý duyệt",
            ShiftSwapStatus.Approved => "Đã duyệt",
            ShiftSwapStatus.RejectedByTarget => "Đồng nghiệp từ chối",
            ShiftSwapStatus.RejectedByManager => "Quản lý từ chối",
            ShiftSwapStatus.Cancelled => "Đã hủy",
            _ => "Không xác định"
        };
    }

    private static string FormatShiftName(Shift? shift)
    {
        if (shift == null)
            return "N/A";
        if (shift.Description != null)
            return shift.Description;
        return $"{shift.StartTime:HH:mm} - {shift.EndTime:HH:mm}";
    }
}
