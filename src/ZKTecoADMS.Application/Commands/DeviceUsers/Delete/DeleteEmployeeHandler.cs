using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.DeviceUsers.Delete;

public class DeleteDeviceUserHandler(
    IRepository<DeviceUser> deviceUserRepository,
    IRepository<DeviceCommand> deviceCmdRepository,
    IRepository<Attendance> attendanceRepository) : ICommandHandler<DeleteDeviceUserCommand, AppResponse<Guid>>
{
    public async Task<AppResponse<Guid>> Handle(DeleteDeviceUserCommand request, CancellationToken cancellationToken)
    {
        var deviceUser = await deviceUserRepository.GetByIdAsync(request.EmployeeId, cancellationToken: cancellationToken);

        if (deviceUser == null)
        {
            return AppResponse<Guid>.Fail("Không tìm thấy nhân sự chấm công");
        }

        var deviceUserId = deviceUser.Id;
        var pin = deviceUser.Pin;
        var deviceId = deviceUser.DeviceId;

        // Giữ lịch sử chấm công thô — chỉ gỡ liên kết DeviceUser, không xóa AttendanceLog.
        var linkedAttendances = await attendanceRepository.GetAllAsync(
            a => a.EmployeeId == deviceUserId,
            cancellationToken: cancellationToken);
        if (linkedAttendances.Count > 0)
        {
            foreach (var attendance in linkedAttendances)
                attendance.EmployeeId = null;
            await attendanceRepository.UpdateRangeAsync(linkedAttendances, cancellationToken);
        }

        if (request.SyncToDevice)
        {
            var cmd = new DeviceCommand
            {
                DeviceId = deviceId,
                Command = ClockCommandBuilder.BuildDeleteEmployeeCommand(pin),
                Status = CommandStatus.Created,
                CommandType = DeviceCommandTypes.DeleteDeviceUser,
                ObjectReferenceId = deviceUserId
            };

            await deviceCmdRepository.AddAsync(cmd, cancellationToken);
        }

        var deleted = await deviceUserRepository.DeleteAsync(deviceUser, cancellationToken);
        if (!deleted)
        {
            return AppResponse<Guid>.Fail("Không thể xóa nhân sự chấm công khỏi server");
        }

        return AppResponse<Guid>.Success(deviceUserId);
    }
}
