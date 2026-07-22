using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.DeviceUsers;
using ZKTecoADMS.Application.Helpers;
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
        var employeeId = (request.EmployeeId == null || request.EmployeeId == Guid.Empty)
            ? null
            : request.EmployeeId;

        // Same HR profile already linked on this device → reuse (do not create duplicate).
        if (employeeId.HasValue)
        {
            var linked = await employeeRepository.GetSingleAsync(
                u => u.DeviceId == request.DeviceId && u.EmployeeId == employeeId,
                cancellationToken: cancellationToken);
            if (linked != null)
            {
                return AppResponse<DeviceUserDto>.Fail(
                    $"Nhân viên đã có trên máy với PIN {linked.Pin}. Không tạo trùng.");
            }
        }

        var onDevice = (await employeeRepository.GetAllAsync(
            u => u.DeviceId == request.DeviceId,
            cancellationToken: cancellationToken)).ToList();
        var usedPins = onDevice.Select(u => u.Pin).ToList();

        string pin;
        try
        {
            // Empty or too-long / phone-like codes → allocate short unique PIN.
            pin = DeviceUserPinAllocator.Allocate(usedPins, request.Pin);
        }
        catch (InvalidOperationException ex)
        {
            return AppResponse<DeviceUserDto>.Fail(ex.Message);
        }

        var deviceUser = new DeviceUser
        {
            Pin = pin,
            Name = request.Name,
            CardNumber = request.CardNumber,
            Password = request.Password,
            Privilege = request.Privilege,
            DeviceId = request.DeviceId,
            EmployeeId = employeeId,
            IsActive = true,
            GroupId = 1,
            VerifyMode = 0
        };

        var validEmployee = await deviceService.IsUserValid(deviceUser);
        if (!validEmployee.IsSuccess)
        {
            // Race: preferred pin taken between read and insert → try sequential once more.
            var used = usedPins.Append(pin).ToHashSet(StringComparer.Ordinal);
            try
            {
                deviceUser.Pin = DeviceUserPinAllocator.AllocateSequential(used);
            }
            catch (InvalidOperationException ex)
            {
                return AppResponse<DeviceUserDto>.Fail(ex.Message);
            }

            validEmployee = await deviceService.IsUserValid(deviceUser);
            if (!validEmployee.IsSuccess)
                return AppResponse<DeviceUserDto>.Fail(validEmployee.Message);
        }

        var employeeEntity = await employeeRepository.AddAsync(deviceUser, cancellationToken);

        var commandStr = ClockCommandBuilder.BuildAddOrUpdateEmployeeCommand(employeeEntity);
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
