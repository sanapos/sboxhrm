using ZKTecoADMS.Application.DTOs.DeviceUsers;

namespace ZKTecoADMS.Application.Commands.DeviceUsers.Create;

public record CreateDeviceUserCommand(
    string? Pin, 
    string Name, 
    string? CardNumber, 
    string? Password, 
    int Privilege, 
    Guid DeviceId,
    Guid? EmployeeId = null,
    // Dùng đúng PIN yêu cầu (hội viên gym: PIN = số điện thoại 9 chữ số) — trùng thì báo lỗi, không tự đổi / cắt ngắn.
    bool ExactPin = false) : ICommand<AppResponse<DeviceUserDto>>;
