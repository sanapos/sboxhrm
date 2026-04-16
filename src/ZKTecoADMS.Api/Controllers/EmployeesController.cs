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
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class EmployeesController(IMediator mediator, IDataScopeService dataScopeService) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<IActionResult> GetEmployees([FromQuery] PaginationRequest request, [FromQuery] string? searchTerm, [FromQuery] string? employmentType, [FromQuery] string? workStatus)
    {
        // Admin xem tất cả, Manager/Employee xem theo phạm vi quản lý
        List<Guid>? subordinateIds = null;
        if (!IsAdmin)
            subordinateIds = await dataScopeService.GetSubordinateEmployeeIdsAsync(CurrentUserId, RequiredStoreId);

        var query = new GetEmployeesQuery
        {
            StoreId = RequiredStoreId,
            PaginationRequest = request,
            SearchTerm = searchTerm,
            EmploymentType = employmentType,
            WorkStatus = workStatus,
            ManagerId = CurrentUserId,
            SubordinateEmployeeIds = subordinateIds
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

    [HttpGet("{id}")]
    public async Task<IActionResult> GetEmployeeById(Guid id)
    {
        var result = await mediator.Send(new GetEmployeeByIdQuery { StoreId = RequiredStoreId, Id = id });
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
            if (innerMsg.Contains("IX_Employees_") || innerMsg.Contains("duplicate key"))
            {
                return Ok(AppResponse<Guid>.Error("Mã nhân viên hoặc email công ty đã tồn tại."));
            }
            return Ok(AppResponse<Guid>.Error($"Lỗi lưu dữ liệu: {innerMsg}"));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<Guid>.Error($"Lỗi tạo nhân viên: {ex.Message}"));
        }
    }

    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<IActionResult> UpdateEmployee(Guid id, [FromBody] UpdateEmployeeCommand command)
    {
        command.StoreId = RequiredStoreId;
        command.Id = id;
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<IActionResult> DeleteEmployee(Guid id)
    {
        var result = await mediator.Send(new DeleteEmployeeCommand { StoreId = RequiredStoreId, Id = id });
        return Ok(result);
    }

    // ─── Export Excel ────────────────────────────────────────────────────────
    [HttpGet("export/excel")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
            var employees = result.Data?.Items ?? [];

            using var workbook = new XLWorkbook();
            var ws = workbook.Worksheets.Add("Nhân viên");

            // Title
            ws.Cell(1, 1).Value = "DANH SÁCH NHÂN VIÊN";
            ws.Range(1, 1, 1, 17).Merge();
            ws.Cell(1, 1).Style.Font.SetBold(true).Font.SetFontSize(16)
                .Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            ws.Cell(2, 1).Value = $"Xuất ngày: {DateTime.Now:dd/MM/yyyy HH:mm}";
            ws.Range(2, 1, 2, 17).Merge();
            ws.Cell(2, 1).Style.Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            // Headers
            var headers = new[]
            {
                "STT", "Mã NV", "Họ và tên", "Giới tính", "Ngày sinh",
                "CCCD/CMND", "Quê quán", "Trình độ học vấn",
                "Số điện thoại", "Email công ty",
                "Phòng ban", "Chức vụ", "Loại HĐ", "Ngày vào làm",
                "Trạng thái", "Ngân hàng", "Số tài khoản"
            };

            int headerRow = 4;
            for (int i = 0; i < headers.Length; i++)
                ws.Cell(headerRow, i + 1).Value = headers[i];

            ws.Range(headerRow, 1, headerRow, headers.Length).Style
                .Font.SetBold(true)
                .Fill.SetBackgroundColor(XLColor.FromHtml("#6366F1"))
                .Font.SetFontColor(XLColor.White)
                .Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center)
                .Border.SetOutsideBorder(XLBorderStyleValues.Thin);

            // Data
            int row = headerRow + 1;
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

            ws.Columns().AdjustToContents();

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
    public async Task<IActionResult> ImportEmployeesExcel([FromBody] List<CreateEmployeeRequest> records)
    {
        if (records == null || records.Count == 0)
            return BadRequest("Không có dữ liệu để import.");

        int imported = 0, failed = 0;
        var errors = new List<string>();

        foreach (var (req, idx) in records.Select((r, i) => (r, i + 1)))
        {
            try
            {
                var command = req.Adapt<CreateEmployeeCommand>();
                command.StoreId = RequiredStoreId;
                command.ManagerId = CurrentUserId;
                var result = await mediator.Send(command);
                if (result.IsSuccess) imported++;
                else { failed++; errors.Add($"Hàng {idx} ({req.EmployeeCode}): {result.Message}"); }
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
            data = new { imported, failed, errors },
            message = $"Import hoàn tất: {imported} thành công, {failed} lỗi."
        });
    }
}
