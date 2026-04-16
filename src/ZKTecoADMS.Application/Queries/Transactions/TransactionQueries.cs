using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Transactions;
using ZKTecoADMS.Application.DTOs.Commons;

namespace ZKTecoADMS.Application.Queries.Transactions;

// Get All Transactions Query (for Admin)
public record GetTransactionsQuery(
    int Page = 1,
    int PageSize = 10,
    Guid? EmployeeUserId = null,
    string? Type = null,
    string? Status = null,
    int? ForMonth = null,
    int? ForYear = null,
    DateTime? FromDate = null,
    DateTime? ToDate = null) : IQuery<AppResponse<PagedResult<PaymentTransactionDto>>>;

public class GetTransactionsHandler(
    IRepository<PaymentTransaction> transactionRepository
) : IQueryHandler<GetTransactionsQuery, AppResponse<PagedResult<PaymentTransactionDto>>>
{
    public async Task<AppResponse<PagedResult<PaymentTransactionDto>>> Handle(GetTransactionsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            Expression<Func<PaymentTransaction, bool>>? filter = null;

            if (request.EmployeeUserId.HasValue || !string.IsNullOrEmpty(request.Type) ||
                !string.IsNullOrEmpty(request.Status) || request.ForMonth.HasValue || request.ForYear.HasValue ||
                request.FromDate.HasValue || request.ToDate.HasValue)
            {
                filter = t =>
                    (!request.EmployeeUserId.HasValue || t.EmployeeUserId == request.EmployeeUserId.Value) &&
                    (string.IsNullOrEmpty(request.Type) || t.Type == request.Type) &&
                    (string.IsNullOrEmpty(request.Status) || t.Status == request.Status) &&
                    (!request.ForMonth.HasValue || t.ForMonth == request.ForMonth.Value) &&
                    (!request.ForYear.HasValue || t.ForYear == request.ForYear.Value) &&
                    (!request.FromDate.HasValue || t.TransactionDate >= request.FromDate.Value) &&
                    (!request.ToDate.HasValue || t.TransactionDate <= request.ToDate.Value);
            }

            var totalCount = await transactionRepository.CountAsync(filter, cancellationToken);

            var items = await transactionRepository.GetAllWithIncludeAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(t => t.TransactionDate),
                includes: q => q.Include(t => t.Employee).Include(t => t.EmployeeUser).Include(t => t.PerformedBy),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var result = new PagedResult<PaymentTransactionDto>(
                items.Adapt<List<PaymentTransactionDto>>(),
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<PaymentTransactionDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<PaymentTransactionDto>>.Error(ex.Message);
        }
    }
}

// Get Transaction by Id Query
public record GetTransactionByIdQuery(Guid Id) : IQuery<AppResponse<PaymentTransactionDto>>;

public class GetTransactionByIdHandler(
    IRepository<PaymentTransaction> transactionRepository
) : IQueryHandler<GetTransactionByIdQuery, AppResponse<PaymentTransactionDto>>
{
    public async Task<AppResponse<PaymentTransactionDto>> Handle(GetTransactionByIdQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var transaction = await transactionRepository.GetByIdAsync(
                request.Id, 
                includeProperties: ["Employee", "EmployeeUser", "PerformedBy"],
                cancellationToken: cancellationToken);
            
            if (transaction == null)
            {
                return AppResponse<PaymentTransactionDto>.Error("Transaction not found");
            }

            return AppResponse<PaymentTransactionDto>.Success(transaction.Adapt<PaymentTransactionDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<PaymentTransactionDto>.Error(ex.Message);
        }
    }
}

// Get Transaction Summary Query
public record GetTransactionSummaryQuery(
    Guid? EmployeeUserId = null,
    int? ForMonth = null,
    int? ForYear = null) : IQuery<AppResponse<TransactionSummaryDto>>;

public class TransactionSummaryDto
{
    public decimal TotalPayments { get; set; }
    public decimal TotalDeductions { get; set; }
    public decimal TotalAdvances { get; set; }
    public decimal TotalBonuses { get; set; }
    public decimal NetAmount { get; set; }
    public int TransactionCount { get; set; }
}

public class GetTransactionSummaryHandler(
    IRepository<PaymentTransaction> transactionRepository
) : IQueryHandler<GetTransactionSummaryQuery, AppResponse<TransactionSummaryDto>>
{
    public async Task<AppResponse<TransactionSummaryDto>> Handle(GetTransactionSummaryQuery request, CancellationToken cancellationToken)
    {
        try
        {
            Expression<Func<PaymentTransaction, bool>>? filter = null;

            if (request.EmployeeUserId.HasValue || request.ForMonth.HasValue || request.ForYear.HasValue)
            {
                filter = t => 
                    (!request.EmployeeUserId.HasValue || t.EmployeeUserId == request.EmployeeUserId.Value) &&
                    (!request.ForMonth.HasValue || t.ForMonth == request.ForMonth.Value) &&
                    (!request.ForYear.HasValue || t.ForYear == request.ForYear.Value);
            }

            var transactions = await transactionRepository.GetAllAsync(filter: filter, cancellationToken: cancellationToken);

            var summary = new TransactionSummaryDto
            {
                TotalPayments = transactions.Where(t => t.Type == "SalaryPayment").Sum(t => t.Amount),
                TotalDeductions = transactions.Where(t => t.Type == "Deduction").Sum(t => t.Amount),
                TotalAdvances = transactions.Where(t => t.Type == "AdvancePayment").Sum(t => t.Amount),
                TotalBonuses = transactions.Where(t => t.Type == "Bonus").Sum(t => t.Amount),
                TransactionCount = transactions.Count
            };

            summary.NetAmount = summary.TotalPayments + summary.TotalBonuses - summary.TotalDeductions - summary.TotalAdvances;

            return AppResponse<TransactionSummaryDto>.Success(summary);
        }
        catch (Exception ex)
        {
            return AppResponse<TransactionSummaryDto>.Error(ex.Message);
        }
    }
}
