using ZKTecoADMS.Application.DTOs.Departments;

namespace ZKTecoADMS.Application.Queries.Departments.GetDepartmentById;

public record GetDepartmentByIdQuery(
    Guid StoreId,
    Guid Id) : IQuery<AppResponse<DepartmentDto>>;
