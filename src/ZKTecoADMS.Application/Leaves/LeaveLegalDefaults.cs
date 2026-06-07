using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Leaves;

public static class LeaveLegalDefaults
{
    public static void Apply(Leave leave, SickLeaveMode? requestedSickMode = null)
    {
        var sickMode = ResolveSickLeaveMode(leave.Type, requestedSickMode);
        leave.SickLeaveMode = sickMode;
        leave.PaymentSource = ResolvePaymentSource(leave.Type, sickMode);
    }

    public static SickLeaveMode ResolveSickLeaveMode(LeaveType type, SickLeaveMode? requested)
    {
        if (type != LeaveType.SickLeave)
            return SickLeaveMode.NotApplicable;

        if (requested is SickLeaveMode.UseAnnualLeave or SickLeaveMode.SocialInsurance)
            return requested.Value;

        return SickLeaveMode.SocialInsurance;
    }

    public static LeavePaymentSource ResolvePaymentSource(LeaveType type, SickLeaveMode sickMode) =>
        type switch
        {
            LeaveType.PersonalUnpaid or LeaveType.LongTermLeave => LeavePaymentSource.Unpaid,
            LeaveType.SickLeave => sickMode == SickLeaveMode.UseAnnualLeave
                ? LeavePaymentSource.EmployerPaid
                : LeavePaymentSource.SocialInsurance,
            LeaveType.MaternityLeave => LeavePaymentSource.EmployerWithBhxhSettlement,
            _ => LeavePaymentSource.EmployerPaid
        };

    public static string? Validate(LeaveType type, SickLeaveMode sickMode, string? bhxhDocumentNote)
    {
        if (type == LeaveType.SickLeave && sickMode == SickLeaveMode.SocialInsurance)
        {
            if (string.IsNullOrWhiteSpace(bhxhDocumentNote))
                return "Nghỉ ốm hưởng BHXH cần ghi số giấy nghỉ / mã hồ sơ BHXH.";
        }

        return null;
    }
}
