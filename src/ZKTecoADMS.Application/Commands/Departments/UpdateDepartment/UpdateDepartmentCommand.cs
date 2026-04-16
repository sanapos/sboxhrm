using ZKTecoADMS.Application.DTOs.Departments;

namespace ZKTecoADMS.Application.Commands.Departments.UpdateDepartment;

public record UpdateDepartmentCommand(
    Guid StoreId,
    Guid Id,
    string Code,
    string Name,
    string? Description,
    Guid? ParentDepartmentId,
    Guid? ManagerId,
    int SortOrder,
    bool IsActive,
    List<string>? Positions) : ICommand<AppResponse<DepartmentDto>>;
