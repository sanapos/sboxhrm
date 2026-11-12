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
        // Phiếu xin bỏ ca: lần duyệt đã gỡ ca → xếp lại ca đó (nếu ngày ấy chưa có lại ca này / chưa là ngày nghỉ).
        if (!registration.IsDayOff && registration.ShiftId == null && registration.ReplaceShiftId is Guid droppedShiftId)
        {
            if (registration.AppliedWorkScheduleId == null) return;
            var dayStart = registration.Date.Date;
            var dayEnd = dayStart.AddDays(1);
            var sameDay = await workScheduleRepository.GetAllAsync(
                ws => ws.EmployeeUserId == registration.EmployeeUserId && ws.StoreId == storeId
                      && ws.Date >= dayStart && ws.Date < dayEnd,
                cancellationToken: cancellationToken);
            if (sameDay.Any(ws => ws.IsDayOff || ws.ShiftId == droppedShiftId)) return;
            await workScheduleRepository.AddAsync(new WorkSchedule
            {
                StoreId = storeId,
                EmployeeUserId = registration.EmployeeUserId,
                ShiftId = droppedShiftId,
                Date = dayStart,
                IsDayOff = false,
            }, cancellationToken);
            return;
        }

        if (registration.AppliedWorkScheduleId is Guid appliedId)
        {
            // Phiếu đổi ca: dòng lịch ca cũ đã chuyển sang ca mới → trả lại ca cũ.
            if (!registration.AppliedCreatedNewSchedule && registration.ReplaceShiftId is Guid oldShiftId)
            {
                var row = await workScheduleRepository.GetSingleAsync(
                    ws => ws.Id == appliedId && ws.StoreId == storeId,
                    cancellationToken: cancellationToken);
                if (row != null && !row.IsDayOff && row.ShiftId == registration.ShiftId)
                {
                    row.ShiftId = oldShiftId;
                    await workScheduleRepository.UpdateAsync(row, cancellationToken);
                }
                return;
            }
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
