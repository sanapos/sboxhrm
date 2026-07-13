namespace ZKTecoADMS.Domain.Enums;

/// <summary>Trạng thái hồ sơ công tác (ứng → hoạch toán → đóng).</summary>
public enum BusinessTripCaseStatus
{
    Draft = 0,
    AdvancePending = 1,
    AdvanceApproved = 2,
    AdvancePaid = 3,
    SettlementDraft = 4,
    SettlementPending = 5,
    SettlementApproved = 6,
    Settling = 7,
    Closed = 8,
    Cancelled = 9
}

/// <summary>Kết quả quyết toán sau hoạch toán.</summary>
public enum BusinessTripSettlementType
{
    Balanced = 0,
    PayExtra = 1,
    SurplusAsAdvance = 2,
    SurplusRefunded = 3
}

public enum BusinessTripAttachmentType
{
    Invoice = 0,
    Receipt = 1,
    Other = 2
}
