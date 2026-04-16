using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using Mapster;
using ZKTecoADMS.Application.Commands.Benefits.AssignEmployee;
using ZKTecoADMS.Application.Commands.Benefits.Create;
using ZKTecoADMS.Application.Commands.Benefits.Delete;
using ZKTecoADMS.Application.Commands.Benefits.Update;
using ZKTecoADMS.Application.DTOs.Benefits;
using ZKTecoADMS.Application.Queries.Benefits.GetBenefitById;
using ZKTecoADMS.Application.Queries.Benefits.GetBenefits;
using ZKTecoADMS.Application.Queries.Benefits.GetEmployeeBenefit;
using ZKTecoADMS.Application.Queries.Benefits.GetEmployeeBenefits;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class BenefitsController(IMediator mediator) : AuthenticatedControllerBase
{
    /// <summary>
    /// Get all salary profiles
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<List<BenefitDto>>>> GetAllProfiles([FromQuery] int? salaryRateType = null)
    {
        var query = new GetBenefitsQuery(RequiredStoreId, salaryRateType);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Get salary profile by ID
    /// </summary>
    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<BenefitDto>>> GetProfileById(Guid id)
    {
        var query = new GetBenefitByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);
        return result.IsSuccess ? Ok(result) : NotFound(result);
    }

    /// <summary>
    /// Create a new salary profile
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<BenefitDto>>> CreateProfile([FromBody] CreateBenefitRequest request)
    {
        var command = request.Adapt<CreateBenefitCommand>();
        command.StoreId = RequiredStoreId;
        
        var result = await mediator.Send(command);
        return result.IsSuccess ? Ok(result) : BadRequest(result);
    }

    /// <summary>
    /// Update an existing salary profile
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<BenefitDto>>> UpdateProfile(Guid id, [FromBody] UpdateSalaryProfileRequest request)
    {
        var command = request.Adapt<UpdateBenefitCommand>();
        command.StoreId = RequiredStoreId;
        command.Id = id;
                
        var result = await mediator.Send(command);
        return result.IsSuccess ? Ok(result) : BadRequest(result);
    }

    /// <summary>
    /// Delete a salary profile
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteProfile(Guid id)
    {
        var command = new DeleteBenefitCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        return result.IsSuccess ? Ok(result) : BadRequest(result);
    }

    /// <summary>
    /// Assign a salary profile to an employee
    /// </summary>
    [HttpPost("assign")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<EmployeeBenefitDto>>> AssignEmployee([FromBody] AssignSalaryProfileRequest request)
    {
        var command = request.Adapt<AssignBenefitCommand>();
        var result = await mediator.Send(command);

        return result.IsSuccess ? Ok(result) : BadRequest(result);
    }

    /// <summary>
    /// Get active salary profile for an employee
    /// </summary>
    [HttpGet("employees/{employeeId}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<EmployeeBenefitDto>>> GetEmployeeBenefit(Guid employeeId)
    {
        var query = new GetEmployeeBenefitQuery(employeeId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Get active salary profile for an employee
    /// </summary>
    [HttpGet("employees")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<IEnumerable<EmployeeBenefitDto>>>> GetEmployeeBenefits()
    {
        var query = new GetEmployeeBenefitsQuery
        {
            ManagerId = CurrentUserId
        };

        var result = await mediator.Send(query);
        return Ok(result);
    }
}
