using ZKTecoADMS.Application.DTOs.BusinessTrip;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Helpers;

public static class BusinessTripMapper
{
    public static BusinessTripCaseDto ToDto(BusinessTripCase entity)
    {
        var emp = entity.Employee;
        var empUser = entity.EmployeeUser;
        var empName = emp != null
            ? $"{emp.LastName} {emp.FirstName}".Trim()
            : empUser != null
                ? $"{empUser.LastName} {empUser.FirstName}".Trim()
                : string.Empty;

        return new BusinessTripCaseDto
        {
            Id = entity.Id,
            CaseCode = entity.CaseCode,
            EmployeeId = entity.EmployeeId,
            EmployeeUserId = entity.EmployeeUserId,
            EmployeeName = empName,
            EmployeeCode = emp?.EmployeeCode ?? string.Empty,
            Title = entity.Title,
            Destination = entity.Destination,
            TripFromDate = entity.TripFromDate,
            TripToDate = entity.TripToDate,
            Note = entity.Note,
            Status = (int)entity.Status,
            AdvanceAmount = entity.AdvanceAmount,
            SettledAmount = entity.SettledAmount,
            BalanceAmount = entity.BalanceAmount,
            Advance = entity.AdvanceClaim != null ? ToAdvanceDto(entity.AdvanceClaim) : null,
            Settlement = entity.SettlementClaim != null ? ToSettlementDto(entity.SettlementClaim) : null,
            CreatedAt = entity.CreatedAt,
            UpdatedAt = entity.UpdatedAt
        };
    }

    public static BusinessTripAdvanceClaimDto ToAdvanceDto(BusinessTripAdvanceClaim a) => new()
    {
        Id = a.Id,
        CaseId = a.CaseId,
        Amount = a.Amount,
        Reason = a.Reason,
        Note = a.Note,
        RequestDate = a.RequestDate,
        Status = (int)a.Status,
        IsPaid = a.IsPaid,
        PaymentMethod = a.PaymentMethod,
        PaidDate = a.PaidDate,
        CashTransactionId = a.CashTransactionId,
        RejectionReason = a.RejectionReason,
        TotalApprovalLevels = a.TotalApprovalLevels,
        CurrentApprovalStep = a.CurrentApprovalStep,
        ApprovalRecords = a.ApprovalRecords?.OrderBy(r => r.StepOrder).Select(ToApprovalDto).ToList() ?? []
    };

    public static BusinessTripSettlementClaimDto ToSettlementDto(BusinessTripSettlementClaim s) => new()
    {
        Id = s.Id,
        CaseId = s.CaseId,
        AdvanceAmount = s.AdvanceAmount,
        TotalAmount = s.TotalAmount,
        TotalWithInvoice = s.TotalWithInvoice,
        TotalWithoutInvoice = s.TotalWithoutInvoice,
        BalanceAmount = s.BalanceAmount,
        SettlementType = (int)s.SettlementType,
        Note = s.Note,
        Status = (int)s.Status,
        IsExtraPaid = s.IsExtraPaid,
        ExtraPaymentMethod = s.ExtraPaymentMethod,
        ExtraPaidDate = s.ExtraPaidDate,
        ExtraCashTransactionId = s.ExtraCashTransactionId,
        SurplusPaymentTransactionId = s.SurplusPaymentTransactionId,
        SurplusAdvanceRequestId = s.SurplusAdvanceRequestId,
        RejectionReason = s.RejectionReason,
        TotalApprovalLevels = s.TotalApprovalLevels,
        CurrentApprovalStep = s.CurrentApprovalStep,
        Lines = s.Lines?.OrderBy(l => l.SortOrder).Select(ToLineDto).ToList() ?? [],
        ApprovalRecords = s.ApprovalRecords?.OrderBy(r => r.StepOrder).Select(ToApprovalDto).ToList() ?? []
    };

    public static BusinessTripApprovalRecordDto ToApprovalDto(BusinessTripAdvanceApprovalRecord r) => new()
    {
        Id = r.Id,
        StepOrder = r.StepOrder,
        StepName = r.StepName,
        AssignedUserId = r.AssignedUserId,
        AssignedUserName = r.AssignedUserName,
        ActualUserId = r.ActualUserId,
        ActualUserName = r.ActualUserName,
        Status = (int)r.Status,
        Note = r.Note,
        ActionDate = r.ActionDate
    };

    public static BusinessTripApprovalRecordDto ToApprovalDto(BusinessTripSettlementApprovalRecord r) => new()
    {
        Id = r.Id,
        StepOrder = r.StepOrder,
        StepName = r.StepName,
        AssignedUserId = r.AssignedUserId,
        AssignedUserName = r.AssignedUserName,
        ActualUserId = r.ActualUserId,
        ActualUserName = r.ActualUserName,
        Status = (int)r.Status,
        Note = r.Note,
        ActionDate = r.ActionDate
    };

    public static BusinessTripExpenseLineDto ToLineDto(BusinessTripExpenseLine l) => new()
    {
        Id = l.Id,
        CategoryId = l.CategoryId,
        CategoryName = l.Category?.Name,
        ExpenseDate = l.ExpenseDate,
        Amount = l.Amount,
        Description = l.Description,
        Note = l.Note,
        HasInvoice = l.HasInvoice,
        InvoiceNumber = l.InvoiceNumber,
        InvoiceDate = l.InvoiceDate,
        SortOrder = l.SortOrder,
        Attachments = l.Attachments?.Select(a => new BusinessTripExpenseAttachmentDto
        {
            Id = a.Id,
            FileName = a.FileName,
            FileUrl = a.FileUrl,
            ContentType = a.ContentType,
            FileSize = a.FileSize,
            AttachmentType = (int)a.AttachmentType
        }).ToList() ?? []
    };

    public static BusinessTripExpenseCategoryDto ToCategoryDto(BusinessTripExpenseCategory c) => new()
    {
        Id = c.Id,
        Code = c.Code,
        Name = c.Name,
        Description = c.Description,
        MaxAmountPerLine = c.MaxAmountPerLine,
        MaxAmountPerMonth = c.MaxAmountPerMonth,
        RequiresInvoice = c.RequiresInvoice,
        SortOrder = c.SortOrder,
        IsActive = c.IsActive
    };
}
