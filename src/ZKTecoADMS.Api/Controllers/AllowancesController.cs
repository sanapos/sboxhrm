using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Allowances;
using ZKTecoADMS.Application.Queries.Allowances;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Allowances;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AllowancesController(IMediator mediator) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PagedResult<AllowanceDto>>>> GetAllowances(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] AllowanceType? type = null,
        [FromQuery] bool? isActive = null,
        [FromQuery] string? searchTerm = null)
    {
        var query = new GetAllowancesQuery(RequiredStoreId, page, pageSize, type, isActive, searchTerm);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<AllowanceDto>>> GetAllowanceById(Guid id)
    {
        var query = new GetAllowanceByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<AllowanceDto>>> CreateAllowance([FromBody] CreateAllowanceDto request)
    {
        var command = new CreateAllowanceCommand(
            RequiredStoreId,
            request.Name,
            request.Code,
            request.Description,
            request.Type,
            request.Amount,
            request.Currency,
            request.IsTaxable,
            request.IsInsuranceApplicable,
            request.StartDate,
            request.EndDate,
            request.EmployeeIds);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<AllowanceDto>>> UpdateAllowance(Guid id, [FromBody] UpdateAllowanceDto request)
    {
        var command = new UpdateAllowanceCommand(
            RequiredStoreId,
            id,
            request.Name,
            request.Code,
            request.Description,
            request.Type,
            request.Amount,
            request.Currency,
            request.IsTaxable,
            request.IsInsuranceApplicable,
            request.IsActive,
            request.StartDate,
            request.EndDate,
            request.EmployeeIds);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteAllowance(Guid id)
    {
        var command = new DeleteAllowanceCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}
