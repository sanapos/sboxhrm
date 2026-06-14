using MediatR;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Services;
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

        NormalizeEmployeeName(employee);

        if (!string.IsNullOrWhiteSpace(request.Department))
        {
            employee.Department = request.Department.Trim();
            var dept = await DepartmentImportHelper.ResolveOrCreateAsync(
                departmentRepository, request.StoreId, request.Department, cancellationToken);
            if (dept != null)
            {
                employee.DepartmentId = dept.Id;
                employee.Department = dept.Name;
            }
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

    static void NormalizeEmployeeName(Employee employee)
    {
        employee.LastName = employee.LastName?.Trim() ?? string.Empty;
        employee.FirstName = employee.FirstName?.Trim() ?? string.Empty;

        if (employee.FirstName == ".") employee.FirstName = string.Empty;
        if (employee.LastName == ".") employee.LastName = string.Empty;

        if (string.IsNullOrWhiteSpace(employee.LastName) &&
            !string.IsNullOrWhiteSpace(employee.FirstName))
        {
            employee.LastName = employee.FirstName;
            employee.FirstName = string.Empty;
        }
        else if (string.IsNullOrWhiteSpace(employee.FirstName) &&
                 !string.IsNullOrWhiteSpace(employee.LastName))
        {
            employee.FirstName = string.Empty;
        }
    }
}
