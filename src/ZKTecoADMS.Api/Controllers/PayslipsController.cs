using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MediatR;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Payslips.GeneratePayslip;
using ZKTecoADMS.Application.Queries.Payslips.GetEmployeePayslips;
using ZKTecoADMS.Application.Queries.Payslips.GetPayslipById;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PayslipsController(IMediator mediator) : AuthenticatedControllerBase
{
    /// <summary>
    /// Generate a payslip for an employee for the current month
    /// Only managers can generate payslips
    /// </summary>
    [HttpPost("generate")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<PayslipDto>>> GeneratePayslip([FromBody] GeneratePayslipRequest request)
    {
        var command = new GeneratePayslipCommand(
            RequiredStoreId,
            request.EmployeeUserId,
            request.Year,
            request.Month,
            request.Bonus,
            request.Deductions,
            request.Notes
        );
        return Ok(await mediator.Send(command));
    }

    /// <summary>
    /// Get all payslips for a specific employee by user ID
    /// Employees can only view their own payslips, managers can view any employee's payslips
    /// </summary>
    [HttpGet("employee/{employeeUserId}")]
    public async Task<ActionResult<AppResponse<List<PayslipDto>>>> GetEmployeePayslips(Guid employeeUserId)
    {
        // Check if user is viewing their own payslips or is a manager
        var isManagerOrAdmin = IsManager || IsAdmin;
        var currentUserId = CurrentUserId;

        if (!isManagerOrAdmin && currentUserId != employeeUserId)
        {
            return Forbid();
        }

        var query = new GetEmployeePayslipsQuery(RequiredStoreId, employeeUserId, isManagerOrAdmin);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Get my payslips (for the current logged-in user)
    /// </summary>
    [HttpGet("my-payslips")]
    public async Task<ActionResult<AppResponse<List<PayslipDto>>>> GetMyPayslips()
    {
        var query = new GetEmployeePayslipsQuery(RequiredStoreId, CurrentUserId, IsManager);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Get a specific payslip by ID
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult<AppResponse<PayslipDto>>> GetPayslipById(Guid id)
    {
        // Check authorization before querying data
        var isManagerOrAdmin = IsManager || IsAdmin;
        var currentUserId = CurrentUserId;

        var query = new GetPayslipByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);

        if (!result.IsSuccess)
        {
            return NotFound(result);
        }

        if (!isManagerOrAdmin && currentUserId != result.Data?.EmployeeUserId)
        {
            return Forbid();
        }

        return Ok(result);
    }
}
