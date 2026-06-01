using MediatR;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Employees.CreateEmployee;

public class CreateEmployeeHandler(
    IRepository<Employee> employeeRepository,
    IRepository<Department> departmentRepository,
    IRepository<OrgPosition> orgPositionRepository,
    IRepository<OrgAssignment> orgAssignmentRepository,
    ISystemNotificationService notificationService) : IRequestHandler<CreateEmployeeCommand, AppResponse<Guid>>
{
    public async Task<AppResponse<Guid>> Handle(CreateEmployeeCommand request, CancellationToken cancellationToken)
    {
        // Auto-generate CompanyEmail if not provided
        if (string.IsNullOrWhiteSpace(request.CompanyEmail))
        {
            request.CompanyEmail = $"{request.EmployeeCode}@company.com";
        }

        if (string.IsNullOrWhiteSpace(request.EmployeeCode))
        {
            return AppResponse<Guid>.Error("Mã nhân viên không được để trống.");
        }

        if (string.IsNullOrWhiteSpace(request.FirstName) && string.IsNullOrWhiteSpace(request.LastName))
        {
            return AppResponse<Guid>.Error("Họ tên nhân viên không được để trống.");
        }

        // Normalize work status (Flutter may send 2/3 for legacy UI labels)
        if (!Enum.IsDefined(typeof(EmployeeWorkStatus), request.WorkStatus))
        {
            request.WorkStatus = EmployeeWorkStatus.Active;
        }

        var dupCode = await employeeRepository.GetSingleAsync(
            e => e.StoreId == request.StoreId && e.EmployeeCode == request.EmployeeCode,
            cancellationToken: cancellationToken);
        if (dupCode != null)
        {
            return AppResponse<Guid>.Error(
                $"Mã nhân viên \"{request.EmployeeCode}\" đã tồn tại trong cửa hàng.");
        }

        var dupEmail = await employeeRepository.GetSingleAsync(
            e => e.StoreId == request.StoreId && e.CompanyEmail == request.CompanyEmail,
            cancellationToken: cancellationToken);
        if (dupEmail != null)
        {
            return AppResponse<Guid>.Error(
                $"Email công ty \"{request.CompanyEmail}\" đã được dùng cho nhân viên {dupEmail.EmployeeCode}.");
        }

        var employee = request.Adapt<Employee>();
        employee.StoreId = request.StoreId;
        employee.ManagerId = request.ManagerId;

        if (string.IsNullOrWhiteSpace(employee.LastName))
        {
            employee.LastName = employee.FirstName;
            employee.FirstName = ".";
        }

        // Auto-resolve DepartmentId from Department name
        if (!string.IsNullOrWhiteSpace(request.Department))
        {
            var dept = await departmentRepository.GetSingleAsync(
                d => d.StoreId == request.StoreId && d.Name == request.Department,
                cancellationToken: cancellationToken);
            if (dept != null) employee.DepartmentId = dept.Id;
        }

        if (!employee.JoinDate.HasValue)
            employee.JoinDate = DateTime.UtcNow.Date;

        await employeeRepository.AddAsync(employee, cancellationToken);

        if (employee.DepartmentId.HasValue && !string.IsNullOrWhiteSpace(request.Position))
        {
            var orgPosition = await orgPositionRepository.GetSingleAsync(
                p => p.StoreId == request.StoreId && p.Name == request.Position,
                cancellationToken: cancellationToken);
            if (orgPosition != null)
            {
                var assignment = new OrgAssignment
                {
                    EmployeeId = employee.Id,
                    DepartmentId = employee.DepartmentId.Value,
                    PositionId = orgPosition.Id,
                    IsPrimary = true,
                    StartDate = employee.JoinDate,
                    StoreId = request.StoreId,
                    IsActive = true
                };
                await orgAssignmentRepository.AddAsync(assignment, cancellationToken);
            }
        }

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
}
