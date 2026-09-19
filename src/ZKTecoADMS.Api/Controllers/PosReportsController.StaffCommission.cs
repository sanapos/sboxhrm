using ClosedXML.Excel;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosReportsController
{
    [HttpGet("staff-commission")]
    [RequireModulePermission("PosReportStaffCommission", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStaffCommission(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] Guid? employeeId,
        [FromQuery] Guid? productId,
        CancellationToken ct = default)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, null);
        var (fromUtc, toUtc, _, _) = ResolvePosRange(from, to, hour, defaultLookbackDays: 7);

        var q = dbContext.PosSaleCommissionLines.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null
                        && x.SaleOrder != null
                        && x.SaleOrder.Deleted == null
                        && x.SaleOrder.Status == PosSaleOrderStatus.Completed
                        && (x.SaleOrder.SaleDate ?? x.SaleOrder.CreatedAt) >= fromUtc
                        && (x.SaleOrder.SaleDate ?? x.SaleOrder.CreatedAt) < toUtc);
        if (employeeId.HasValue) q = q.Where(x => x.EmployeeId == employeeId);
        if (productId.HasValue) q = q.Where(x => x.ProductId == productId);

        var rows = await q
            .Select(x => new
            {
                x.Id,
                x.SaleOrderId,
                OrderNo = x.SaleOrder != null ? x.SaleOrder.OrderNo : "",
                SaleAt = x.SaleOrder != null ? x.SaleOrder.CreatedAt : x.CreatedAt,
                x.EmployeeId,
                x.EmployeeName,
                x.ProductId,
                x.ProductName,
                x.ParentComboProductId,
                ComboName = x.ParentComboProductId != null && x.SaleOrderLine != null
                    ? x.SaleOrderLine.ProductName
                    : (string?)null,
                x.Qty,
                x.RevenueAmount,
                CommissionMode = x.CommissionMode.ToString(),
                x.CommissionPercent,
                x.CommissionFixed,
                x.CommissionAmount,
            })
            .OrderBy(x => x.EmployeeName)
            .ThenBy(x => x.SaleAt)
            .ToListAsync(ct);

        var byStaff = rows
            .GroupBy(x => new { x.EmployeeId, x.EmployeeName })
            .Select(g => new
            {
                employeeId = g.Key.EmployeeId,
                employeeName = g.Key.EmployeeName,
                orderCount = g.Select(x => x.SaleOrderId).Distinct().Count(),
                qty = g.Sum(x => x.Qty),
                revenue = g.Sum(x => x.RevenueAmount),
                commission = g.Sum(x => x.CommissionAmount),
            })
            .OrderByDescending(x => x.commission)
            .ToList();

        var byProduct = rows
            .GroupBy(x => new { x.ProductId, x.ProductName })
            .Select(g => new
            {
                productId = g.Key.ProductId,
                productName = g.Key.ProductName,
                qty = g.Sum(x => x.Qty),
                revenue = g.Sum(x => x.RevenueAmount),
                commission = g.Sum(x => x.CommissionAmount),
            })
            .OrderByDescending(x => x.commission)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromUtc,
            to = toUtc,
            totalRevenue = rows.Sum(x => x.RevenueAmount),
            totalCommission = rows.Sum(x => x.CommissionAmount),
            staffCount = byStaff.Count,
            lineCount = rows.Count,
            byStaff,
            byProduct,
            lines = rows,
        }));
    }

    [HttpGet("staff-commission/excel")]
    [RequireModulePermission("PosReportStaffCommission", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportStaffCommissionExcel(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] Guid? employeeId,
        [FromQuery] Guid? productId,
        CancellationToken ct = default)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, null);
        var (fromUtc, toUtc, _, _) = ResolvePosRange(from, to, hour, defaultLookbackDays: 7);
        var q = dbContext.PosSaleCommissionLines.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null
                        && x.SaleOrder != null
                        && x.SaleOrder.Deleted == null
                        && x.SaleOrder.Status == PosSaleOrderStatus.Completed
                        && (x.SaleOrder.SaleDate ?? x.SaleOrder.CreatedAt) >= fromUtc
                        && (x.SaleOrder.SaleDate ?? x.SaleOrder.CreatedAt) < toUtc);
        if (employeeId.HasValue) q = q.Where(x => x.EmployeeId == employeeId);
        if (productId.HasValue) q = q.Where(x => x.ProductId == productId);
        var rows = await q
            .Select(x => new
            {
                OrderNo = x.SaleOrder != null ? x.SaleOrder.OrderNo : "",
                SaleAt = x.SaleOrder != null ? x.SaleOrder.CreatedAt : x.CreatedAt,
                x.EmployeeName,
                x.ProductName,
                ComboName = x.ParentComboProductId != null && x.SaleOrderLine != null
                    ? x.SaleOrderLine.ProductName
                    : "",
                x.Qty,
                x.RevenueAmount,
                Mode = x.CommissionMode.ToString(),
                x.CommissionPercent,
                x.CommissionFixed,
                x.CommissionAmount,
            })
            .OrderBy(x => x.EmployeeName)
            .ThenBy(x => x.SaleAt)
            .ToListAsync(ct);

        using var wb = new XLWorkbook();
        var ws = wb.AddWorksheet("Hoa hong NV");
        var headers = new[]
        {
            "Số HĐ", "Thời gian", "Nhân viên", "Hàng / DV", "Trong combo",
            "SL", "Doanh thu phân bổ", "Cách tính", "%", "Cố định", "Hoa hồng"
        };
        for (var i = 0; i < headers.Length; i++)
            ws.Cell(1, i + 1).Value = headers[i];
        var r = 2;
        foreach (var x in rows)
        {
            ws.Cell(r, 1).Value = x.OrderNo;
            ws.Cell(r, 2).Value = x.SaleAt;
            ws.Cell(r, 3).Value = x.EmployeeName;
            ws.Cell(r, 4).Value = x.ProductName;
            ws.Cell(r, 5).Value = x.ComboName;
            ws.Cell(r, 6).Value = x.Qty;
            ws.Cell(r, 7).Value = x.RevenueAmount;
            ws.Cell(r, 8).Value = x.Mode;
            ws.Cell(r, 9).Value = x.CommissionPercent;
            ws.Cell(r, 10).Value = x.CommissionFixed;
            ws.Cell(r, 11).Value = x.CommissionAmount;
            r++;
        }
        ws.SheetView.FreezeRows(1);
        ws.Columns().AdjustToContents();
        using var stream = new MemoryStream();
        wb.SaveAs(stream);
        return File(
            stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"POS_HoaHongNV_{DateTime.Now:yyyyMMdd}.xlsx");
    }
}
