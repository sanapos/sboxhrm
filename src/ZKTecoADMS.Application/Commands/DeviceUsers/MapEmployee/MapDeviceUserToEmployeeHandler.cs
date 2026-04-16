using ZKTecoADMS.Application.DTOs.Employees;

namespace ZKTecoADMS.Application.Commands.DeviceUsers.MapEmployee;

public class MapDeviceUserToEmployeeCommandHandler(
    IRepository<DeviceUser> deviceUserRepository,
    IRepository<Employee> employeeRepository
    ) : ICommandHandler<MapDeviceUserToEmployeeCommand, AppResponse<EmployeeDto>>
{
    public async Task<AppResponse<EmployeeDto>> Handle(MapDeviceUserToEmployeeCommand request, CancellationToken cancellationToken)
    {
        var deviceUser = await deviceUserRepository.GetByIdAsync(request.deviceUserId);
        if (deviceUser == null)
        {
            return AppResponse<EmployeeDto>.Fail("Device user not found.");
        }

        var employee = await employeeRepository.GetByIdAsync(request.employeeId);
        if (employee == null)
        {
            return AppResponse<EmployeeDto>.Fail("Employee not found.");
        }

        deviceUser.EmployeeId = employee.Id;
        await deviceUserRepository.UpdateAsync(deviceUser, cancellationToken);

        return AppResponse<EmployeeDto>.Success(employee.Adapt<EmployeeDto>());
    }
}