using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.Models;
using FluentValidation;
using MediatR;
using System.Reflection;

namespace ZKTecoADMS.Application.Behaviours;

public class ValidationBehavior<TRequest, TResponse>(IEnumerable<IValidator<TRequest>> validators)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IRequest<TResponse>
{
    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken cancellationToken)
    {
        var context = new ValidationContext<TRequest>(request);

        var validationResults = await Task.WhenAll(validators.Select(v => v.ValidateAsync(context, cancellationToken)));

        var failures = validationResults.Where(result => result.Errors.Any()).SelectMany(r => r.Errors);

        if (failures.Any())
        {
            var errorMessages = failures.Select(f => f.ErrorMessage).ToList();
            
            // Check if TResponse is AppResponse<T>
            if (IsAppResponseType(typeof(TResponse)))
            {
                return CreateAppResponseError<TResponse>(errorMessages);
            }
            
            // Fallback to throwing exception for non-AppResponse types
            throw new ValidationException(failures);
        }

        return await next(cancellationToken);
    }

    private static bool IsAppResponseType(Type type)
    {
        return type.IsGenericType && type.GetGenericTypeDefinition() == typeof(AppResponse<>);
    }

    private static TResponse CreateAppResponseError<TResponse>(IEnumerable<string> errorMessages)
    {
        var responseType = typeof(TResponse);
        
        // Get the AppResponse<T>.Error method
        var errorMethod = responseType.GetMethod("Error", new[] { typeof(IEnumerable<string>) });
        
        if (errorMethod != null)
        {
            var result = errorMethod.Invoke(null, new object[] { errorMessages });
            return (TResponse)result!;
        }
        
        // Fallback: create instance manually
        var instance = Activator.CreateInstance<TResponse>();
        var isSuccessProperty = responseType.GetProperty("IsSuccess");
        var errorsProperty = responseType.GetProperty("Errors");
        
        isSuccessProperty?.SetValue(instance, false);
        errorsProperty?.SetValue(instance, errorMessages.ToList());
        
        return instance;
    }
}