using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>Gỡ lịch do phiếu đăng ký đã duyệt ghi vào (khi xóa phiếu / hoàn duyệt).</summary>
internal static class RegistrationScheduleCleanup
{
    public static async Task RemoveAppliedScheduleAsync(
        ScheduleRegistration registration,
        Guid storeId,
        IRepository<WorkSchedule> workScheduleRepository,
        CancellationToken cancellationToken)
    {
        if (registration.AppliedWorkScheduleId is Guid appliedId)
        {
            // Phiếu chỉ cập nhật lịch quản lý xếp sẵn → giữ nguyên lịch đó.
            if (!registration.AppliedCreatedNewSchedule)
                return;
            var created = await workScheduleRepository.GetSingleAsync(
                ws => ws.Id == appliedId && ws.StoreId == storeId,
                cancellationToken: cancellationToken);
            if (created != null)
                await workScheduleRepository.DeleteAsync(created, cancellationToken);
            return;
        }

        // Phiếu duyệt trước khi có AppliedWorkScheduleId: giữ cách cũ (gỡ lịch cùng ngày, cùng ca).
        var workSchedules = await workScheduleRepository.GetAllAsync(
            ws => ws.EmployeeUserId == registration.EmployeeUserId
                  && ws.Date.Date == registration.Date.Date
                  && ws.ShiftId == registration.ShiftId
                  && ws.StoreId == storeId,
            cancellationToken: cancellationToken);
        foreach (var ws in workSchedules)
            await workScheduleRepository.DeleteAsync(ws, cancellationToken);
    }
}
