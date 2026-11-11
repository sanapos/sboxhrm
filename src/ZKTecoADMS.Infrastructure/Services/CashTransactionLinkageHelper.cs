using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Khi kế toán thanh toán phiếu thu/chi → cập nhật phiếu ứng lương / thưởng-phạt / phiếu phạt liên kết + gửi thông báo NV.
/// </summary>
public static class CashTransactionLinkageHelper
{
    private const string AdvanceMarker = "yêu cầu ứng lương #";
    private const string BonusPenaltyMarker = "phiếu thưởng/phạt #";
    private const string PenaltyTicketMarker = "phiếu phạt #";
    private const string PayslipMarker = PayslipCashTransactionHelper.InternalNoteMarker;

    public static async Task ApplyOnCashPaidAsync(
        ZKTecoDbContext context,
        ISystemNotificationService notificationService,
        CashTransaction cash,
        Guid performedByUserId,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        if (!cash.IsPaid || cash.Status != CashTransactionStatus.Completed)
            return;

        await TrySyncAdvanceOnPaidAsync(context, notificationService, cash, performedByUserId, storeId, cancellationToken);
        await TrySyncBusinessTripAdvanceOnPaidAsync(context, notificationService, cash, performedByUserId, storeId, cancellationToken);
        await TrySyncBusinessTripSettlementExtraOnPaidAsync(context, notificationService, cash, performedByUserId, storeId, cancellationToken);
        await TrySyncBusinessTripSurplusRefundOnPaidAsync(context, notificationService, cash, performedByUserId, storeId, cancellationToken);
        await TrySyncPaymentTransactionOnPaidAsync(context, notificationService, cash, performedByUserId, storeId, cancellationToken);
        await TrySyncPenaltyTicketOnPaidAsync(context, notificationService, cash, performedByUserId, storeId, cancellationToken);
        await TrySyncPayslipOnPaidAsync(context, notificationService, cash, performedByUserId, storeId, cancellationToken);
    }

    private static async Task TrySyncAdvanceOnPaidAsync(
        ZKTecoDbContext context,
        ISystemNotificationService notificationService,
        CashTransaction cash,
        Guid performedByUserId,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        if (!TryExtractTrailingGuid(cash.InternalNote, AdvanceMarker, out var advanceId)
            && !TryExtractTrailingGuid(cash.InternalNote, "thanh toán ứng lương #", out advanceId))
            return;

        var advance = await context.AdvanceRequests
            .AsTracking()
            .Include(a => a.Employee)
            .Include(a => a.EmployeeUser)
            .FirstOrDefaultAsync(a => a.Id == advanceId && a.StoreId == storeId, cancellationToken);

        if (advance == null || advance.Status != AdvanceRequestStatus.Approved)
            return;

        var methodLabel = GetPaymentMethodLabel(cash.PaymentMethod);
        var wasPaid = advance.IsPaid;

        if (!advance.IsPaid)
        {
            advance.IsPaid = true;
            advance.PaymentMethod = methodLabel;
            advance.PaidDate = cash.PaidDate ?? DateTime.UtcNow;
            advance.UpdatedAt = DateTime.UtcNow;
        }

        await context.SaveChangesAsync(cancellationToken);

        if (!wasPaid && advance.EmployeeUserId.HasValue)
        {
            try
            {
                // Số đã chi = số trên phiếu chi (lúc duyệt dùng ApprovedAmount ?? Amount) — trước đây in số xin
                // (advance.Amount) nên duyệt 2tr vẫn báo «3.000.000đ».
                var approved = advance.ApprovedAmount ?? advance.Amount;
                var paid = cash.Amount > 0 ? cash.Amount : approved;
                var body = methodLabel;
                if (Math.Abs(advance.Amount - paid) >= 1)
                    body += $" · xin {Vnd(advance.Amount)}";
                await notificationService.CreateAndSendAsync(
                    advance.EmployeeUserId.Value,
                    NotificationType.Success,
                    $"Đã chi ứng lương {Vnd(paid)}",
                    body,
                    relatedEntityId: advance.Id,
                    relatedEntityType: "AdvanceRequest",
                    fromUserId: performedByUserId,
                    categoryCode: "payroll",
                    storeId: storeId);
            }
            catch { /* best-effort */ }
        }
    }

