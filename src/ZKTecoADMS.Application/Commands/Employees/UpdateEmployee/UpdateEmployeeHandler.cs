using MediatR;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.Employees.UpdateEmployee;

public class UpdateEmployeeHandler(
    IRepository<Employee> employeeRepository,
    IRepository<Department> departmentRepository,
    ISystemNotificationService notificationService) : IRequestHandler<UpdateEmployeeCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(UpdateEmployeeCommand request, CancellationToken cancellationToken)
    {
        // Filter by StoreId for multi-tenant data isolation
        var employee = await employeeRepository.GetSingleAsync(
            e => e.Id == request.Id && e.StoreId == request.StoreId,
            cancellationToken: cancellationToken);
        
        if (employee == null)
        {
            return AppResponse<bool>.Error("Employee not found");
        }

        // Check if employee code is being changed and if it already exists within the store
        if (employee.EmployeeCode != request.EmployeeCode)
        {
            var existingEmployee = await employeeRepository.GetFirstOrDefaultAsync(
                e => e.EmployeeCode,
                e => e.StoreId == request.StoreId && e.EmployeeCode == request.EmployeeCode && e.Id != request.Id,
                null,
                cancellationToken);

            if (existingEmployee != null)
            {
                return AppResponse<bool>.Error($"Employee with code {request.EmployeeCode} already exists");
            }
        }

        // Track key changes for notification
        var oldDepartment = employee.Department;
        var oldPosition = employee.Position;
        var oldWorkStatus = employee.WorkStatus;

        employee.EmployeeCode = request.EmployeeCode;
        employee.FirstName = request.FirstName?.Trim() ?? string.Empty;
        employee.LastName = request.LastName?.Trim() ?? string.Empty;
        if (employee.FirstName == ".") employee.FirstName = string.Empty;
        if (employee.LastName == ".") employee.LastName = string.Empty;
        if (string.IsNullOrWhiteSpace(employee.LastName) &&
            !string.IsNullOrWhiteSpace(employee.FirstName))
        {
            employee.LastName = employee.FirstName;
            employee.FirstName = string.Empty;
        }
        employee.Gender = request.Gender;
        employee.DateOfBirth = request.DateOfBirth;
        employee.PhotoUrl = request.PhotoUrl;
        employee.NationalIdNumber = request.NationalIdNumber;
        employee.NationalIdIssueDate = request.NationalIdIssueDate;
        employee.NationalIdIssuePlace = request.NationalIdIssuePlace;
        employee.PhoneNumber = request.PhoneNumber;
        employee.PersonalEmail = request.PersonalEmail;
        employee.CompanyEmail = request.CompanyEmail;
        employee.PermanentAddress = request.PermanentAddress;
        employee.TemporaryAddress = request.TemporaryAddress;
        employee.EmergencyContactName = request.EmergencyContactName;
        employee.EmergencyContactPhone = request.EmergencyContactPhone;
        employee.MaritalStatus = request.MaritalStatus;
        employee.Hometown = request.Hometown;
        employee.EducationLevel = request.EducationLevel;
        employee.BankName = request.BankName;
        employee.BankAccountName = request.BankAccountName;
        employee.BankAccountNumber = request.BankAccountNumber;
        employee.IdCardFrontUrl = request.IdCardFrontUrl;
        employee.IdCardBackUrl = request.IdCardBackUrl;
        employee.Department = request.Department?.Trim();

        if (!string.IsNullOrWhiteSpace(request.Department))
        {
            var dept = await DepartmentImportHelper.ResolveOrCreateAsync(
                departmentRepository, request.StoreId, request.Department, cancellationToken);
            employee.DepartmentId = dept?.Id;
            if (dept != null) employee.Department = dept.Name;
        }
        else
        {
            employee.DepartmentId = null;
        }

        employee.Position = request.Position;
        employee.Level = request.Level;
        employee.JoinDate = request.JoinDate;
        employee.ProbationEndDate = request.ProbationEndDate;
        employee.ContractEndDate = request.ContractEndDate;
        employee.DirectManagerEmployeeId = request.DirectManagerEmployeeId;
        // Normalize work status (reject unknown values from legacy clients)
        if (!Enum.IsDefined(typeof(EmployeeWorkStatus), request.WorkStatus))
        {
            request.WorkStatus = employee.WorkStatus;
        }

        employee.WorkStatus = request.WorkStatus;
        employee.ResignationDate = request.ResignationDate;
        employee.ResignationReason = request.ResignationReason;
        employee.ApplicationUserId = request.ApplicationUserId;
        if (request.ManagerId.HasValue)
            employee.ManagerId = request.ManagerId.Value;
        employee.BranchId = request.BranchId;
        employee.UpdatedAt = DateTime.UtcNow;

        await employeeRepository.UpdateAsync(employee, cancellationToken);

        // Notify employee about profile changes
        try
        {
            if (employee.ApplicationUserId.HasValue)
            {
                var changes = new List<string>();
                if (oldDepartment != employee.Department) changes.Add("phòng ban");
                if (oldPosition != employee.Position) changes.Add("chức vụ");
                if (oldWorkStatus != employee.WorkStatus) changes.Add("trạng thái");

                var message = changes.Count > 0
                    ? $"Thông tin nhân sự đã thay đổi: {string.Join(", ", changes)}"
                    : "Thông tin nhân sự của bạn đã được cập nhật";

                await notificationService.CreateAndSendAsync(
                    employee.ApplicationUserId.Value, NotificationType.Info,
                    "Cập nhật hồ sơ nhân sự",
                    message,
                    relatedEntityId: employee.Id, relatedEntityType: "Employee",
                    categoryCode: "hr", storeId: request.StoreId);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return AppResponse<bool>.Success(true);
    }
}
