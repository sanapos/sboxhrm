using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosReportsController
{
    /// <summary>
    /// Bảng kê VAT đầu vào (hóa đơn mua vào) theo kỳ: mỗi phiếu nhập hoàn thành tách theo thuế suất, phiếu trả hàng NCC
    /// ghi âm (giảm VAT đầu vào). Kỳ lọc theo ngày hóa đơn đầu vào; phiếu chưa nhập ngày hóa đơn thì theo ngày nhập.
    /// Giá trị chưa thuế = tổng tiền dòng (trước chiết khấu cả phiếu) — cùng cơ sở máy chủ dùng tính VAT dòng.
    /// <c>format=excel</c> tải file Excel.
    /// </summary>
    [HttpGet("purchases/input-vat")]
    [RequireModulePermission("PosReportPurchases", ModulePermissionAction.View)]
    public async Task<IActionResult> GetInputVatReport(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] Guid? supplierId = null,
        [FromQuery] string? format = null)
    {
        var storeId = RequiredStoreId;
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, 0, defaultLookbackDays: 30);
        var fromDay = fromVn.Date;
        var toDayEx = toVnEx.Date;
        var bctx = HttpContext.BranchContext();

        var receiptQ = dbContext.PosStockReceipts.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.Status == PosPurchaseReceiptStatus.Completed
                && ((r.InputInvoiceDate != null && r.InputInvoiceDate >= fromDay && r.InputInvoiceDate < toDayEx)
                    || (r.InputInvoiceDate == null && (r.ImportDate ?? r.CreatedAt) >= fromDt && (r.ImportDate ?? r.CreatedAt) < toDt)))
            .ApplyBranchScope(bctx);
        if (supplierId.HasValue) receiptQ = receiptQ.Where(r => r.SupplierId == supplierId);
        var receipts = await receiptQ
            .Select(r => new
            {
                r.Id, r.ReceiptNo, r.InputInvoiceNo, r.InputInvoiceSerial, r.InputInvoiceDate,
                ImportDate = r.ImportDate ?? r.CreatedAt,
                SupplierName = r.Supplier != null ? r.Supplier.Name : null,
                SupplierTaxCode = r.Supplier != null ? r.Supplier.TaxCode : null,
            })
            .ToListAsync();
        var receiptIds = receipts.Select(r => r.Id).ToList();
        var receiptLines = await dbContext.PosStockReceiptLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && receiptIds.Contains(l.ReceiptId))
            .Select(l => new { l.ReceiptId, l.VatRate, l.VatExempt, l.LineTotal, l.VatAmount })
            .ToListAsync();

        var returnQ = dbContext.PosPurchaseReturns.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.Status == PosPurchaseReturnStatus.Completed
                && (r.ReturnDate ?? r.CreatedAt) >= fromDt && (r.ReturnDate ?? r.CreatedAt) < toDt)
            .ApplyBranchScope(bctx);
        if (supplierId.HasValue) returnQ = returnQ.Where(r => r.SupplierId == supplierId);
        var returns = await returnQ
            .Select(r => new
            {
                r.Id, r.ReturnNo, Date = r.ReturnDate ?? r.CreatedAt,
                SourceReceiptNo = r.SourceReceipt != null ? r.SourceReceipt.ReceiptNo : null,
                InvoiceNo = r.SourceReceipt != null ? r.SourceReceipt.InputInvoiceNo : null,
                InvoiceSerial = r.SourceReceipt != null ? r.SourceReceipt.InputInvoiceSerial : null,
                InvoiceDate = r.SourceReceipt != null ? r.SourceReceipt.InputInvoiceDate : null,
                SupplierName = r.Supplier != null ? r.Supplier.Name : null,
                SupplierTaxCode = r.Supplier != null ? r.Supplier.TaxCode : null,
            })
            .ToListAsync();
        var returnIds = returns.Select(r => r.Id).ToList();
        var returnLines = await dbContext.PosPurchaseReturnLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && returnIds.Contains(l.ReturnId))
            .Select(l => new { l.ReturnId, l.VatRate, l.LineTotal, l.VatAmount })
            .ToListAsync();

        static string RateLabel(decimal rate, bool exempt) => exempt ? "KCT" : $"{rate:0.##}%";
        var rows = new List<InputVatRow>();
        foreach (var r in receipts)
            foreach (var g in receiptLines.Where(l => l.ReceiptId == r.Id).GroupBy(l => RateLabel(l.VatExempt ? 0 : l.VatRate, l.VatExempt)))
                rows.Add(new InputVatRow("Receipt", r.ReceiptNo, r.InputInvoiceSerial, r.InputInvoiceNo,
                    r.InputInvoiceDate ?? ReportHelpers.ToVn(r.ImportDate).Date, r.InputInvoiceDate == null,
                    r.SupplierName, r.SupplierTaxCode, g.Key,
                    g.Sum(x => x.LineTotal), g.Sum(x => x.VatExempt ? 0 : x.VatAmount)));
        foreach (var r in returns)
            foreach (var g in returnLines.Where(l => l.ReturnId == r.Id).GroupBy(l => RateLabel(l.VatRate, false)))
                rows.Add(new InputVatRow("Return", r.ReturnNo + (r.SourceReceiptNo != null ? $" (trả {r.SourceReceiptNo})" : ""),
                    r.InvoiceSerial, r.InvoiceNo, ReportHelpers.ToVn(r.Date).Date, false,
                    r.SupplierName, r.SupplierTaxCode, g.Key,
                    -g.Sum(x => x.LineTotal), -g.Sum(x => x.VatAmount)));
        rows = rows.OrderBy(x => x.InvoiceDate).ThenBy(x => x.DocNo).ToList();

        var byRate = rows.GroupBy(x => x.RateLabel)
            .Select(g => new
            {
                rate = g.Key,
                docCount = g.Select(x => x.DocNo).Distinct().Count(),
                amount = g.Sum(x => x.Amount),
                vat = g.Sum(x => x.Vat),
            })
            .OrderBy(x => x.rate == "KCT" ? 1000 : decimal.TryParse(x.rate.TrimEnd('%'), out var v) ? v : 999)
            .ToList();
        var missingInvoice = rows.Where(x => x.Kind == "Receipt" && x.Vat > 0 && string.IsNullOrWhiteSpace(x.InvoiceNo))
            .Select(x => x.DocNo).Distinct().ToList();
        var totalAmount = rows.Sum(x => x.Amount);
        var totalVat = rows.Sum(x => x.Vat);

        if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
        {
            return ReportHelpers.ExcelFile("VAT dau vao",
                ["STT", "Ký hiệu HĐ", "Số HĐ", "Ngày HĐ", "Người bán", "MST người bán", "Giá trị chưa thuế", "Thuế suất", "Thuế GTGT", "Chứng từ"],
                (ws, dataStartRow) =>
                {
                    var row = dataStartRow;
                    var stt = 1;
                    foreach (var x in rows)
                    {
                        ws.Cell(row, 1).Value = stt++;
                        ws.Cell(row, 2).Value = x.InvoiceSerial ?? "";
                        ws.Cell(row, 3).Value = x.InvoiceNo ?? "";
                        ws.Cell(row, 4).Value = x.InvoiceDate.ToString("dd/MM/yyyy");
                        ws.Cell(row, 5).Value = x.SupplierName ?? "";
                        ws.Cell(row, 6).Value = x.SupplierTaxCode ?? "";
                        ReportHelpers.MoneyCell(ws.Cell(row, 7), x.Amount);
                        ws.Cell(row, 8).Value = x.RateLabel;
                        ReportHelpers.MoneyCell(ws.Cell(row, 9), x.Vat);
                        ws.Cell(row, 10).Value = x.DocNo;
                        row++;
                    }
                    ws.Cell(row, 5).Value = "Tổng cộng";
                    ws.Cell(row, 5).Style.Font.Bold = true;
                    ReportHelpers.MoneyCell(ws.Cell(row, 7), totalAmount).Style.Font.Bold = true;
                    ReportHelpers.MoneyCell(ws.Cell(row, 9), totalVat).Style.Font.Bold = true;
                },
                "bang-ke-vat-dau-vao.xlsx", user: User,
                reportTitle: "Bảng kê hóa đơn mua vào (VAT đầu vào)",
                periodLabel: $"{fromDay:dd/MM/yyyy} – {toDayEx.AddDays(-1):dd/MM/yyyy}",
                summaryLines: byRate.Select(b => $"{b.rate}: chưa thuế {b.amount:#,##0} — VAT {b.vat:#,##0}").ToList(),
                dataRowCount: rows.Count);
        }

        return Ok(AppResponse<object>.Success(new
        {
            from = fromDay,
            to = toDayEx.AddDays(-1),
            receiptCount = receipts.Count,
            returnCount = returns.Count,
            totalAmount,
            totalVat,
            byRate,
            missingInvoiceCount = missingInvoice.Count,
            missingInvoiceDocs = missingInvoice.Take(20).ToList(),
            rows = rows.Select(x => new
            {
                kind = x.Kind,
                docNo = x.DocNo,
                invoiceSerial = x.InvoiceSerial,
                invoiceNo = x.InvoiceNo,
                invoiceDate = x.InvoiceDate,
                invoiceDateFromImport = x.DateFromImport,
                supplierName = x.SupplierName,
                supplierTaxCode = x.SupplierTaxCode,
                rate = x.RateLabel,
                amount = x.Amount,
                vat = x.Vat,
            }),
        }));
    }

    sealed record InputVatRow(
        string Kind, string DocNo, string? InvoiceSerial, string? InvoiceNo, DateTime InvoiceDate, bool DateFromImport,
        string? SupplierName, string? SupplierTaxCode, string RateLabel, decimal Amount, decimal Vat);
}
