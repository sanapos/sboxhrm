using MediatR;
using ZKTecoADMS.Application.DTOs.Employees;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Application.Queries.Employees.GetEmployees;

public class GetEmployeesHandler(
    IRepositoryPagedQuery<Employee> employeeRepository
    ) 
    : IRequestHandler<GetEmployeesQuery, AppResponse<PagedResult<EmployeeDto>>>
{
    public async Task<AppResponse<PagedResult<EmployeeDto>>> Handle(GetEmployeesQuery request, CancellationToken cancellationToken)
    {
        var subordinateIds = request.SubordinateEmployeeIds;

        var pagedResult = await employeeRepository.GetPagedResultWithProjectionAsync(
            request.PaginationRequest,
            filter: e => e.StoreId == request.StoreId &&
                    (subordinateIds == null || subordinateIds.Contains(e.Id)) && 
                    (string.IsNullOrEmpty(request.SearchTerm) || 
                    e.EmployeeCode.Contains(request.SearchTerm) ||
                    e.FirstName.Contains(request.SearchTerm) ||
                    e.LastName.Contains(request.SearchTerm) ||
                    (e.PersonalEmail != null && e.PersonalEmail.Contains(request.SearchTerm)) ||
                    (e.CompanyEmail != null && e.CompanyEmail.Contains(request.SearchTerm))) && 
                    (string.IsNullOrEmpty(request.EmploymentType) || (int)e.EmploymentType == int.Parse(request.EmploymentType)) &&
                    (string.IsNullOrEmpty(request.WorkStatus) || (int)e.WorkStatus == int.Parse(request.WorkStatus)),
            projection: e => new EmployeeDto
            {
                Id = e.Id,
                EmployeeCode = e.EmployeeCode,
                FirstName = e.FirstName,
                LastName = e.LastName,
                Gender = e.Gender,
                DateOfBirth = e.DateOfBirth,
                PhotoUrl = e.PhotoUrl,
                NationalIdNumber = e.NationalIdNumber,
                NationalIdIssueDate = e.NationalIdIssueDate,
                NationalIdIssuePlace = e.NationalIdIssuePlace,
                PhoneNumber = e.PhoneNumber,
                PersonalEmail = e.PersonalEmail,
                CompanyEmail = e.CompanyEmail,
                PermanentAddress = e.PermanentAddress,
                TemporaryAddress = e.TemporaryAddress,
                EmergencyContactName = e.EmergencyContactName,
                EmergencyContactPhone = e.EmergencyContactPhone,
                MaritalStatus = e.MaritalStatus,
                Hometown = e.Hometown,
                EducationLevel = e.EducationLevel,
                BankName = e.BankName,
                BankAccountName = e.BankAccountName,
                BankAccountNumber = e.BankAccountNumber,
                IdCardFrontUrl = e.IdCardFrontUrl,
                IdCardBackUrl = e.IdCardBackUrl,
                DepartmentId = e.DepartmentId,
                Department = e.Department,
                Position = e.Position,
                Level = e.Level,
                EmploymentType = e.EmploymentType,
                JoinDate = e.JoinDate,
                ProbationEndDate = e.ProbationEndDate,
                WorkStatus = e.WorkStatus,
                DirectManagerEmployeeId = e.DirectManagerEmployeeId,
                DirectManagerName = e.DirectManagerEmployee != null
                    ? e.DirectManagerEmployee.LastName + " " + e.DirectManagerEmployee.FirstName
                    : null,
                ResignationDate = e.ResignationDate,
                ResignationReason = e.ResignationReason,
                Pin = e.DeviceUsers.OrderBy(x => x.CreatedAt).Select(x => x.Pin).FirstOrDefault(),
                CardNumber = e.DeviceUsers.OrderBy(x => x.CreatedAt).Select(x => x.CardNumber).FirstOrDefault(),
                DeviceId = e.DeviceUsers.OrderBy(x => x.CreatedAt).Select(x => x.DeviceId).FirstOrDefault(),
                ApplicationUserId = e.ApplicationUserId,
                HasAccount = e.ApplicationUserId != null,
            }
        );

        var result = new PagedResult<EmployeeDto>(pagedResult.Items, pagedResult.TotalCount, pagedResult.PageNumber, pagedResult.PageSize);

        
        return AppResponse<PagedResult<EmployeeDto>>.Success(result);
    }
}
