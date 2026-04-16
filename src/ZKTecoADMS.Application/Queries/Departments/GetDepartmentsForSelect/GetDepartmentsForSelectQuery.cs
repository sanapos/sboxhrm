using ZKTecoADMS.Application.DTOs.Departments;

namespace ZKTecoADMS.Application.Queries.Departments.GetDepartmentsForSelect;

public record GetDepartmentsForSelectQuery(
    Guid StoreId) : IQuery<AppResponse<List<DepartmentSelectDto>>>;
