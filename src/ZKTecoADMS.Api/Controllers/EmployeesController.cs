using ClosedXML.Excel;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Commands.Employees.CreateEmployee;
using ZKTecoADMS.Application.Commands.Employees.UpdateEmployee;
using ZKTecoADMS.Application.Commands.Employees.DeleteEmployee;
using ZKTecoADMS.Application.Queries.Employees.GetEmployees;
using ZKTecoADMS.Application.Queries.Employees.GetEmployeeById;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Employees;
using Mapster;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class EmployeesController(IMediator mediator, IDataScopeService dataScopeService, ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Employee", ModulePermissionAction.View)]
    public async Task<IActionResult> GetEmployees(
        [FromQuery] PaginationRequest request,
        [FromQuery] string? searchTerm,
        [FromQuery] string? employmentType,
        [FromQuery] string? workStatus,
        [FromQuery] Guid? branchId,
        [FromQuery] bool includeChildBranches = true)
    {
        // Admin: tất cả. Manager: phạm vi quản lý. Employee: chỉ hồ sơ của mình.
        List<Guid>? subordinateIds = null;
        if (!IsAdmin)
        {
            if (IsEmployee && !IsManager)
            {
                subordinateIds = EmployeeId.HasValue ? [EmployeeId.Value] : [];
            }
            else
            {
                subordinateIds = await dataScopeService.GetSubordinateEmployeeIdsAsync(CurrentUserId, RequiredStoreId);
            }
        }

        List<Guid>? branchIds = null;
        if (branchId.HasValue)
        {
            var set = await BranchQueryHelper.GetBranchIdsIncludingChildrenAsync(
                dbContext, RequiredStoreId, branchId.Value, includeChildBranches);
            branchIds = set.ToList();
        }

        var query = new GetEmployeesQuery
        {
            StoreId = RequiredStoreId,
            PaginationRequest = request,
            SearchTerm = searchTerm,
            EmploymentType = employmentType,
            WorkStatus = workStatus,
            ManagerId = CurrentUserId,
            SubordinateEmployeeIds = subordinateIds,
            BranchId = branchId,
            BranchIds = branchIds,
        };
        
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Get current user's own employee profile
    /// </summary>
    [HttpGet("me")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<IActionResult> GetMyEmployee()
    {
        var employeeId = EmployeeId;
        if (!employeeId.HasValue)
        {
            return Ok(AppResponse<EmployeeDto>.Error("Tài khoản chưa liên kết với nhân viên"));
        }
        var result = await mediator.Send(new GetEmployeeByIdQuery { StoreId = RequiredStoreId, Id = employeeId.Value });
        return Ok(result);
    }

    /// <summary>
    /// Birthday list for the whole company (toàn store, KHÔNG bị giới hạn
    /// theo phân quyền phòng ban). Trả về dữ liệu nhẹ để dashboard hiển thị
    /// "Sinh nhật hôm nay" và "Sinh nhật trong tháng".
    /// </summary>
    [HttpGet("birthdays")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Dashboard", ModulePermissionAction.View)]
    public async Task<IActionResult> GetBirthdays()
    {
        var items = await dbContext.Employees
            .AsNoTracking()
            .Where(e => e.StoreId == RequiredStoreId
                && e.DateOfBirth != null
                && e.ResignationDate == null)
            .Select(e => new
            {
                id = e.Id,
                employeeCode = e.EmployeeCode,
                firstName = e.FirstName,
                lastName = e.LastName,
                department = e.Department,
                departmentId = e.DepartmentId,
                dateOfBirth = e.DateOfBirth,
                photoUrl = e.PhotoUrl,
            })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(items));
    }

    [HttpGet("expiring-contracts")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Dashboard", ModulePermissionAction.View)]
    public async Task<IActionResult> GetExpiringContracts([FromQuery] int daysAhead = 30)
    {
        var today = DateTime.UtcNow.Date;
        var futureDate = today.AddDays(daysAhead);
        var items = await dbContext.Employees
            .AsNoTracking()
            .Where(e => e.StoreId == RequiredStoreId
                && e.ResignationDate == null
                && e.ContractEndDate.HasValue)
            .OrderBy(e => e.ContractEndDate)
            .Select(e => new
            {
                id = e.Id,
                employeeCode = e.EmployeeCode,
                firstName = e.FirstName,
                lastName = e.LastName,
                department = e.Department,
                departmentId = e.DepartmentId,
                photoUrl = e.PhotoUrl,
                contractEndDate = e.ContractEndDate,
                daysUntilExpiry = (int)(e.ContractEndDate!.Value.Date - today).TotalDays,
            })
            .ToListAsync();
        // Split: expiring (within daysAhead) vs already expired
        var expiring = items.Where(x => x.daysUntilExpiry >= 0 && x.daysUntilExpiry <= daysAhead).ToList();
        var expired  = items.Where(x => x.daysUntilExpiry < 0).ToList();
        return Ok(AppResponse<object>.Success(new { expiring, expired }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("Employee", ModulePermissionAction.View)]
    public async Task<IActionResult> GetEmployeeById(Guid id)
    {
        var result = await mediator.Send(new GetEmployeeByIdQuery { StoreId = RequiredStoreId, Id = id });
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Employee", ModulePermissionAction.Create)]
    public async Task<IActionResult> CreateEmployee([FromBody] CreateEmployeeRequest request)
    {
        try
        {
            var command = request.Adapt<CreateEmployeeCommand>();
            command.StoreId = RequiredStoreId;
            command.ManagerId = CurrentUserId;

            var result = await mediator.Send(command);
            return Ok(result);
        }
        catch (Microsoft.EntityFrameworkCore.DbUpdateException dbEx)
        {
            var innerMsg = dbEx.InnerException?.Message ?? dbEx.Message;
            if (innerMsg.Contains("IX_Employees_", StringComparison.OrdinalIgnoreCase)
                || innerMsg.Contains("duplicate key", StringComparison.OrdinalIgnoreCase))
            {
                if (innerMsg.Contains("CompanyEmail", StringComparison.OrdinalIgnoreCase))
                {
                    return Ok(AppResponse<Guid>.Error(
                        "Email cong ty da ton tai. Vui long nhap email khac."));
                }
                if (innerMsg.Contains("EmployeeCode", StringComparison.OrdinalIgnoreCase))
                {
                    return Ok(AppResponse<Guid>.Error(
                        "Ma nhan vien da ton tai trong cua hang."));
                }
                return Ok(AppResponse<Guid>.Error(
                    "Ma nhan vien hoac email cong ty da ton tai."));
            }
            return Ok(AppResponse<Guid>.Error($"Loi luu du lieu: {innerMsg}"));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<Guid>.Error($"Lỗi tạo nhân viên: {ex.Message}"));
        }
    }

    [HttpPut("{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Employee", ModulePermissionAction.Edit)]
    public async Task<IActionResult> UpdateEmployee(Guid id, [FromBody] UpdateEmployeeCommand command)
    {
        command.StoreId = RequiredStoreId;
        command.Id = id;
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Employee", ModulePermissionAction.Delete)]
    public async Task<IActionResult> DeleteEmployee(Guid id)
    {
        var result = await mediator.Send(new DeleteEmployeeCommand { StoreId = RequiredStoreId, Id = id });
        return Ok(result);
    }

    // ─── Export Excel ────────────────────────────────────────────────────────
    [HttpGet("export/excel")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Employee", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportEmployeesExcel()
    {
        try
        {
            var query = new GetEmployeesQuery
            {
                StoreId = RequiredStoreId,
                ManagerId = CurrentUserId,
                SubordinateEmployeeIds = IsAdmin ? null : await dataScopeService.GetSubordinateEmployeeIdsAsync(CurrentUserId, RequiredStoreId),
                PaginationRequest = new PaginationRequest { PageNumber = 1, PageSize = 10000 }
            };
            var result = await mediator.Send(query);
            var employees = (result.Data?.Items ?? []).ToList();

            using var workbook = new XLWorkbook();
            var ws = workbook.Worksheets.Add("Nhân viên");

            var headers = new[]
            {
                "STT", "Mã NV", "Họ và tên", "Giới tính", "Ngày sinh",
                "CCCD/CMND", "Quê quán", "Trình độ học vấn",
                "Số điện thoại", "Email công ty",
                "Phòng ban", "Chức vụ", "Loại HĐ", "Ngày vào làm",
                "Trạng thái", "Ngân hàng", "Số tài khoản"
            };

            var meta = ReportExcelMeta.FromUser(
                User, "DANH SÁCH NHÂN VIÊN", null, null,
                new[] { $"Tổng nhân viên: {employees.Count}" }, employees.Count);
            var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
            ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

            int row = dataStartRow;
            int stt = 1;
            foreach (var e in employees)
            {
                ws.Cell(row, 1).Value = stt++;
                ws.Cell(row, 2).Value = e.EmployeeCode;
                ws.Cell(row, 3).Value = e.FullName;
                ws.Cell(row, 4).Value = e.Gender ?? "";
                ws.Cell(row, 5).Value = e.DateOfBirth?.ToString("dd/MM/yyyy") ?? "";
                ws.Cell(row, 6).Value = e.NationalIdNumber ?? "";
                ws.Cell(row, 7).Value = e.Hometown ?? "";
                ws.Cell(row, 8).Value = e.EducationLevel ?? "";
                ws.Cell(row, 9).Value = e.PhoneNumber ?? "";
                ws.Cell(row, 10).Value = e.CompanyEmail ?? "";
                ws.Cell(row, 11).Value = e.Department ?? "";
                ws.Cell(row, 12).Value = e.Position ?? "";
                ws.Cell(row, 13).Value = e.EmploymentType.ToString();
                ws.Cell(row, 14).Value = e.JoinDate?.ToString("dd/MM/yyyy") ?? "";
                ws.Cell(row, 15).Value = e.WorkStatus.ToString();
                ws.Cell(row, 16).Value = e.BankName ?? "";
                ws.Cell(row, 17).Value = e.BankAccountNumber ?? "";

                if (row % 2 == 0)
                    ws.Range(row, 1, row, headers.Length).Style.Fill.SetBackgroundColor(XLColor.FromHtml("#F5F5FF"));

                row++;
            }

            ReportExcelLayout.FinishSheet(ws, headerRow);

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);

            return File(stream.ToArray(),
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                $"nhan_vien_{DateTime.Now:yyyyMMdd_HHmmss}.xlsx");
        }
        catch (Exception ex)
        {
            return BadRequest($"Export thất bại: {ex.Message}");
        }
    }

    // ─── Import Excel ────────────────────────────────────────────────────────
    [HttpPost("import/excel")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Employee", ModulePermissionAction.Create)]
    public async Task<IActionResult> ImportEmployeesExcel([FromBody] List<CreateEmployeeRequest> records)
    {
        if (records == null || records.Count == 0)
            return BadRequest(new { isSuccess = false, message = "Không có dữ liệu để import." });

        int imported = 0, updated = 0, failed = 0;
        var errors = new List<string>();
        var storeId = RequiredStoreId;

        foreach (var (req, idx) in records.Select((r, i) => (r, i + 1)))
        {
            try
            {
                var existing = await dbContext.Employees
                    .AsNoTracking()
                    .FirstOrDefaultAsync(e => e.StoreId == storeId && e.EmployeeCode == req.EmployeeCode);

                if (existing != null)
                {
                    var updateCmd = req.Adapt<UpdateEmployeeCommand>();
                    updateCmd.Id = existing.Id;
                    updateCmd.StoreId = storeId;
                    updateCmd.ManagerId = CurrentUserId;
                    if (!Enum.IsDefined(typeof(EmployeeWorkStatus), updateCmd.WorkStatus))
                        updateCmd.WorkStatus = existing.WorkStatus;
                    if (IsPlaceholderImportEmail(req.EmployeeCode, req.CompanyEmail))
                        updateCmd.CompanyEmail = existing.CompanyEmail;
                    var updateResult = await mediator.Send(updateCmd);
                    if (updateResult.IsSuccess) updated++;
                    else
                    {
                        failed++;
                        errors.Add($"Hàng {idx} ({req.EmployeeCode}): {updateResult.Message}");
                    }
                }
                else
                {
                    var command = req.Adapt<CreateEmployeeCommand>();
                    command.StoreId = storeId;
                    command.ManagerId = CurrentUserId;
                    var result = await mediator.Send(command);
                    if (result.IsSuccess) imported++;
                    else { failed++; errors.Add($"Hàng {idx} ({req.EmployeeCode}): {result.Message}"); }
                }
            }
            catch (Exception ex)
            {
                failed++;
                errors.Add($"Hàng {idx} ({req.EmployeeCode}): {ex.Message}");
            }
        }

        return Ok(new
        {
            isSuccess = true,
            data = new { imported, updated, failed, errors },
            message = $"Import hoàn tất: {imported} mới, {updated} cập nhật, {failed} lỗi."
        });
    }

    static bool IsPlaceholderImportEmail(string employeeCode, string? companyEmail)
    {
        if (string.IsNullOrWhiteSpace(companyEmail)) return true;
        return string.Equals(
            companyEmail.Trim(),
            $"{employeeCode.Trim()}@company.com",
            StringComparison.OrdinalIgnoreCase);
    }
}
