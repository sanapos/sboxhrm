using MediatR;
using ZKTecoADMS.Application.DTOs.Employees;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Employees.GetEmployees;

public class GetEmployeesQuery : IRequest<AppResponse<PagedResult<EmployeeDto>>>
{
    public Guid StoreId { get; set; }
    public PaginationRequest PaginationRequest {get;set;}
    
    public string? SearchTerm { get; set; }
    public string? EmploymentType { get; set; }
    public string? WorkStatus { get; set; }

    public Guid ManagerId { get; set; }

    /// <summary>
    /// Danh sách EmployeeId thuộc phạm vi quản lý (phòng ban + trực tiếp).
    /// Nếu null, dùng ManagerId truyền thống.
    /// </summary>
    public List<Guid>? SubordinateEmployeeIds { get; set; }
}