    private static async Task TrySyncPaymentTransactionOnPaidAsync(
        ZKTecoDbContext context,
        ISystemNotificationService notificationService,
        CashTransaction cash,
        Guid performedByUserId,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        if (!TryExtractTrailingGuid(cash.InternalNote, BonusPenaltyMarker, out var paymentTxId))
            return;

        var tx = await context.PaymentTransactions
            .AsTracking()
            .Include(t => t.Employee)
            .FirstOrDefaultAsync(t => t.Id == paymentTxId, cancellationToken);

        if (tx == null || tx.Status != "Completed")
            return;

        var method = cash.PaymentMethod.ToString();
        var wasUnset = string.IsNullOrWhiteSpace(tx.PaymentMethod);

        if (wasUnset)
        {
            tx.PaymentMethod = method;
            tx.UpdatedAt = DateTime.UtcNow;
            await context.SaveChangesAsync(cancellationToken);
        }

        if (wasUnset)
        {
            try
            {
                await PaymentTransactionNotificationHelper.NotifyPaidAsync(
                    notificationService, tx, performedByUserId, storeId);
            }
            catch { /* best-effort */ }
        }
    }

    private static async Task TrySyncPenaltyTicketOnPaidAsync(
        ZKTecoDbContext context,
        ISystemNotificationService notificationService,
        CashTransaction cash,
        Guid performedByUserId,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        PenaltyTicket? ticket = await context.PenaltyTickets
            .AsTracking()
            .Include(t => t.Employee)
            .FirstOrDefaultAsync(t => t.CashTransactionId == cash.Id && t.StoreId == storeId, cancellationToken);

        if (ticket == null && cash.InternalNote != null)
        {
            if (cash.InternalNote.Contains("Tạo từ phiếu phạt ", StringComparison.OrdinalIgnoreCase))
            {
                var code = cash.InternalNote
                    .Split("Tạo từ phiếu phạt ", StringSplitOptions.RemoveEmptyEntries)
                    .LastOrDefault()?.Split('|', ' ')[0]?.Trim();
                if (!string.IsNullOrEmpty(code))
                {
                    ticket = await context.PenaltyTickets
                        .AsTracking()
                        .Include(t => t.Employee)
                        .FirstOrDefaultAsync(t => t.TicketCode == code && t.StoreId == storeId, cancellationToken);
                }
            }
            else if (TryExtractTrailingGuid(cash.InternalNote, PenaltyTicketMarker, out var ticketId))
            {
                ticket = await context.PenaltyTickets
                    .AsTracking()
                    .Include(t => t.Employee)
                    .FirstOrDefaultAsync(t => t.Id == ticketId && t.StoreId == storeId, cancellationToken);
            }
        }

        if (ticket == null)
            return;

        if (ticket.CashTransactionId != cash.Id)
        {
            ticket.CashTransactionId = cash.Id;
            ticket.UpdatedAt = DateTime.UtcNow;
            await context.SaveChangesAsync(cancellationToken);
        }

        var uid = ticket.Employee?.ApplicationUserId;
        if (uid == null || uid == performedByUserId)
            return;

        try
        {
            await notificationService.CreateAndSendAsync(
                uid.Value,
                NotificationType.Success,
                $"Đã thu phạt {Vnd(ticket.Amount)}",
                string.IsNullOrWhiteSpace(ticket.Description)
                    ? $"Phiếu {ticket.TicketCode}"
                    : $"{ticket.Description.Trim()} · phiếu {ticket.TicketCode}",
                relatedEntityType: "PenaltyTicket",
                relatedEntityId: ticket.Id,
                fromUserId: performedByUserId,
                categoryCode: "penalty",
                storeId: storeId);
        }
        catch { /* best-effort */ }
    }

    private static async Task TrySyncPayslipOnPaidAsync(
        ZKTecoDbContext context,
        ISystemNotificationService notificationService,
        CashTransaction cash,
        Guid performedByUserId,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        // Phiếu lương «Đã trả» chỉ khi tổng phiếu chi hoàn thành đủ thực lĩnh (trả nhiều lần / nhiều phương thức).
        var (payslip, becamePaid) = await PayslipPayments.SyncForVoucherAsync(
            context, cash, storeId, performedByUserId, ensurePending: true, cancellationToken);
        if (payslip == null || !becamePaid) return;

        var uid = payslip.EmployeeUserId ?? payslip.Employee?.ApplicationUserId;
        if (uid.HasValue && uid != performedByUserId)
        {
            try
            {
                var monthLabel = $"T{payslip.Month:D2}/{payslip.Year}";
                await notificationService.CreateAndSendAsync(
                    uid.Value,
                    NotificationType.Success,
                    $"Lương {monthLabel} đã thanh toán đủ",
                    $"Thực lĩnh {Vnd(payslip.NetSalary)}",
                    relatedEntityType: "Payslip",
                    relatedEntityId: payslip.Id,
                    fromUserId: performedByUserId,
                    categoryCode: "payroll",
                    storeId: storeId);
            }
            catch { /* best-effort */ }
        }
    }

