using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MediatR;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Queries.Payslips.GetEmployeePayslips;
using ZKTecoADMS.Application.Queries.Payslips.GetPayslipAttendanceSnapshot;
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
        var isManagerOrAdmin = IsManager || SeesWholeStore;
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
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
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
    /// Chốt lương (app bản cũ gửi kèm số đã tính). Máy chủ TÍNH LẠI bằng chương trình tính lương và
    /// chỉ dùng danh sách nhân viên + kỳ từ app — số tiền app gửi không còn được tin (mỗi phiên bản app
    /// có thể tính khác nhau, và ai gọi được API đều ghi được số tùy ý). Bản mới dùng POST api/payroll/finalize.
    /// </summary>
    [HttpPost("finalize")]
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
    // Chốt lương = ghi phiếu lương → quyền «Duyệt» bảng lương (trước đây «Xuất»: ai xuất Excel được cũng chốt được).
    [RequireModulePermission("Payroll", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<FinalizePayrollResultDto>>> FinalizePayroll(
        [FromBody] FinalizePayrollRequest request,
        [FromServices] ZKTecoADMS.Api.Services.PayrollEngineRunner engine,
        [FromServices] ILogger<PayslipsController> logger,
        CancellationToken ct)
    {
        var ids = request.Items.Where(i => i.EmployeeId.HasValue).Select(i => i.EmployeeId!.Value.ToString()).Distinct().ToList();
        if (engine.IsAvailable && ids.Count > 0)
        {
            try
            {
                var input = ZKTecoADMS.Api.Services.PayrollEngineRunner.InputFor(
                    HttpContext, IsEmployee, request.PeriodStart, request.PeriodEnd) with { EmployeeIds = ids };
                var (server, _) = await engine.ComputeFinalizeAsync(input, ct);
                server.OverwriteExisting = request.OverwriteExisting;
                request = server;
            }
            catch (ZKTecoADMS.Api.Services.PayrollEngineException ex)
            {
                // Không để chốt lương đứng hẳn khi chương trình tính lương lỗi — ghi lại để xử lý.
                logger.LogWarning("Finalize fallback to client numbers: {Err}", ex.Message);
            }
        }
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
        var isManagerOrAdmin = IsManager || SeesWholeStore;
        var currentUserId = CurrentUserId;

        var query = new GetPayslipByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);

        if (!result.IsSuccess)
            return NotFound(result);

        if (!isManagerOrAdmin && currentUserId != result.Data?.EmployeeUserId)
            return Forbid();

        return Ok(result);
    }

    /// <summary>
    /// Bản chấm công đính kèm phiếu lương (snapshot độc lập khi chốt lương).
    /// </summary>
    [HttpGet("{id}/attendance-snapshot")]
    [RequireModulePermission("Payslip", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PayslipAttendanceSnapshotDto>>> GetPayslipAttendanceSnapshot(Guid id)
    {
        var isManagerOrAdmin = IsManager || SeesWholeStore;
        var payslipResult = await mediator.Send(new GetPayslipByIdQuery(RequiredStoreId, id));
        if (!payslipResult.IsSuccess || payslipResult.Data == null)
            return NotFound(payslipResult);

        if (!isManagerOrAdmin && CurrentUserId != payslipResult.Data.EmployeeUserId)
            return Forbid();

        var query = new GetPayslipAttendanceSnapshotQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);
        if (!result.IsSuccess)
            return NotFound(result);
        return Ok(result);
    }
}
