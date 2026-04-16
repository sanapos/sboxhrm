using ZKTecoADMS.Application.DTOs.Employees;

namespace ZKTecoADMS.Application.Commands.DeviceUsers.MapEmployee;

public record MapDeviceUserToEmployeeCommand(
    Guid deviceUserId,
    Guid employeeId
    ) : ICommand<AppResponse<EmployeeDto>>;
