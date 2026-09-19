using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Application.Constants;

namespace ZKTecoADMS.Api.Authorization;

/// <summary>
/// Route <c>api/pos/stock/{kind}</c> — damage → PosDamageIssues, internal-use → PosInternalUseIssues.
/// PosProducts cùng action vẫn được nhờ implicit grant.
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = true)]
public sealed class RequirePosStockIssueKindAttribute : TypeFilterAttribute
{
    public RequirePosStockIssueKindAttribute(ModulePermissionAction action)
        : base(typeof(RequirePosStockIssueKindFilter))
    {
        Arguments = [action];
    }
}
