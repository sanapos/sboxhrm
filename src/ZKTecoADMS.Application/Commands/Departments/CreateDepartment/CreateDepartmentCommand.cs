using ZKTecoADMS.Application.DTOs.Departments;

namespace ZKTecoADMS.Application.Commands.Departments.CreateDepartment;

public record CreateDepartmentCommand(
    Guid StoreId,
    string Code,
    string Name,
    string? Description,
    Guid? ParentDepartmentId,
    Guid? ManagerId,
    int SortOrder,
    List<string>? Positions) : ICommand<AppResponse<DepartmentDto>>;
