using ZKTecoADMS.Application.Constants;

namespace ZKTecoADMS.Api.Authorization;

/// <summary>
/// Allows access when the user has the required action on ANY of the listed modules.
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = false)]
public sealed class RequireAnyModulePermissionAttribute : TypeFilterAttribute
{
    public RequireAnyModulePermissionAttribute(ModulePermissionAction action, params string[] modules)
        : base(typeof(RequireAnyModulePermissionFilter))
    {
        Arguments = [modules, action];
    }
}
