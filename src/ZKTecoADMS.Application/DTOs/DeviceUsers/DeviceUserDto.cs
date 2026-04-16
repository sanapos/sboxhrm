using ZKTecoADMS.Application.DTOs.Employees;

namespace ZKTecoADMS.Application.DTOs.DeviceUsers;

public class DeviceUserDto
{
    public Guid Id { get; set; }
    public string Pin { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? CardNumber { get; set; }
    public string? Password { get; set; }
    public int Privilege { get; set; }
    public bool IsActive { get; set; }
    public Guid DeviceId { get; set; }
    public string? DeviceName { get; set; }
    public int FingerprintCount { get; set; }

    public EmployeeDto? Employee { get;set; }
}
