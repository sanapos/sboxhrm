using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Employees;

public class CreateEmployeeRequest
{
    // Identity Information
    public string EmployeeCode { get; set; } = string.Empty;
    public string FirstName { get; set; } = string.Empty;
    public string LastName { get; set; } = string.Empty;
    public string? Gender { get; set; }
    public DateTime? DateOfBirth { get; set; }
    public string? PhotoUrl { get; set; }
    public string? NationalIdNumber { get; set; }
    public DateTime? NationalIdIssueDate { get; set; }
    public string? NationalIdIssuePlace { get; set; }

    // Contact Information
    public string? PhoneNumber { get; set; }
    public string? PersonalEmail { get; set; }
    public string? CompanyEmail { get; set; } = string.Empty;
    public string? PermanentAddress { get; set; }
    public string? TemporaryAddress { get; set; }
    public string? EmergencyContactName { get; set; }
    public string? EmergencyContactPhone { get; set; }
    public string? MaritalStatus { get; set; }
    public string? Hometown { get; set; }
    public string? EducationLevel { get; set; }

    // Bank Information
    public string? BankName { get; set; }
    public string? BankAccountName { get; set; }
    public string? BankAccountNumber { get; set; }

    // CCCD Photos
    public string? IdCardFrontUrl { get; set; }
    public string? IdCardBackUrl { get; set; }

    // Work Information
    public string? Department { get; set; }
    public string? Position { get; set; }
    public string? Level { get; set; }
    public EmploymentType EmploymentType { get; set; }
    public DateTime? JoinDate { get; set; }
    public DateTime? ProbationEndDate { get; set; }
    public EmployeeWorkStatus WorkStatus { get; set; }
    public Guid? DirectManagerEmployeeId { get; set; }

}
