using System.Text.Json;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Commands.Payslips.FinalizePayroll;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Payslips;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Bảng lương do MÁY CHỦ tính (cùng công thức với app — gói payroll_engine) và chốt lương bằng số máy chủ tính.
/// Trước đây app tự tính rồi gửi số lên chốt: mỗi máy / phiên bản app có thể ra số khác nhau,
/// và ai gọi được API chốt lương đều ghi được bất kỳ số nào vào phiếu lương.
/// </summary>
[ApiController]
[Authorize]
[Route("api/payroll")]
public class PayrollController(PayrollEngineRunner engine, IMediator mediator) : AuthenticatedControllerBase
{
    public sealed record FinalizeServerRequest(
        DateTime From,
        DateTime To,
        List<string>? EmployeeIds = null,
        string? BranchId = null,
        string? HeadquarterId = null,
        bool OverwriteExisting = true);

    /// <summary>Bảng lương kỳ [from, to] — tính trên máy chủ.</summary>
    [HttpGet("summary")]
    [RequireModulePermission("Payroll", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Summary(
        [FromQuery] DateTime from, [FromQuery] DateTime to,
        [FromQuery] string? branchId, [FromQuery] string? headquarterId, CancellationToken ct)
    {
        var err = ValidatePeriod(from, to);
        if (err != null) return Ok(AppResponse<object>.Fail(err));
        try
        {
            using var doc = await engine.RunAsync(Input(from, to, branchId, headquarterId), ct);
            var root = doc.RootElement;
            return Ok(AppResponse<object>.Success(new
            {
                rows = root.GetProperty("rows").Clone(),
                notConfiguredSalaryCount = root.TryGetProperty("notConfiguredSalaryCount", out var n) ? n.GetInt32() : 0,
                warnings = root.TryGetProperty("warnings", out var w) ? w.Clone() : default(JsonElement?),
                computedAt = DateTime.UtcNow,
                engine = "server",
            }));
        }
        catch (PayrollEngineException ex)
        {
            return Ok(AppResponse<object>.Fail(ex.Message));
        }
    }

    /// <summary>Chốt lương bằng số máy chủ tự tính (người dùng bấm «Chốt lương»).</summary>
    [HttpPost("finalize")]
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
    // Chốt lương = ghi phiếu lương → quyền «Duyệt» bảng lương (trước đây «Xuất»: ai xuất Excel được cũng chốt được).
    [RequireModulePermission("Payroll", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<FinalizePayrollResultDto>>> Finalize(
        [FromBody] FinalizeServerRequest body, CancellationToken ct)
    {
        var err = ValidatePeriod(body.From, body.To);
        if (err != null) return Ok(AppResponse<FinalizePayrollResultDto>.Error(err));
        try
        {
            var (request, skipped) = await ComputeFinalizeAsync(
                body.From, body.To, body.EmployeeIds, body.BranchId, body.HeadquarterId, ct);
            request.OverwriteExisting = body.OverwriteExisting;
            if (request.Items.Count == 0)
                return Ok(AppResponse<FinalizePayrollResultDto>.Error(skipped.Count > 0
                    ? $"Không có nhân viên hợp lệ để chốt ({skipped.Count} NV chưa có bảng lương)"
                    : "Không có nhân viên để chốt lương"));
            var result = await mediator.Send(new FinalizePayrollCommand(RequiredStoreId, CurrentUserId, request), ct);
            if (result.IsSuccess && result.Data != null && skipped.Count > 0)
                result.Data.Errors.Add($"{skipped.Count} NV chưa có bảng lương — bỏ qua: {string.Join(", ", skipped.Take(5))}{(skipped.Count > 5 ? "…" : "")}");
            return result.IsSuccess ? Ok(result) : BadRequest(result);
        }
        catch (PayrollEngineException ex)
        {
            return Ok(AppResponse<FinalizePayrollResultDto>.Error(ex.Message));
        }
    }

    Task<(FinalizePayrollRequest Request, List<string> Skipped)> ComputeFinalizeAsync(
        DateTime from, DateTime to, IReadOnlyCollection<string>? employeeIds,
        string? branchId, string? headquarterId, CancellationToken ct) =>
        engine.ComputeFinalizeAsync(Input(from, to, branchId, headquarterId) with { EmployeeIds = employeeIds }, ct);

    PayrollEngineInput Input(DateTime from, DateTime to, string? branchId, string? headquarterId) =>
        PayrollEngineRunner.InputFor(HttpContext, IsEmployee, from, to, branchId, headquarterId);

    static string? ValidatePeriod(DateTime from, DateTime to)
    {
        if (from == default || to == default) return "Thiếu kỳ lương";
        if (to.Date < from.Date) return "Kỳ lương không hợp lệ";
        if ((to.Date - from.Date).TotalDays > 62) return "Kỳ lương tối đa 2 tháng";
        return null;
    }
}
