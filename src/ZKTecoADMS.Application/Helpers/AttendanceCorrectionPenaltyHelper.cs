using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Hủy phiếu phạt / phiếu thu khi duyệt chỉnh sửa chấm công.
/// </summary>
public static class AttendanceCorrectionPenaltyHelper
{
    public static async Task CancelPenaltyTicketAsync(
        PenaltyTicket ticket,
        string reason,
        IRepository<PenaltyTicket> penaltyTicketRepository,
        IRepository<PaymentTransaction> paymentTransactionRepository,
        IRepository<CashTransaction> cashTransactionRepository,
        CancellationToken cancellationToken = default)
    {
        if (ticket.Status == PenaltyTicketStatus.Cancelled)
            return;

        ticket.Status = PenaltyTicketStatus.Cancelled;
        ticket.ProcessedDate = DateTime.UtcNow;
        ticket.CancellationReason = reason;
        ticket.UpdatedAt = DateTime.UtcNow;
        await penaltyTicketRepository.UpdateAsync(ticket, cancellationToken);

        if (ticket.CashTransactionId.HasValue)
        {
            var cash = await cashTransactionRepository.GetByIdAsync(
                ticket.CashTransactionId.Value, cancellationToken: cancellationToken);
            if (cash != null && cash.Deleted == null)
            {
                cash.Status = CashTransactionStatus.Cancelled;
                cash.IsPaid = false;
                cash.PaidDate = null;
                cash.IsActive = false;
                cash.UpdatedAt = DateTime.UtcNow;
                cash.InternalNote = AppendNote(cash.InternalNote, reason);
                await cashTransactionRepository.UpdateAsync(cash, cancellationToken);
            }
        }

        var txs = (await paymentTransactionRepository.GetAllAsync(
            filter: tx => tx.EmployeeId == ticket.EmployeeId
                && tx.Type == "Penalty"
                && tx.TransactionDate.Date == ticket.ViolationDate.Date
                && tx.Status == "Pending"
                && (tx.Description == ticket.Description
                    || (tx.Note != null && tx.Note.Contains(ticket.TicketCode))),
            cancellationToken: cancellationToken)).ToList();

        foreach (var tx in txs)
        {
            tx.Status = "Cancelled";
            tx.Note = AppendNote(tx.Note, reason);
            await paymentTransactionRepository.UpdateAsync(tx, cancellationToken);
        }
    }

    public static async Task CancelPenaltiesForAttendanceAsync(
        Guid attendanceId,
        Guid correctionId,
        IRepository<PenaltyTicket> penaltyTicketRepository,
        IRepository<PaymentTransaction> paymentTransactionRepository,
        IRepository<CashTransaction> cashTransactionRepository,
        CancellationToken cancellationToken = default)
    {
        var reason = $"Tự động hủy do duyệt chỉnh sửa chấm công [YC:{correctionId}]";
        var tickets = (await penaltyTicketRepository.GetAllAsync(
            filter: t => t.AttendanceId == attendanceId
                && (t.Status == PenaltyTicketStatus.Pending
                    || t.Status == PenaltyTicketStatus.Approved
                    || t.Status == PenaltyTicketStatus.AutoApproved),
            cancellationToken: cancellationToken)).ToList();

        foreach (var ticket in tickets)
            await CancelPenaltyTicketAsync(ticket, reason, penaltyTicketRepository,
                paymentTransactionRepository, cashTransactionRepository, cancellationToken);
    }

    public static async Task CancelDayLevelPenaltiesAsync(
        Guid employeeId,
        DateTime violationDate,
        Guid correctionId,
        IRepository<PenaltyTicket> penaltyTicketRepository,
        IRepository<PaymentTransaction> paymentTransactionRepository,
        IRepository<CashTransaction> cashTransactionRepository,
        CancellationToken cancellationToken = default)
    {
        var date = violationDate.Date;
        var reason = $"Tự động hủy do duyệt bù chấm công [YC:{correctionId}]";
        var tickets = (await penaltyTicketRepository.GetAllAsync(
            filter: t => t.EmployeeId == employeeId
                && t.ViolationDate == date
                && (t.Type == PenaltyTicketType.ForgotCheck
                    || t.Type == PenaltyTicketType.UnauthorizedLeave
                    || t.Type == PenaltyTicketType.Late
                    || t.Type == PenaltyTicketType.EarlyLeave)
                && (t.Status == PenaltyTicketStatus.Pending
                    || t.Status == PenaltyTicketStatus.Approved
                    || t.Status == PenaltyTicketStatus.AutoApproved),
            cancellationToken: cancellationToken)).ToList();

        foreach (var ticket in tickets)
            await CancelPenaltyTicketAsync(ticket, reason, penaltyTicketRepository,
                paymentTransactionRepository, cashTransactionRepository, cancellationToken);
    }

    private static string AppendNote(string? existing, string addition)
    {
        if (string.IsNullOrWhiteSpace(existing))
            return addition;
        if (existing.Contains(addition, StringComparison.Ordinal))
            return existing;
        return $"{existing} | {addition}";
    }
}
