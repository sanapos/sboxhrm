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
    public sealed record StaffCommissionRow(
        Guid Id, Guid SaleOrderId, string OrderNo, DateTime SaleAt,
        Guid EmployeeId, string EmployeeName, Guid ProductId, string ProductName,
        Guid? ParentComboProductId, string? ComboName,
        decimal Qty, decimal RevenueAmount, string CommissionMode,
        decimal CommissionPercent, decimal CommissionFixed, decimal CommissionAmount,
        decimal ReturnedQty);

    /// <summary>
    /// Dòng hoa hồng trong kỳ. Hàng khách đã trả lại → hoa hồng / doanh thu / SL giảm theo tỷ lệ SL trả của dòng bán
    /// (hủy phiếu trả thì tự hồi lại vì tính từ sổ trả hàng). Hoa hồng «mỗi buổi» của liệu trình giữ nguyên — buổi đã làm.
    /// </summary>
    async Task<List<StaffCommissionRow>> LoadStaffCommissionRowsAsync(
        Guid storeId, DateTime fromUtc, DateTime toUtc, Guid? employeeId, Guid? productId, CancellationToken ct)
    {
        var q = dbContext.PosSaleCommissionLines.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null
                        && x.SaleOrder != null
                        && x.SaleOrder.Deleted == null
                        && x.SaleOrder.Status == PosSaleOrderStatus.Completed
                        && (x.PerformedAt ?? x.SaleOrder.SaleDate ?? x.SaleOrder.CreatedAt) >= fromUtc
                        && (x.PerformedAt ?? x.SaleOrder.SaleDate ?? x.SaleOrder.CreatedAt) < toUtc);
        if (employeeId.HasValue) q = q.Where(x => x.EmployeeId == employeeId);
        if (productId.HasValue) q = q.Where(x => x.ProductId == productId);

        var raw = await q
            .Select(x => new
            {
                x.Id,
                x.SaleOrderId,
                OrderNo = x.SaleOrder != null ? x.SaleOrder.OrderNo : "",
                SaleAt = x.PerformedAt ?? (x.SaleOrder != null ? x.SaleOrder.CreatedAt : x.CreatedAt),
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
                x.CommissionMode,
                x.CommissionPercent,
                x.CommissionFixed,
                x.CommissionAmount,
                x.SaleOrderLineId,
                LineQty = x.SaleOrderLine != null ? x.SaleOrderLine.Qty : 0m,
                x.SessionTransactionId,
            })
            .OrderBy(x => x.EmployeeName)
            .ThenBy(x => x.SaleAt)
            .ToListAsync(ct);

        var orderIds = raw.Where(x => x.SessionTransactionId == null).Select(x => x.SaleOrderId).Distinct().ToList();
        var returned = orderIds.Count == 0
            ? new Dictionary<Guid, decimal>()
            : await PosSaleReturnLedger.ReturnedQtyByLineAsync(dbContext, storeId, orderIds);

        return raw.Select(x =>
        {
            decimal ret = 0, keep = 1;
            if (x.SessionTransactionId == null && x.SaleOrderLineId is Guid lid
                && x.LineQty > 0 && returned.TryGetValue(lid, out var r) && r > 0)
            {
                ret = Math.Min(r, x.LineQty);
                keep = Math.Max(0, (x.LineQty - ret) / x.LineQty);
            }
            return new StaffCommissionRow(
                x.Id, x.SaleOrderId, x.OrderNo, x.SaleAt, x.EmployeeId, x.EmployeeName,
                x.ProductId, x.ProductName, x.ParentComboProductId, x.ComboName,
                Math.Round(x.Qty * keep, 4), Math.Round(x.RevenueAmount * keep, 0),
                x.CommissionMode.ToString(), x.CommissionPercent, x.CommissionFixed,
                Math.Round(x.CommissionAmount * keep, 0), Math.Round(x.Qty * (1 - keep), 4));
        }).ToList();
    }

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
        var rows = await LoadStaffCommissionRowsAsync(storeId, fromUtc, toUtc, employeeId, productId, ct);

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
        var rows = await LoadStaffCommissionRowsAsync(storeId, fromUtc, toUtc, employeeId, productId, ct);

        using var wb = new XLWorkbook();
        var ws = wb.AddWorksheet("Hoa hong NV");
        var headers = new[]
        {
            "Số HĐ", "Thời gian", "Nhân viên", "Hàng / DV", "Trong combo",
            "SL", "Doanh thu phân bổ", "Cách tính", "%", "Cố định", "Hoa hồng", "SL khách trả"
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
            ws.Cell(r, 5).Value = x.ComboName ?? "";
            ws.Cell(r, 6).Value = x.Qty;
            ws.Cell(r, 7).Value = x.RevenueAmount;
            ws.Cell(r, 8).Value = x.CommissionMode;
            ws.Cell(r, 9).Value = x.CommissionPercent;
            ws.Cell(r, 10).Value = x.CommissionFixed;
            ws.Cell(r, 11).Value = x.CommissionAmount;
            ws.Cell(r, 12).Value = x.ReturnedQty;
            r++;
        }
        ws.SheetView.FreezeRows(1);
        ReportExcelLayout.FinishSheet(ws, 1);
        using var stream = new MemoryStream();
        wb.SaveAs(stream);
        return File(
            stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"POS_HoaHongNV_{DateTime.Now:yyyyMMdd}.xlsx");
    }
}
