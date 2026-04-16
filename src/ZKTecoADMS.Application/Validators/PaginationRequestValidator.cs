using ZKTecoADMS.Application.Models;
using FluentValidation;
using FluentValidation.Validators;

namespace ZKTecoADMS.Application.Validators;

public class PaginationRequestValidator<T, TRequest> : IPropertyValidator<T, TRequest> where T : class where TRequest : PaginationRequest
{
    public string Name => "PaginationRequestValidator";

    public string GetDefaultMessageTemplate(string errorCode)
    {
        return "PageNumber and PageSize must be greater than 0, and SortOrder must be 'asc' or 'desc'";
    }

    public bool IsValid(ValidationContext<T> context, TRequest value)
    {
        var validSortOrder = string.IsNullOrEmpty(value.SortOrder) || 
                           value.SortOrder.Equals("asc", StringComparison.OrdinalIgnoreCase) || 
                           value.SortOrder.Equals("desc", StringComparison.OrdinalIgnoreCase);
                           
        return value.PageNumber > 0 && value.PageSize > 0 && validSortOrder;
    }
}