using ZKTecoADMS.Application.DTOs.Departments;

namespace ZKTecoADMS.Application.Queries.Departments.GetDepartmentTree;

public record GetDepartmentTreeQuery(
    Guid StoreId,
    bool IncludeInactive = false) : IQuery<AppResponse<List<DepartmentTreeNodeDto>>>;
