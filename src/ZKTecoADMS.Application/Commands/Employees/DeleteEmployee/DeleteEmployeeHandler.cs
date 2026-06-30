using MediatR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.Employees.DeleteEmployee;

public class DeleteEmployeeHandler(
    IRepository<Employee> employeeRepository,
    IEmployeeDeleteGuard deleteGuard,
    ISystemNotificationService notificationService)
    : IRequestHandler<DeleteEmployeeCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteEmployeeCommand request, CancellationToken cancellationToken)
    {
        var employee = await employeeRepository.GetSingleAsync(
            e => e.Id == request.Id && e.StoreId == request.StoreId,
            cancellationToken: cancellationToken);

        if (employee == null)
        {
            return AppResponse<bool>.Error("Không tìm thấy nhân viên");
        }

        var evaluation = await deleteGuard.EvaluateAsync(employee.Id, cancellationToken);
        if (!evaluation.CanDelete)
        {
            return AppResponse<bool>.Error(
                evaluation.BlockedReason ?? "Không thể xóa nhân viên vì còn dữ liệu liên quan.");
        }

        var employeeName = $"{employee.LastName} {employee.FirstName}";
        var employeeCode = employee.EmployeeCode;

        try
        {
            await employeeRepository.DeleteAsync(employee, cancellationToken);
        }
        catch (DbUpdateException)
        {
            return AppResponse<bool>.Error(
                "Không thể xóa nhân viên vì còn dữ liệu liên quan trong hệ thống. "
                + "Nên chuyển trạng thái sang \"Đã nghỉ việc\" thay vì xóa.");
        }

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
