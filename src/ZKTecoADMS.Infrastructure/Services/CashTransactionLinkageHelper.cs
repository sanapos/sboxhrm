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
                await notificationService.CreateAndSendAsync(
                    advance.EmployeeUserId.Value,
                    NotificationType.Success,
                    "Ứng lương đã thanh toán",
                    $"Yêu cầu ứng lương {advance.Amount:N0}đ đã được thanh toán ({methodLabel})",
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
                        .Include(t => t.Employee)
                        .FirstOrDefaultAsync(t => t.TicketCode == code && t.StoreId == storeId, cancellationToken);
                }
            }
            else if (TryExtractTrailingGuid(cash.InternalNote, PenaltyTicketMarker, out var ticketId))
            {
                ticket = await context.PenaltyTickets
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
                "Phiếu phạt đã thu",
                $"Phiếu phạt {ticket.TicketCode} ({ticket.Amount:N0}đ) đã được thu qua phiếu {cash.TransactionCode}",
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
        Payslip? payslip = await context.Payslips
            .Include(p => p.Employee)
            .FirstOrDefaultAsync(
                p => p.CashTransactionId == cash.Id && p.StoreId == storeId,
                cancellationToken);

        if (payslip == null
            && TryExtractTrailingGuid(cash.InternalNote, PayslipMarker, out var payslipId))
        {
            payslip = await context.Payslips
                .Include(p => p.Employee)
                .FirstOrDefaultAsync(p => p.Id == payslipId && p.StoreId == storeId, cancellationToken);
        }

        if (payslip == null)
            return;

        var wasPaid = payslip.Status == PayslipStatus.Paid;
        if (payslip.CashTransactionId != cash.Id)
        {
            payslip.CashTransactionId = cash.Id;
        }

        if (!wasPaid)
        {
            payslip.Status = PayslipStatus.Paid;
            payslip.PaidDate = cash.PaidDate ?? DateTime.UtcNow;
            payslip.UpdatedAt = DateTime.UtcNow;
            await context.SaveChangesAsync(cancellationToken);
        }

        var uid = payslip.EmployeeUserId ?? payslip.Employee?.ApplicationUserId;
        if (!wasPaid && uid.HasValue && uid != performedByUserId)
        {
            try
            {
                var monthLabel = $"T{payslip.Month:D2}/{payslip.Year}";
                await notificationService.CreateAndSendAsync(
                    uid.Value,
                    NotificationType.Success,
                    "Lương đã thanh toán",
                    $"Phiếu lương kỳ {monthLabel} ({payslip.NetSalary:N0}đ) đã được thanh toán",
                    relatedEntityType: "Payslip",
                    relatedEntityId: payslip.Id,
                    fromUserId: performedByUserId,
                    categoryCode: "payroll",
                    storeId: storeId);
            }
            catch { /* best-effort */ }
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

    private static string GetPaymentMethodLabel(PaymentMethodType method) => method switch
    {
        PaymentMethodType.BankTransfer => "Chuyển khoản",
        PaymentMethodType.VietQR => "VietQR",
        PaymentMethodType.Card => "Thẻ",
        PaymentMethodType.EWallet => "Ví điện tử",
        _ => "Tiền mặt",
    };
}
