using System.Collections.Concurrent;
using System.Reflection;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers.Filters;

/// <summary>
/// Thông điệp lỗi ghép số tiền bằng {x:N0} (invariant → «4,000,000đ») → đổi sang «4.000.000đ»
/// cho khớp app. Chỉ đụng <c>Errors</c> của AppResponse, không đụng dữ liệu trả về.
/// </summary>
public sealed class VnMoneyErrorFilter : IResultFilter
{
    private static readonly ConcurrentDictionary<Type, PropertyInfo?> ErrorsProp = new();

    public void OnResultExecuting(ResultExecutingContext context)
    {
        if (context.Result is not ObjectResult { Value: { } value }) return;
        var prop = ErrorsProp.GetOrAdd(value.GetType(), t =>
            t.IsGenericType && t.GetGenericTypeDefinition() == typeof(AppResponse<>)
                ? t.GetProperty(nameof(AppResponse<object>.Errors))
                : null);
        if (prop?.GetValue(value) is not List<string> { Count: > 0 } errors) return;
        for (var i = 0; i < errors.Count; i++)
            errors[i] = VnMoneyText.Normalize(errors[i]);
    }

    public void OnResultExecuted(ResultExecutedContext context) { }
}
