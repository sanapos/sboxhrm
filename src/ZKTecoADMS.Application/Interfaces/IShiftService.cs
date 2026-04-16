using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Interfaces;

public interface IShiftService
{
    Task<Shift?> GetShiftByIdAsync(Guid storeId, Guid id, CancellationToken cancellationToken = default);
    Task<Shift> ApproveShiftAsync(Guid storeId, Guid shiftId, Guid approvedByUserId, CancellationToken cancellationToken = default);
    Task<Shift> RejectShiftAsync(Guid storeId, Guid shiftId, Guid rejectedByUserId, string rejectionReason, CancellationToken cancellationToken = default);
    Task<Shift> UpdateShiftAsync(Guid storeId, Guid shiftId, Guid updatedByUserId, DateTime? checkInTime, DateTime? checkOutTime, CancellationToken cancellationToken = default);
    Task<(Shift? CurrentShift, Shift? NextShift)> GetTodayShiftAndNextShiftAsync(Guid employeeId, CancellationToken cancellationToken = default);   
    Task<Shift?> GetShiftByDateAsync(Guid employeeUserId, DateTime date, CancellationToken cancellationToken = default);
}
