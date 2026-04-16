using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

public class EmployeeWorkingInfo : Entity<Guid>
{
    [Required]
    public Guid EmployeeId { get; set; }

    [Required]
    public Guid EmployeeUserId { get; set; }

    // Leave balances
    public decimal BalancedPaidLeaveDays { get; set; }

    public decimal BalancedUnpaidLeaveDays { get; set; }

    public decimal BalancedLateEarlyLeaveMinutes { get; set; }

    // Monthly profile configuration (populated when assigned to monthly profile)
    public int? StandardHoursPerDay { get; set; }
    
    [MaxLength(100)]
    public string? WeeklyOffDays { get; set; } // Comma-separated days like "Saturday,Sunday"
    
    public decimal? PaidLeaveDaysPerYear { get; set; }
    
    public decimal? UnpaidLeaveDaysPerYear { get; set; }
    
    // Navigation properties
    public DeviceUser Employee { get; set; } = null!;

    public ApplicationUser EmployeeUser { get; set; } = null!;
}