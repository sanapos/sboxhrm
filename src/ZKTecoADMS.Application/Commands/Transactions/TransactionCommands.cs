using ZKTecoADMS.Application.DTOs.Transactions;

namespace ZKTecoADMS.Application.Commands.Transactions;

// Create Payment Transaction Command
public record CreatePaymentTransactionCommand(
    Guid? EmployeeUserId,
    Guid? EmployeeId,
    string Type,
    int? ForMonth,
    int? ForYear,
    DateTime TransactionDate,
    decimal Amount,
    string? Description,
    string? PaymentMethod,
    string? Note,
    Guid? AdvanceRequestId,
    Guid? PayslipId,
    Guid? PerformedById) : ICommand<AppResponse<PaymentTransactionDto>>;

public class CreatePaymentTransactionHandler(
    IRepository<PaymentTransaction> transactionRepository,
    IRepository<Employee> employeeRepository
) : ICommandHandler<CreatePaymentTransactionCommand, AppResponse<PaymentTransactionDto>>
{
    public async Task<AppResponse<PaymentTransactionDto>> Handle(CreatePaymentTransactionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Determine EmployeeId: use EmployeeId directly, or fall back to EmployeeUserId as EmployeeId
            var employeeId = request.EmployeeId ?? request.EmployeeUserId;
            if (!employeeId.HasValue || employeeId == Guid.Empty)
            {
                return AppResponse<PaymentTransactionDto>.Error("Employee not found");
            }

            // Verify employee exists
            var employee = await employeeRepository.GetByIdAsync(employeeId.Value, cancellationToken: cancellationToken);
            if (employee == null)
            {
                return AppResponse<PaymentTransactionDto>.Error("Employee not found");
            }

            var transaction = new PaymentTransaction
            {
                EmployeeId = employeeId,
                EmployeeUserId = employee.ApplicationUserId.HasValue && employee.ApplicationUserId != Guid.Empty 
                    ? employee.ApplicationUserId : null,
                Type = request.Type,
                ForMonth = request.ForMonth ?? request.TransactionDate.Month,
                ForYear = request.ForYear ?? request.TransactionDate.Year,
                TransactionDate = request.TransactionDate,
                Amount = request.Amount,
                Description = request.Description,
                PaymentMethod = request.PaymentMethod,
                Note = request.Note,
                AdvanceRequestId = request.AdvanceRequestId,
                PayslipId = request.PayslipId,
                PerformedById = request.PerformedById,
                Status = "Pending"
            };

            var created = await transactionRepository.AddAsync(transaction, cancellationToken);
            var result = await transactionRepository.GetByIdAsync(
                created.Id, 
                [nameof(PaymentTransaction.Employee), nameof(PaymentTransaction.EmployeeUser)], 
                cancellationToken: cancellationToken);
            
            return AppResponse<PaymentTransactionDto>.Success(result!.Adapt<PaymentTransactionDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<PaymentTransactionDto>.Error(ex.Message);
        }
    }
}

// Update Transaction Status Command
public record UpdateTransactionStatusCommand(
    Guid Id,
    string Status,
    Guid? PerformedById) : ICommand<AppResponse<PaymentTransactionDto>>;

public class UpdateTransactionStatusHandler(
    IRepository<PaymentTransaction> transactionRepository
) : ICommandHandler<UpdateTransactionStatusCommand, AppResponse<PaymentTransactionDto>>
{
    public async Task<AppResponse<PaymentTransactionDto>> Handle(UpdateTransactionStatusCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var transaction = await transactionRepository.GetByIdAsync(
                request.Id, 
                [nameof(PaymentTransaction.Employee), nameof(PaymentTransaction.EmployeeUser)], 
                cancellationToken: cancellationToken);
            if (transaction == null)
            {
                return AppResponse<PaymentTransactionDto>.Error("Transaction not found");
            }

            transaction.Status = request.Status;
            transaction.PerformedById = request.PerformedById;

            await transactionRepository.UpdateAsync(transaction, cancellationToken);
            
            return AppResponse<PaymentTransactionDto>.Success(transaction.Adapt<PaymentTransactionDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<PaymentTransactionDto>.Error(ex.Message);
        }
    }
}

// Delete Transaction Command
public record DeletePaymentTransactionCommand(Guid Id) : ICommand<AppResponse<bool>>;

public class DeletePaymentTransactionHandler(
    IRepository<PaymentTransaction> transactionRepository
) : ICommandHandler<DeletePaymentTransactionCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeletePaymentTransactionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var transaction = await transactionRepository.GetByIdAsync(request.Id, cancellationToken: cancellationToken);
            if (transaction == null)
            {
                return AppResponse<bool>.Error("Transaction not found");
            }

            await transactionRepository.DeleteAsync(transaction, cancellationToken);
            
            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}

// Update Payment Transaction Command (edit fields)
public record UpdatePaymentTransactionCommand(
    Guid Id,
    string? Type,
    decimal? Amount,
    string? Description,
    string? Note,
    DateTime? TransactionDate,
    int? ForMonth,
    int? ForYear) : ICommand<AppResponse<PaymentTransactionDto>>;

public class UpdatePaymentTransactionHandler(
    IRepository<PaymentTransaction> transactionRepository
) : ICommandHandler<UpdatePaymentTransactionCommand, AppResponse<PaymentTransactionDto>>
{
    public async Task<AppResponse<PaymentTransactionDto>> Handle(UpdatePaymentTransactionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var transaction = await transactionRepository.GetByIdAsync(
                request.Id,
                [nameof(PaymentTransaction.Employee), nameof(PaymentTransaction.EmployeeUser)],
                cancellationToken: cancellationToken);
            if (transaction == null)
            {
                return AppResponse<PaymentTransactionDto>.Error("Transaction not found");
            }

            if (transaction.Status == "Completed")
            {
                return AppResponse<PaymentTransactionDto>.Error("Cannot edit completed transaction. Please unapprove first.");
            }

            if (request.Type != null) transaction.Type = request.Type;
            if (request.Amount.HasValue) transaction.Amount = request.Amount.Value;
            if (request.Description != null) transaction.Description = request.Description;
            if (request.Note != null) transaction.Note = request.Note;
            if (request.TransactionDate.HasValue) transaction.TransactionDate = request.TransactionDate.Value;
            if (request.ForMonth.HasValue) transaction.ForMonth = request.ForMonth.Value;
            if (request.ForYear.HasValue) transaction.ForYear = request.ForYear.Value;

            await transactionRepository.UpdateAsync(transaction, cancellationToken);

            return AppResponse<PaymentTransactionDto>.Success(transaction.Adapt<PaymentTransactionDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<PaymentTransactionDto>.Error(ex.Message);
        }
    }
}
