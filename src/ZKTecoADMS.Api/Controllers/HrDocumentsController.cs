using Microsoft.AspNetCore.Authorization;
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
    /// Lấy danh sách tài liệu HR
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<HrDocumentDto>>>> GetHrDocuments(
        [FromQuery] PaginationRequest request,
        [FromQuery] Guid? employeeUserId = null,
        [FromQuery] HrDocumentType? documentType = null,
        [FromQuery] bool? expiredOnly = null,
        [FromQuery] bool? expiringOnly = null,
        [FromQuery] string? searchTerm = null)
    {
        var query = new GetHrDocumentsQuery(
            RequiredStoreId,
            request,
            employeeUserId,
            documentType,
            expiredOnly,
            expiringOnly,
            searchTerm);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Lấy danh sách tài liệu sắp hết hạn
    /// </summary>
    [HttpGet("expiring")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<ExpiringDocumentDto>>>> GetExpiringDocuments(
        [FromQuery] int daysAhead = 30)
    {
        var query = new GetExpiringDocumentsQuery(RequiredStoreId, daysAhead);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Tạo tài liệu mới
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<Guid>>> CreateHrDocument(
        [FromBody] CreateHrDocumentDto request)
    {
        var command = new CreateHrDocumentCommand(
            RequiredStoreId,
            CurrentUserId,
            request.EmployeeUserId,
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
    /// Cập nhật tài liệu
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
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
    /// Xóa tài liệu
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteHrDocument(Guid id)
    {
        var command = new DeleteHrDocumentCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}
