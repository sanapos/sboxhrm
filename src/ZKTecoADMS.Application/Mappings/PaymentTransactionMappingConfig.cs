using ZKTecoADMS.Application.DTOs.Transactions;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Mappings;

public class PaymentTransactionMappingConfig : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        config.NewConfig<PaymentTransaction, PaymentTransactionDto>()
            .Map(dest => dest.Id, src => src.Id)
            .Map(dest => dest.EmployeeUserId, src => src.EmployeeUserId)
            .Map(dest => dest.EmployeeId, src => src.EmployeeId)
            .Map(dest => dest.EmployeeName, src => src.Employee != null 
                ? $"{src.Employee.LastName} {src.Employee.FirstName}".Trim()
                : src.EmployeeUser != null 
                    ? $"{src.EmployeeUser.LastName} {src.EmployeeUser.FirstName}".Trim() 
                    : "")
            .Map(dest => dest.EmployeeCode, src => src.Employee != null 
                ? src.Employee.EmployeeCode 
                : src.EmployeeUser != null && src.EmployeeUser.Employee != null 
                    ? src.EmployeeUser.Employee.EmployeeCode 
                    : "")
            .Map(dest => dest.Type, src => src.Type)
            .Map(dest => dest.ForMonth, src => src.ForMonth)
            .Map(dest => dest.ForYear, src => src.ForYear)
            .Map(dest => dest.TransactionDate, src => src.TransactionDate)
            .Map(dest => dest.Amount, src => src.Amount)
            .Map(dest => dest.Description, src => src.Description)
            .Map(dest => dest.PaymentMethod, src => src.PaymentMethod)
            .Map(dest => dest.Status, src => src.Status)
            .Map(dest => dest.PerformedById, src => src.PerformedById)
            .Map(dest => dest.Note, src => src.Note)
            .Map(dest => dest.AdvanceRequestId, src => src.AdvanceRequestId)
            .Map(dest => dest.PayslipId, src => src.PayslipId)
            .Map(dest => dest.CreatedAt, src => src.CreatedAt)
            .Map(dest => dest.UpdatedAt, src => src.UpdatedAt);

        config.NewConfig<CreatePaymentTransactionDto, PaymentTransaction>()
            .Map(dest => dest.EmployeeUserId, src => src.EmployeeUserId)
            .Map(dest => dest.EmployeeId, src => src.EmployeeId)
            .Map(dest => dest.Type, src => src.Type)
            .Map(dest => dest.ForMonth, src => src.ForMonth)
            .Map(dest => dest.ForYear, src => src.ForYear)
            .Map(dest => dest.TransactionDate, src => src.TransactionDate)
            .Map(dest => dest.Amount, src => src.Amount)
            .Map(dest => dest.Description, src => src.Description)
            .Map(dest => dest.PaymentMethod, src => src.PaymentMethod)
            .Map(dest => dest.Note, src => src.Note)
            .Map(dest => dest.AdvanceRequestId, src => src.AdvanceRequestId)
            .Map(dest => dest.PayslipId, src => src.PayslipId)
            .Map(dest => dest.Status, _ => "Pending");
    }
}
