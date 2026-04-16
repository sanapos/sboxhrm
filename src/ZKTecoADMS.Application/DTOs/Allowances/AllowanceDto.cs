using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Allowances;

public class AllowanceDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Code { get; set; }
    public string? Description { get; set; }
    public AllowanceType Type { get; set; }
    public decimal Amount { get; set; }
    public string? Currency { get; set; }
    public bool IsTaxable { get; set; }
    public bool IsInsuranceApplicable { get; set; }
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public List<string>? EmployeeIds { get; set; }
}

public class CreateAllowanceDto
{
    public string Name { get; set; } = string.Empty;
    public string? Code { get; set; }
    public string? Description { get; set; }
    public AllowanceType Type { get; set; }
    public decimal Amount { get; set; }
    public string? Currency { get; set; } = "VND";
    public bool IsTaxable { get; set; } = true;
    public bool IsInsuranceApplicable { get; set; } = false;
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public List<string>? EmployeeIds { get; set; }
}

public class UpdateAllowanceDto
{
    public string Name { get; set; } = string.Empty;
    public string? Code { get; set; }
    public string? Description { get; set; }
    public AllowanceType Type { get; set; }
    public decimal Amount { get; set; }
    public string? Currency { get; set; }
    public bool IsTaxable { get; set; }
    public bool IsInsuranceApplicable { get; set; }
    public bool IsActive { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public List<string>? EmployeeIds { get; set; }
}

public class AllowanceQueryParams
{
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public AllowanceType? Type { get; set; }
    public bool? IsActive { get; set; }
    public string? SearchTerm { get; set; }
}
