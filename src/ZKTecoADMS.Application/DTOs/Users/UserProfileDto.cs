namespace ZKTecoADMS.Application.DTOs.Users;

public class UserProfileDto
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string UserName { get; set; } = string.Empty;
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public string? PhoneNumber { get; set; }
    public List<string> Roles { get; set; } = [];
    public Guid? ManagerId { get; set; }
    public string? ManagerName { get; set; }
    public DateTime Created { get; set; }
}
