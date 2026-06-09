using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MediatR;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Queries.Payslips.GetEmployeePayslips;
using ZKTecoADMS.Application.Queries.Payslips.GetPayslipById;
using ZKTecoADMS.Application.Queries.Payslips.GetStorePayslips;
using ZKTecoADMS.Application.Commands.Payslips.FinalizePayroll;
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
    /// </summary>
    [HttpGet("employee/{employeeUserId}")]
    [RequireModulePermission("Payslip", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<PayslipDto>>>> GetEmployeePayslips(Guid employeeUserId)
    {
        var isManagerOrAdmin = IsManager || IsAdmin;
        var currentUserId = CurrentUserId;

        if (!isManagerOrAdmin && currentUserId != employeeUserId)
            return Forbid();

        var query = new GetEmployeePayslipsQuery(RequiredStoreId, employeeUserId, isManagerOrAdmin);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Get my payslips (for the current logged-in user)
    /// </summary>
    [HttpGet("my-payslips")]
    [RequireModulePermission("Payslip", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<PayslipDto>>>> GetMyPayslips()
    {
        var query = new GetEmployeePayslipsQuery(RequiredStoreId, CurrentUserId, IsManager);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Search payslips in the current store with optional filters.
    /// Manager/Admin only.
    /// </summary>
    [HttpGet("store")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Payslip", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<PayslipDto>>>> GetStorePayslips(
        [FromQuery] int? year,
        [FromQuery] int? month,
        [FromQuery] Guid? employeeUserId,
        [FromQuery] string? department,
        [FromQuery] DateTime? periodStartFrom,
        [FromQuery] DateTime? periodEndTo)
    {
        var query = new GetStorePayslipsQuery(
            RequiredStoreId, year, month, employeeUserId, department, periodStartFrom, periodEndTo);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Chốt lương — tạo/cập nhật phiếu lương từ dữ liệu tổng hợp lương đã tính.
    /// </summary>
    [HttpPost("finalize")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Payroll", ModulePermissionAction.Export)]
    public async Task<ActionResult<AppResponse<FinalizePayrollResultDto>>> FinalizePayroll(
        [FromBody] FinalizePayrollRequest request)
    {
        var command = new FinalizePayrollCommand(RequiredStoreId, CurrentUserId, request);
        var result = await mediator.Send(command);
        if (!result.IsSuccess)
            return BadRequest(result);
        return Ok(result);
    }

    /// <summary>
    /// Get a specific payslip by ID
    /// </summary>
    [HttpGet("{id}")]
    [RequireModulePermission("Payslip", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PayslipDto>>> GetPayslipById(Guid id)
    {
        var isManagerOrAdmin = IsManager || IsAdmin;
        var currentUserId = CurrentUserId;

        var query = new GetPayslipByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);

        if (!result.IsSuccess)
            return NotFound(result);

        if (!isManagerOrAdmin && currentUserId != result.Data?.EmployeeUserId)
            return Forbid();

        return Ok(result);
    }
}
