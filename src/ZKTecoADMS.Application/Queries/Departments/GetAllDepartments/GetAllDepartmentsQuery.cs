using ZKTecoADMS.Application.DTOs.Departments;

namespace ZKTecoADMS.Application.Queries.Departments.GetAllDepartments;

public record GetAllDepartmentsQuery(
    Guid StoreId,
    PaginationRequest PaginationRequest,
    string? SearchTerm = null,
    bool? IsActive = null) : IQuery<AppResponse<PagedResult<DepartmentDto>>>;
