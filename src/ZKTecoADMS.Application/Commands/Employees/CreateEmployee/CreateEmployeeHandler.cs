using MediatR;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Employees.CreateEmployee;

public class CreateEmployeeHandler(
    IRepository<Employee> employeeRepository,
    IRepository<Department> departmentRepository,
    ISystemNotificationService notificationService) : IRequestHandler<CreateEmployeeCommand, AppResponse<Guid>>
{
    public async Task<AppResponse<Guid>> Handle(CreateEmployeeCommand request, CancellationToken cancellationToken)
    {
        // Auto-generate CompanyEmail if not provided
        if (string.IsNullOrWhiteSpace(request.CompanyEmail))
        {
            request.CompanyEmail = $"{request.EmployeeCode}@company.com";
        }

        var employeeCount = await employeeRepository.CountAsync(
            e => e.StoreId == request.StoreId && e.ManagerId == request.ManagerId,
            cancellationToken: cancellationToken
        );

        if(employeeCount >= 30)
        {
            return AppResponse<Guid>.Error("Manager has reached the maximum number of employees (30). Cannot add more employees.");
        }

        // Check if employee code already exists within the store
        var existingEmployee = await employeeRepository.GetSingleAsync(
            e => e.StoreId == request.StoreId && (e.EmployeeCode == request.EmployeeCode || e.CompanyEmail == request.CompanyEmail),
            cancellationToken: cancellationToken
        );

        if(existingEmployee == null)
        {
            var employee = request.Adapt<Employee>();
            employee.StoreId = request.StoreId;

            // Auto-resolve DepartmentId from Department name
            if (!string.IsNullOrWhiteSpace(request.Department))
            {
                var dept = await departmentRepository.GetSingleAsync(
                    d => d.StoreId == request.StoreId && d.Name == request.Department,
                    cancellationToken: cancellationToken);
                if (dept != null) employee.DepartmentId = dept.Id;
            }

            await employeeRepository.AddAsync(employee, cancellationToken);

            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Info,
                    title: "Nhân viên mới",
                    message: $"Nhân viên mới: {request.LastName} {request.FirstName} ({request.EmployeeCode})",
                    relatedEntityId: employee.Id,
                    relatedEntityType: "Employee",
                    categoryCode: "employee",
                    storeId: request.StoreId);
            }
            catch { /* notification failure should not block main flow */ }

            return AppResponse<Guid>.Success(employee.Id);
        }

        if (existingEmployee.EmployeeCode == request.EmployeeCode)
        {
            return AppResponse<Guid>.Error($"Employee with code {request.EmployeeCode} already exists");
        }

        return AppResponse<Guid>.Error($"Employee with company email {request.CompanyEmail} already exists");
    }
}
