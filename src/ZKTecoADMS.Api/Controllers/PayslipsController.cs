using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MediatR;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Queries.Payslips.GetEmployeePayslips;
using ZKTecoADMS.Application.Queries.Payslips.GetPayslipById;
using ZKTecoADMS.Application.Queries.Payslips.GetStorePayslips;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PayslipsController(IMediator mediator) : AuthenticatedControllerBase
{
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
    /// Get all payslips in the current store for a given period (year + optional month).
    /// Manager/Admin only. Used by payroll report dashboard.
    /// </summary>
    [HttpGet("store")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<List<PayslipDto>>>> GetStorePayslips(
        [FromQuery] int year,
        [FromQuery] int? month)
    {
        var query = new GetStorePayslipsQuery(RequiredStoreId, year, month);
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
