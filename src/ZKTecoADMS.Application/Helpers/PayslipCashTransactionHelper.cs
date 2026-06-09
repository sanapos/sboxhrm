using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

public static class PayslipCashTransactionHelper
{
    public const string InternalNoteMarker = "phiếu lương #";

    public static string BuildInternalNote(Guid payslipId) => $"{InternalNoteMarker}{payslipId}";

    public static async Task EnsureExpenseVoucherAsync(
        Payslip payslip,
        Employee employee,
        Guid storeId,
        Guid userId,
        IPayslipRepository payslipRepository,
        IRepository<CashTransaction> cashTransactionRepository,
        IRepository<TransactionCategory> categoryRepository,
        CancellationToken cancellationToken = default)
    {
        var employeeName = $"{employee.LastName} {employee.FirstName}".Trim();
        if (string.IsNullOrWhiteSpace(employeeName))
            employeeName = employee.EmployeeCode ?? "Nhân viên";

        var marker = BuildInternalNote(payslip.Id);
        var monthLabel = $"T{payslip.Month:D2}/{payslip.Year}";
        var description = $"Chi lương {monthLabel} - {employeeName}";

        CashTransaction? cash = null;
        if (payslip.CashTransactionId.HasValue)
        {
            cash = await cashTransactionRepository.GetByIdAsync(
                payslip.CashTransactionId.Value, cancellationToken: cancellationToken);
            if (cash is { IsActive: false })
                cash = null;
        }

        if (cash == null)
        {
            cash = await cashTransactionRepository.GetSingleAsync(
                filter: c => c.IsActive &&
                             c.Deleted == null &&
                             c.InternalNote != null &&
                             c.InternalNote.Contains(marker),
                cancellationToken: cancellationToken);
        }

        if (cash != null)
        {
            if (!cash.IsPaid)
            {
                cash.Amount = payslip.NetSalary;
                cash.Description = description;
                cash.ContactName = employeeName;
                cash.TransactionDate = DateTime.UtcNow;
                cash.UpdatedAt = DateTime.UtcNow;
                await cashTransactionRepository.UpdateAsync(cash, cancellationToken);
            }

            if (payslip.CashTransactionId != cash.Id)
            {
                payslip.CashTransactionId = cash.Id;
                await payslipRepository.UpdateAsync(payslip, cancellationToken);
            }

            return;
        }

        var category = await categoryRepository.GetSingleAsync(
            filter: c => c.Name == "Chi lương" &&
                         c.Type == CashTransactionType.Expense &&
                         c.StoreId == storeId,
            cancellationToken: cancellationToken);

        if (category == null)
        {
            category = new TransactionCategory
            {
                Id = Guid.NewGuid(),
                Name = "Chi lương",
                Description = "Chi trả lương nhân viên",
                Type = CashTransactionType.Expense,
                Icon = "payments",
                Color = "#059669",
                IsSystem = true,
                StoreId = storeId,
            };
            await categoryRepository.AddAsync(category, cancellationToken);
        }

        var now = DateTime.UtcNow;
        var cashTx = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = $"CH-{now:yyyyMMdd}-{Guid.NewGuid().ToString()[..4].ToUpperInvariant()}",
            Type = CashTransactionType.Expense,
            CategoryId = category.Id,
            Amount = payslip.NetSalary,
            TransactionDate = now,
            Description = description,
            PaymentMethod = PaymentMethodType.Cash,
            Status = CashTransactionStatus.Pending,
            ContactName = employeeName,
            CreatedByUserId = userId,
            IsPaid = false,
            InternalNote = marker,
            IsActive = true,
            StoreId = storeId,
        };
        await cashTransactionRepository.AddAsync(cashTx, cancellationToken);

        payslip.CashTransactionId = cashTx.Id;
        if (payslip.Status != PayslipStatus.Paid)
        {
            payslip.Status = PayslipStatus.Approved;
            payslip.PaidDate = null;
        }
        await payslipRepository.UpdateAsync(payslip, cancellationToken);
    }
}
