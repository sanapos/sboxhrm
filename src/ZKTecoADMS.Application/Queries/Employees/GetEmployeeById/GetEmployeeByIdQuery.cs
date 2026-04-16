using MediatR;
using ZKTecoADMS.Application.DTOs.Employees;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Employees.GetEmployeeById;

public class GetEmployeeByIdQuery : IRequest<AppResponse<EmployeeDto>>
{
    public Guid StoreId { get; set; }
    public Guid Id { get; set; }
}
