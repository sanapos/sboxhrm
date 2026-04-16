namespace ZKTecoADMS.Domain.Enums;

public enum PayslipStatus
{
    /// <summary>
    /// Payslip is in draft state, not yet finalized
    /// </summary>
    Draft = 0,

    /// <summary>
    /// Payslip has been generated and is pending approval
    /// </summary>
    PendingApproval = 1,

    /// <summary>
    /// Payslip has been approved and is ready for payment
    /// </summary>
    Approved = 2,

    /// <summary>
    /// Payment has been made
    /// </summary>
    Paid = 3,

    /// <summary>
    /// Payslip has been cancelled/voided
    /// </summary>
    Cancelled = 4
}
