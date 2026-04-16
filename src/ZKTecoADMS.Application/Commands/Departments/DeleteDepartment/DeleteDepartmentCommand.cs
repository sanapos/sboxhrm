namespace ZKTecoADMS.Application.Commands.Departments.DeleteDepartment;

public record DeleteDepartmentCommand(
    Guid StoreId,
    Guid Id) : ICommand<AppResponse<bool>>;