    private static async Task TrySyncBusinessTripAdvanceOnPaidAsync(
        ZKTecoDbContext context,
        ISystemNotificationService notificationService,
        CashTransaction cash,
        Guid performedByUserId,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        if (!TryExtractTrailingGuid(cash.InternalNote, "ứng công tác #", out var advanceClaimId))
            return;

        var advance = await context.BusinessTripAdvanceClaims
            .AsTracking()
            .Include(a => a.Case)
            .FirstOrDefaultAsync(a => a.Id == advanceClaimId && a.StoreId == storeId, cancellationToken);

        if (advance == null || advance.Status != AdvanceRequestStatus.Approved || advance.Case == null)
            return;

        var methodLabel = GetPaymentMethodLabel(cash.PaymentMethod);
        var wasPaid = advance.IsPaid;

        if (!advance.IsPaid)
        {
            advance.IsPaid = true;
            advance.PaymentMethod = methodLabel;
            advance.PaidDate = cash.PaidDate ?? DateTime.UtcNow;
            advance.CashTransactionId = cash.Id;
            advance.Case.Status = BusinessTripCaseStatus.AdvancePaid;
            advance.Case.AdvanceAmount = advance.Amount;
            advance.Case.UpdatedAt = DateTime.UtcNow;
            await context.SaveChangesAsync(cancellationToken);
        }

        if (!wasPaid && advance.Case.EmployeeUserId.HasValue)
        {
            try
            {
                await notificationService.CreateAndSendAsync(
                    advance.Case.EmployeeUserId.Value,
                    NotificationType.Success,
                    $"Đã chi ứng công tác {Vnd(advance.Amount)}",
                    JoinParts(TripLabel(advance.Case), methodLabel),
                    relatedEntityId: advance.Case.Id,
                    relatedEntityType: "BusinessTripCase",
                    fromUserId: performedByUserId,
                    categoryCode: "business_trip",
                    storeId: storeId);
            }
            catch { }
        }
    }

    private static async Task TrySyncBusinessTripSettlementExtraOnPaidAsync(
        ZKTecoDbContext context,
        ISystemNotificationService notificationService,
        CashTransaction cash,
        Guid performedByUserId,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        if (!TryExtractTrailingGuid(cash.InternalNote, "quyết toán công tác phí #", out var settlementId))
            return;

        var settlement = await context.BusinessTripSettlementClaims
            .AsTracking()
            .Include(s => s.Case)
            .FirstOrDefaultAsync(s => s.Id == settlementId && s.StoreId == storeId, cancellationToken);

        if (settlement == null || settlement.Case == null || settlement.IsExtraPaid)
            return;

        var methodLabel = GetPaymentMethodLabel(cash.PaymentMethod);
        settlement.IsExtraPaid = true;
        settlement.ExtraPaymentMethod = methodLabel;
        settlement.ExtraPaidDate = cash.PaidDate ?? DateTime.UtcNow;
        settlement.ExtraCashTransactionId = cash.Id;
        settlement.Case.Status = BusinessTripCaseStatus.Closed;
        settlement.Case.UpdatedAt = DateTime.UtcNow;
        await context.SaveChangesAsync(cancellationToken);

        if (settlement.Case.EmployeeUserId.HasValue)
        {
            try
            {
                await notificationService.CreateAndSendAsync(
                    settlement.Case.EmployeeUserId.Value,
                    NotificationType.Success,
                    $"Đã chi bù công tác phí {Vnd(settlement.BalanceAmount)}",
                    JoinParts(TripLabel(settlement.Case), methodLabel),
                    relatedEntityId: settlement.Case.Id,
                    relatedEntityType: "BusinessTripCase",
                    fromUserId: performedByUserId,
                    categoryCode: "business_trip",
                    storeId: storeId);
            }
            catch { }
        }
    }

