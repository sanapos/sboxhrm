using MediatR;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.Employees.DeleteEmployee;

public class DeleteEmployeeHandler(
    IRepository<Employee> employeeRepository,
    ISystemNotificationService notificationService) 
    : IRequestHandler<DeleteEmployeeCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteEmployeeCommand request, CancellationToken cancellationToken)
    {
        // Filter by StoreId for multi-tenant data isolation
        var employee = await employeeRepository.GetSingleAsync(
            e => e.Id == request.Id && e.StoreId == request.StoreId,
            cancellationToken: cancellationToken);
        
        if (employee == null)
        {
            return AppResponse<bool>.Error("Employee not found");
        }

        var employeeName = $"{employee.LastName} {employee.FirstName}";
        var employeeCode = employee.EmployeeCode;
        await employeeRepository.DeleteAsync(employee, cancellationToken);

        try
        {
            await notificationService.CreateAndSendAsync(
                targetUserId: null,
                type: NotificationType.Warning,
                title: "Xóa nhân viên",
                message: $"Nhân viên {employeeName} ({employeeCode}) đã bị xóa khỏi hệ thống",
                relatedEntityType: "Employee",
                categoryCode: "employee",
                storeId: request.StoreId);
        }
        catch { /* notification failure should not block main flow */ }

        return AppResponse<bool>.Success(true);
    }
}
