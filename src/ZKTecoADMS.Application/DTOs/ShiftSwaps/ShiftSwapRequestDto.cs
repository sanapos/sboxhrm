using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.ShiftSwaps;

/// <summary>
/// DTO thông tin chi tiết yêu cầu đổi ca
/// </summary>
public class ShiftSwapRequestDto
{
    public Guid Id { get; set; }
    public Guid StoreId { get; set; }
    
    // Requester info
    public Guid RequesterUserId { get; set; }
    public string RequesterName { get; set; } = string.Empty;
    public DateTime RequesterDate { get; set; }
    public Guid RequesterShiftId { get; set; }
    public string RequesterShiftName { get; set; } = string.Empty;
    
    // Target info
    public Guid TargetUserId { get; set; }
    public string TargetName { get; set; } = string.Empty;
    public DateTime TargetDate { get; set; }
    public Guid TargetShiftId { get; set; }
    public string TargetShiftName { get; set; } = string.Empty;
    
    public string? Reason { get; set; }
    public ShiftSwapStatus Status { get; set; }
    public string StatusText { get; set; } = string.Empty;
    
    public bool TargetAccepted { get; set; }
    public DateTime? TargetResponseDate { get; set; }
    
    public Guid? ApprovedByManagerId { get; set; }
    public string? ApprovedByManagerName { get; set; }
    public DateTime? ManagerApprovalDate { get; set; }
    
    public string? RejectionReason { get; set; }
    public string? Note { get; set; }
    
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

/// <summary>
/// DTO tạo yêu cầu đổi ca
/// </summary>
public class CreateShiftSwapRequestDto
{
    public Guid TargetUserId { get; set; }
    public DateTime RequesterDate { get; set; }
    public Guid RequesterShiftId { get; set; }
    public DateTime TargetDate { get; set; }
    public Guid TargetShiftId { get; set; }
    public string? Reason { get; set; }
}

/// <summary>
/// DTO phản hồi yêu cầu đổi ca (từ người được yêu cầu)
/// </summary>
public class RespondShiftSwapDto
{
    public bool Accept { get; set; }
    public string? RejectionReason { get; set; }
}

/// <summary>
/// DTO phê duyệt/từ chối từ quản lý
/// </summary>
public class ManagerDecisionDto
{
    public bool Approve { get; set; }
    public string? RejectionReason { get; set; }
    public string? Note { get; set; }
}