    private static async Task TrySyncBusinessTripSurplusRefundOnPaidAsync(
        ZKTecoDbContext context,
        ISystemNotificationService notificationService,
        CashTransaction cash,
        Guid performedByUserId,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        if (!TryExtractTrailingGuid(cash.InternalNote, "thu hoàn ứng công tác #", out var settlementId))
            return;

        var settlement = await context.BusinessTripSettlementClaims
            .AsTracking()
            .Include(s => s.Case)
            .FirstOrDefaultAsync(s => s.Id == settlementId && s.StoreId == storeId, cancellationToken);

        if (settlement == null || settlement.Case == null || settlement.IsExtraPaid)
            return;

        var methodLabel = GetPaymentMethodLabel(cash.PaymentMethod);
        settlement.SettlementType = BusinessTripSettlementType.SurplusRefunded;
        settlement.IsExtraPaid = true;
        settlement.ExtraPaymentMethod = methodLabel;
        settlement.ExtraPaidDate = cash.PaidDate ?? DateTime.UtcNow;
        settlement.ExtraCashTransactionId = cash.Id;
        settlement.Case.Status = BusinessTripCaseStatus.Closed;
        settlement.Case.UpdatedAt = DateTime.UtcNow;
        await context.SaveChangesAsync(cancellationToken);

        if (settlement.Case.EmployeeUserId.HasValue)
        {
            try
            {
                await notificationService.CreateAndSendAsync(
                    settlement.Case.EmployeeUserId.Value,
                    NotificationType.Success,
                    $"Đã thu hoàn ứng công tác {Vnd(Math.Abs(settlement.BalanceAmount))}",
                    JoinParts(TripLabel(settlement.Case), methodLabel),
                    relatedEntityId: settlement.Case.Id,
                    relatedEntityType: "BusinessTripCase",
                    fromUserId: performedByUserId,
                    categoryCode: "business_trip",
                    storeId: storeId);
            }
            catch { }
        }
    }

    public static bool TryExtractTrailingGuid(string? note, string markerContains, out Guid id)
    {
        id = Guid.Empty;
        if (string.IsNullOrWhiteSpace(note)
            || !note.Contains(markerContains, StringComparison.OrdinalIgnoreCase))
            return false;

        var hashIndex = note.LastIndexOf('#');
        if (hashIndex < 0 || hashIndex >= note.Length - 1)
            return false;

        var tail = note[(hashIndex + 1)..].Trim();
        var guidPart = tail.Length >= 36 ? tail[..36] : tail.Split([' ', '|', '\n', '\r'], StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? tail;
        return Guid.TryParse(guidPart, out id);
    }

    /// <summary>Tiền kiểu Việt: 2000000 → «2.000.000đ».</summary>
    internal static string Vnd(decimal v) =>
        Math.Round(v, 0).ToString("#,0", System.Globalization.CultureInfo.InvariantCulture).Replace(',', '.') + "đ";

    private static string JoinParts(params string?[] parts) =>
        string.Join(" · ", parts.Where(p => !string.IsNullOrWhiteSpace(p)).Select(p => p!.Trim()));

    /// <summary>
    /// Chuyến công tác nào: «Đà Nẵng 12–14/11». Ngày chuyến là ngày lịch (00:00), không đổi múi giờ.
    /// </summary>
    private static string? TripLabel(BusinessTripCase? c)
    {
        if (c == null) return null;
        var name = !string.IsNullOrWhiteSpace(c.Title) ? c.Title.Trim()
            : !string.IsNullOrWhiteSpace(c.Destination) ? c.Destination.Trim()
            : c.CaseCode;
        string? dates = null;
        if (c.TripFromDate is DateTime from)
        {
            var f = from.Date;
            var t = c.TripToDate?.Date;
            dates = t == null || t == f
                ? f.ToString("dd/MM")
                : f.Month == t.Value.Month && f.Year == t.Value.Year
                    ? $"{f:dd}–{t.Value:dd/MM}"
                    : $"{f:dd/MM}–{t.Value:dd/MM}";
        }
        return JoinParts(name, dates);
    }

    private static string GetPaymentMethodLabel(PaymentMethodType method) => method switch
    {
        PaymentMethodType.BankTransfer => "Chuyển khoản",
        PaymentMethodType.VietQR => "VietQR",
        PaymentMethodType.Card => "Thẻ",
        PaymentMethodType.EWallet => "Ví điện tử",
        _ => "Tiền mặt",
    };
}
