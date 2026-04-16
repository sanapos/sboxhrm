using MediatR;
using ZKTecoADMS.Application.DTOs.Employees;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Employees.GetEmployeeById;

public class GetEmployeeByIdHandler(IRepository<Employee> employeeRepository) 
    : IRequestHandler<GetEmployeeByIdQuery, AppResponse<EmployeeDto>>
{
    public async Task<AppResponse<EmployeeDto>> Handle(GetEmployeeByIdQuery request, CancellationToken cancellationToken)
    {
        // Filter by StoreId for multi-tenant data isolation
        var employee = await employeeRepository.GetSingleAsync(
            e => e.Id == request.Id && e.StoreId == request.StoreId,
            includeProperties: new[] { "DirectManagerEmployee" },
            cancellationToken: cancellationToken);
        
        if (employee == null)
        {
            return AppResponse<EmployeeDto>.Error("Employee not found");
        }

        var employeeDto = new EmployeeDto
        {
            Id = employee.Id,
            EmployeeCode = employee.EmployeeCode,
            FirstName = employee.FirstName,
            LastName = employee.LastName,
            Gender = employee.Gender,
            DateOfBirth = employee.DateOfBirth,
            PhotoUrl = employee.PhotoUrl,
            NationalIdNumber = employee.NationalIdNumber,
            NationalIdIssueDate = employee.NationalIdIssueDate,
            NationalIdIssuePlace = employee.NationalIdIssuePlace,
            PhoneNumber = employee.PhoneNumber,
            PersonalEmail = employee.PersonalEmail,
            CompanyEmail = employee.CompanyEmail,
            PermanentAddress = employee.PermanentAddress,
            TemporaryAddress = employee.TemporaryAddress,
            EmergencyContactName = employee.EmergencyContactName,
            EmergencyContactPhone = employee.EmergencyContactPhone,
            MaritalStatus = employee.MaritalStatus,
            Hometown = employee.Hometown,
            EducationLevel = employee.EducationLevel,
            BankName = employee.BankName,
            BankAccountName = employee.BankAccountName,
            BankAccountNumber = employee.BankAccountNumber,
            IdCardFrontUrl = employee.IdCardFrontUrl,
            IdCardBackUrl = employee.IdCardBackUrl,
            DepartmentId = employee.DepartmentId,
            Department = employee.Department,
            Position = employee.Position,
            Level = employee.Level,
            EmploymentType = employee.EmploymentType,
            JoinDate = employee.JoinDate,
            ProbationEndDate = employee.ProbationEndDate,
            WorkStatus = employee.WorkStatus,
            DirectManagerEmployeeId = employee.DirectManagerEmployeeId,
            DirectManagerName = employee.DirectManagerEmployee != null
                ? $"{employee.DirectManagerEmployee.LastName} {employee.DirectManagerEmployee.FirstName}"
                : null,
            ResignationDate = employee.ResignationDate,
            ResignationReason = employee.ResignationReason,
            ApplicationUserId = employee.ApplicationUserId
        };

        return AppResponse<EmployeeDto>.Success(employeeDto);
    }
}
