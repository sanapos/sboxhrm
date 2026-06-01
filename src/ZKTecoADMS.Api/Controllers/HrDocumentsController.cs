using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.HrDocuments.CreateHrDocument;
using ZKTecoADMS.Application.Commands.HrDocuments.UpdateHrDocument;
using ZKTecoADMS.Application.Commands.HrDocuments.DeleteHrDocument;
using ZKTecoADMS.Application.Queries.HrDocuments.GetHrDocuments;
using ZKTecoADMS.Application.Queries.HrDocuments.GetExpiringDocuments;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.HrDocuments;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/hr-documents")]
public class HrDocumentsController(IMediator mediator) : AuthenticatedControllerBase
{
    /// <summary>
    /// Láº¥y danh sÃ¡ch tÃ i liá»‡u HR
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("HrDocument", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PagedResult<HrDocumentDto>>>> GetHrDocuments(
        [FromQuery] PaginationRequest request,
        [FromQuery] Guid? employeeUserId = null,
        [FromQuery] Guid? employeeId = null,
        [FromQuery] HrDocumentType? documentType = null,
        [FromQuery] bool? expiredOnly = null,
        [FromQuery] bool? expiringOnly = null,
        [FromQuery] string? searchTerm = null)
    {
        var query = new GetHrDocumentsQuery(
            RequiredStoreId,
            request,
            employeeUserId,
            employeeId,
            documentType,
            expiredOnly,
            expiringOnly,
            searchTerm);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Láº¥y danh sÃ¡ch tÃ i liá»‡u sáº¯p háº¿t háº¡n
    /// </summary>
    [HttpGet("expiring")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("HrDocument", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ExpiringDocumentDto>>>> GetExpiringDocuments(
        [FromQuery] int daysAhead = 30)
    {
        var query = new GetExpiringDocumentsQuery(RequiredStoreId, daysAhead);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Táº¡o tÃ i liá»‡u má»›i
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("HrDocument", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<Guid>>> CreateHrDocument(
        [FromBody] CreateHrDocumentDto request)
    {
        var command = new CreateHrDocumentCommand(
            RequiredStoreId,
            CurrentUserId,
            request.EmployeeUserId,
            request.EmployeeId,
            request.Name,
            request.Description,
            request.DocumentType,
            request.FilePath,
            request.FileName,
            request.ContentType,
            request.FileSize,
            request.EffectiveDate,
            request.ExpiryDate,
            request.DocumentNumber,
            request.IssuedBy,
            request.Notes);

        var result = await mediator.Send(command);
        return Ok(result);
    }

    /// <summary>
    /// Cáº­p nháº­t tÃ i liá»‡u
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("HrDocument", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> UpdateHrDocument(
        Guid id,
        [FromBody] UpdateHrDocumentDto request)
    {
        var command = new UpdateHrDocumentCommand(
            RequiredStoreId,
            id,
            request.Name,
            request.Description,
            request.DocumentType,
            request.EffectiveDate,
            request.ExpiryDate,
            request.DocumentNumber,
            request.IssuedBy,
            request.Notes);

        var result = await mediator.Send(command);
        return Ok(result);
    }

    /// <summary>
    /// XÃ³a tÃ i liá»‡u
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("HrDocument", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteHrDocument(Guid id)
    {
        var command = new DeleteHrDocumentCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}

