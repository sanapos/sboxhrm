using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.ShiftTemplates.DeleteShiftTemplate;

public class DeleteShiftTemplateHandler(
    IRepository<ShiftTemplate> repository,
    IRepository<WorkSchedule> schedules,
    IRepository<ScheduleRegistration> registrations)
    : ICommandHandler<DeleteShiftTemplateCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteShiftTemplateCommand request, CancellationToken cancellationToken)
    {
        var template = await repository.GetSingleAsync(
            t => t.Id == request.Id,
            cancellationToken: cancellationToken);

        if (template == null)
        {
            return AppResponse<bool>.Error("Không tìm thấy ca");
        }

        // Lịch và đăng ký chỉ giữ mã ca (nullable). Gỡ liên kết rồi mới xóa,
        // nếu không SQL chặn vì khóa ngoại Restrict.
        var linkedSchedules = await schedules.GetAllAsync(
            filter: s => s.ShiftId == template.Id,
            cancellationToken: cancellationToken);
        if (linkedSchedules.Count > 0)
        {
            foreach (var row in linkedSchedules)
                row.ShiftId = null;
            await schedules.UpdateRangeAsync(linkedSchedules, cancellationToken);
        }

        var linkedRegs = await registrations.GetAllAsync(
            filter: r => r.ShiftId == template.Id,
            cancellationToken: cancellationToken);
        if (linkedRegs.Count > 0)
        {
            foreach (var row in linkedRegs)
                row.ShiftId = null;
            await registrations.UpdateRangeAsync(linkedRegs, cancellationToken);
        }

        try
        {
            await repository.DeleteAsync(template, cancellationToken);
        }
        catch (DbUpdateException)
        {
            return AppResponse<bool>.Error(
                "Không xóa được ca vì còn dữ liệu đang dùng ca này. Tắt ca hoặc gỡ lịch rồi thử lại.");
        }

        return AppResponse<bool>.Success(true);
    }
}
