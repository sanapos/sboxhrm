using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.DeviceUsers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.DeviceUsers.Create;

public class CreateDeviceUserHandler(
    IDeviceService deviceService, 
    IRepository<DeviceUser> employeeRepository,
    IRepository<DeviceCommand> deviceCmdRepository) : ICommandHandler<CreateDeviceUserCommand, AppResponse<DeviceUserDto>>
{
    public async Task<AppResponse<DeviceUserDto>> Handle(CreateDeviceUserCommand request, CancellationToken cancellationToken)
    {
        // Log request data
        Console.WriteLine($"[CreateDeviceUser Handler] Request: PIN={request.Pin}, Name={request.Name}, Privilege={request.Privilege}");
        
        var deviceUser = new DeviceUser
        {
            Name = request.Name,
            CardNumber = request.CardNumber,
            Password = request.Password,
            Privilege = request.Privilege,
            DeviceId = request.DeviceId,
            EmployeeId = (request.EmployeeId == null || request.EmployeeId == Guid.Empty) ? null : request.EmployeeId,
            IsActive = true,
            GroupId = 1,
            VerifyMode = 0
        };
        
        // PIN là bắt buộc trong protocol ZKTeco ADMS (DATA UPDATE USERINFO PIN=xxx)
        // Nếu user không nhập PIN, hệ thống tự sinh PIN tạm thời
        // Sau khi gửi lệnh, cần sync lại từ máy để lấy PIN chính thức (nếu máy có thay đổi)
        if (string.IsNullOrWhiteSpace(request.Pin))
        {
            // Sinh PIN tự động: lấy số giây hiện tại, đảm bảo tối đa 8 ký tự
            var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds() % 100000000;
            deviceUser.Pin = timestamp.ToString();
            Console.WriteLine($"[CreateDeviceUser Handler] Auto-generated PIN (system): {deviceUser.Pin}");
        }
        else
        {
            deviceUser.Pin = request.Pin;
        }
        
        // Log after mapping
        Console.WriteLine($"[CreateDeviceUser Handler] After Mapping: PIN={deviceUser.Pin}, Name={deviceUser.Name}, Privilege={deviceUser.Privilege}");
        
        var validEmployee = await deviceService.IsUserValid(deviceUser);
        if (!validEmployee.IsSuccess)
        {
            return AppResponse<DeviceUserDto>.Fail(validEmployee.Message);
        }
        
        var employeeEntity = await employeeRepository.AddAsync(deviceUser, cancellationToken);
        
        // Log saved entity
        Console.WriteLine($"[CreateDeviceUser Handler] Saved Entity: ID={employeeEntity.Id}, PIN={employeeEntity.Pin}, Name={employeeEntity.Name}");

        var commandStr = ClockCommandBuilder.BuildAddOrUpdateEmployeeCommand(employeeEntity);
        Console.WriteLine($"[CreateDeviceUser] Command to device: {commandStr}");
        
        var cmd = new DeviceCommand
        {
            DeviceId = employeeEntity.DeviceId,
            Command = commandStr,
            Priority = 10,
            CommandType = DeviceCommandTypes.AddDeviceUser,
            ObjectReferenceId = employeeEntity.Id
        };
        await deviceCmdRepository.AddAsync(cmd, cancellationToken);

        return AppResponse<DeviceUserDto>.Success(employeeEntity.Adapt<DeviceUserDto>());

    }
}