using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Application.Constants;

namespace ZKTecoADMS.Api.Authorization;

/// <summary>
/// Allows access when the user has ANY of the listed actions on one module.
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = true)]
public sealed class RequireAnyActionOnModuleAttribute : TypeFilterAttribute
{
    public RequireAnyActionOnModuleAttribute(
        string module,
        ModulePermissionAction action1,
        ModulePermissionAction action2)
        : base(typeof(RequireAnyActionOnModuleFilter))
    {
        Arguments = [module, action1, action2];
    }
}
