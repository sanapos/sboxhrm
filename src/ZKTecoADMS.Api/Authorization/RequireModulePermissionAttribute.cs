using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Application.Constants;

namespace ZKTecoADMS.Api.Authorization;

/// <summary>
/// Enforces effective module permission (role + department) on API actions.
/// Returns 403 if the current user lacks the required permission.
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = true)]
public sealed class RequireModulePermissionAttribute : TypeFilterAttribute
{
    public RequireModulePermissionAttribute(string module, ModulePermissionAction action)
        : base(typeof(RequireModulePermissionFilter))
    {
        Arguments = [module, action];
    }
}
