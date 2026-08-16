using System.Globalization;
using ClosedXML.Excel;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Sổ sách kế toán hộ kinh doanh (TT 152/2025/TT-BTC) —
/// Phase 1: S1a/S2a/S2e · Phase 2: S2b/S2c/S2d (nhóm 3).
/// </summary>
[ApiController]
[Route("api/hkd")]
[Authorize]
public class HkdBooksController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    private static readonly string[] HkdSettingKeys =
    [
        "hkd_tax_group",
        "hkd_tax_code",
        "hkd_business_name",
        "hkd_industry",
        "hkd_vat_percent",
        "hkd_pit_percent",
    ];

    [HttpGet("settings")]
    [RequireModulePermission("HkdBooks", ModulePermissionAction.View)]
    public async Task<IActionResult> GetSettings()
    {
        var storeId = CurrentStoreId;
        if (!storeId.HasValue)
            return Ok(AppResponse<object>.Success(DefaultSettings()));

        var settings = await dbContext.AppSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId.Value && HkdSettingKeys.Contains(s.Key))
            .ToListAsync();
        var map = settings
            .Where(s => s.Value != null)
            .ToDictionary(s => s.Key, s => s.Value!);
        return Ok(AppResponse<object>.Success(MapSettings(map)));
    }

    [HttpPut("settings")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("HkdBooks", ModulePermissionAction.Edit)]
    public async Task<IActionResult> UpdateSettings([FromBody] UpdateHkdSettingsRequest request)
    {
        var storeId = CurrentStoreId;
        if (!storeId.HasValue)
            return BadRequest(AppResponse<object>.Fail("Yêu cầu đăng nhập theo cửa hàng"));

        var group = Math.Clamp(request.TaxGroup ?? 2, 1, 3);
        await UpsertAsync(storeId.Value, "hkd_tax_group", group.ToString(), "Nhóm thuế HKD (1/2/3)");
        await UpsertAsync(storeId.Value, "hkd_tax_code",
            (request.TaxCode ?? "").Trim(), "Mã số thuế hộ kinh doanh");
        await UpsertAsync(storeId.Value, "hkd_business_name",
            (request.BusinessName ?? "").Trim(), "Tên hộ kinh doanh");
        await UpsertAsync(storeId.Value, "hkd_industry",
            (request.Industry ?? "").Trim(), "Ngành nghề kinh doanh");
        await UpsertAsync(storeId.Value, "hkd_vat_percent",
            (request.VatPercent ?? 0).ToString(CultureInfo.InvariantCulture),
            "Tỷ lệ % thuế GTGT trên doanh thu (nhóm 2/3)");
        await UpsertAsync(storeId.Value, "hkd_pit_percent",
            (request.PitPercent ?? 0).ToString(CultureInfo.InvariantCulture),
            "Tỷ lệ % thuế TNCN (nhóm 2: trên DT; nhóm 3: trên thu nhập)");

        await dbContext.SaveChangesAsync();
        return await GetSettings();
    }

    /// <summary>Xuất sổ doanh thu S1a-HKD hoặc S2a-HKD từ đơn bán POS hoàn thành.</summary>
    [HttpGet("books/revenue/export/excel")]
    [RequireModulePermission("HkdBooks", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportRevenueBook(
        [FromQuery] string book = "S1a",
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null)
    {
        var storeId = RequiredStoreId;
        var bookCode = NormalizeRevenueBook(book);
        var (fromDt, toDt, periodLabel) = ResolvePeriod(from, to);
        var profile = await LoadProfileAsync(storeId);

        var orders = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId
                        && o.Deleted == null
                        && o.IsActive
                        && o.Status == PosSaleOrderStatus.Completed
                        && (o.SaleDate ?? o.CreatedAt) >= fromDt
                        && (o.SaleDate ?? o.CreatedAt) < toDt)
            .OrderBy(o => o.SaleDate ?? o.CreatedAt)
            .ToListAsync();

        using var workbook = new XLWorkbook();
        switch (bookCode)
        {
            case "S2a":
                WriteS2a(workbook, orders, profile, periodLabel);
                break;
            case "S2b":
                WriteS2b(workbook, orders, profile, periodLabel);
                break;
            default:
                WriteS1a(workbook, orders, profile, periodLabel);
                break;
        }

        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        var fileName = $"SoDoanhThu_{bookCode}-HKD_{fromDt:yyyyMMdd}_{toDt.AddDays(-1):yyyyMMdd}.xlsx";
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            fileName);
    }

    /// <summary>Xuất sổ chi tiết doanh thu, chi phí S2c-HKD (nhóm 3 — TNCN trên thu nhập).</summary>
    [HttpGet("books/income-expense/export/excel")]
    [RequireModulePermission("HkdBooks", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportIncomeExpenseBook(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null)
    {
        var storeId = RequiredStoreId;
        var (fromDt, toDt, periodLabel) = ResolvePeriod(from, to);
        var profile = await LoadProfileAsync(storeId);

        var orders = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId
                        && o.Deleted == null
                        && o.IsActive
                        && o.Status == PosSaleOrderStatus.Completed
                        && (o.SaleDate ?? o.CreatedAt) >= fromDt
                        && (o.SaleDate ?? o.CreatedAt) < toDt)
            .OrderBy(o => o.SaleDate ?? o.CreatedAt)
            .ToListAsync();

        var expenses = await dbContext.CashTransactions.AsNoTracking()
            .Include(t => t.Category)
            .Where(t => t.StoreId == storeId
                        && t.Deleted == null
                        && t.Status == CashTransactionStatus.Completed
                        && t.Type == CashTransactionType.Expense
                        && t.TransactionDate >= fromDt
                        && t.TransactionDate < toDt)
            .OrderBy(t => t.TransactionDate)
            .ThenBy(t => t.TransactionCode)
            .ToListAsync();

        var receipts = await dbContext.PosStockReceipts.AsNoTracking()
            .Include(r => r.Supplier)
            .Where(r => r.StoreId == storeId
                        && r.Deleted == null
                        && r.Status == PosPurchaseReceiptStatus.Completed
                        && ((r.ImportDate ?? r.CreatedAt) >= fromDt)
                        && ((r.ImportDate ?? r.CreatedAt) < toDt))
            .OrderBy(r => r.ImportDate ?? r.CreatedAt)
            .ToListAsync();

        using var workbook = new XLWorkbook();
        WriteS2c(workbook, orders, expenses, receipts, profile, periodLabel);

        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        var fileName = $"SoDoanhThuChiPhi_S2c-HKD_{fromDt:yyyyMMdd}_{toDt.AddDays(-1):yyyyMMdd}.xlsx";
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            fileName);
    }

    /// <summary>Xuất sổ chi tiết hàng hóa S2d-HKD từ thẻ kho.</summary>
    [HttpGet("books/inventory/export/excel")]
    [RequireModulePermission("HkdBooks", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportInventoryBook(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null)
    {
        var storeId = RequiredStoreId;
        var (fromDt, toDt, periodLabel) = ResolvePeriod(from, to);
        var profile = await LoadProfileAsync(storeId);

        var products = await dbContext.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId
                        && p.Deleted == null
                        && p.IsActive
                        && p.ProductType != PosProductType.Service)
            .Select(p => new
            {
                p.Id,
                p.ProductCode,
                p.Name,
                p.BaseUnitName,
                p.CostPrice,
                p.OnHandQty,
            })
            .ToListAsync();

        var productIds = products.Select(p => p.Id).ToList();

        var openingRows = await dbContext.PosStockTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId
                        && productIds.Contains(t.ProductId)
                        && t.Deleted == null
                        && t.CreatedAt < fromDt)
            .GroupBy(t => t.ProductId)
            .Select(g => new { ProductId = g.Key, Qty = g.Sum(x => x.QtyChange) })
            .ToListAsync();
        var openingByProduct = openingRows.ToDictionary(x => x.ProductId, x => x.Qty);

        var periodTxs = await dbContext.PosStockTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId
                        && productIds.Contains(t.ProductId)
                        && t.Deleted == null
                        && t.CreatedAt >= fromDt
                        && t.CreatedAt < toDt)
            .OrderBy(t => t.ProductId)
            .ThenBy(t => t.CreatedAt)
            .ToListAsync();

        var productMap = products.ToDictionary(p => p.Id);
        using var workbook = new XLWorkbook();
        WriteS2d(
            workbook,
            productMap.ToDictionary(
                kv => kv.Key,
                kv => new S2dProduct(
                    kv.Value.ProductCode,
                    kv.Value.Name,
                    string.IsNullOrWhiteSpace(kv.Value.BaseUnitName) ? "Cái" : kv.Value.BaseUnitName,
                    kv.Value.CostPrice,
                    openingByProduct.GetValueOrDefault(kv.Value.Id))),
            periodTxs,
            profile,
            periodLabel);

        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        var fileName = $"SoChiTietHangHoa_S2d-HKD_{fromDt:yyyyMMdd}_{toDt.AddDays(-1):yyyyMMdd}.xlsx";
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            fileName);
    }

    /// <summary>Xuất sổ chi tiết tiền S2e-HKD từ sổ thu chi.</summary>
    [HttpGet("books/cash/export/excel")]
    [RequireModulePermission("HkdBooks", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportCashBook(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null)
    {
        var storeId = RequiredStoreId;
        var (fromDt, toDt, periodLabel) = ResolvePeriod(from, to);
        var profile = await LoadProfileAsync(storeId);

        var txs = await dbContext.CashTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId
                        && t.Deleted == null
                        && t.Status == CashTransactionStatus.Completed
                        && t.TransactionDate >= fromDt
                        && t.TransactionDate < toDt)
            .OrderBy(t => t.TransactionDate)
            .ThenBy(t => t.TransactionCode)
            .ToListAsync();

        using var workbook = new XLWorkbook();
        WriteS2e(workbook, txs, profile, periodLabel);

        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        var fileName = $"SoChiTietTien_S2e-HKD_{fromDt:yyyyMMdd}_{toDt.AddDays(-1):yyyyMMdd}.xlsx";
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            fileName);
    }

    private void WriteS1a(
        XLWorkbook workbook,
        List<PosSaleOrder> orders,
        HkdProfile profile,
        string periodLabel)
    {
        var ws = workbook.Worksheets.Add("S1a-HKD");
        var headers = new[] { "STT", "Ngày tháng (A)", "Diễn giải (B)", "Số tiền (1)" };
        var total = orders.Sum(o => o.Total);
        var meta = ReportExcelMeta.FromUser(
            User,
            "SỔ DOANH THU BÁN HÀNG HÓA, DỊCH VỤ — Mẫu số S1a-HKD",
            periodLabel,
            BuildFilterLabel(profile, "Nhóm 1 — không chịu GTGT/TNCN"),
            new[]
            {
                $"MST: {NullDash(profile.TaxCode)}  |  Hộ KD: {NullDash(profile.BusinessName)}",
                $"Ngành nghề: {NullDash(profile.Industry)}",
                $"Tổng doanh thu kỳ: {total:N0} đ  |  Số chứng từ: {orders.Count}",
                "Căn cứ: Thông tư 152/2025/TT-BTC — sổ theo dõi doanh thu (đối chiếu CQT).",
            },
            orders.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

        var row = dataStartRow;
        var idx = 1;
        foreach (var o in orders)
        {
            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = (o.SaleDate ?? o.CreatedAt).ToString("dd/MM/yyyy");
            ws.Cell(row, 3).Value = BuildRevenueDescription(o, profile.Industry);
            ws.Cell(row, 4).Value = o.Total;
            ws.Cell(row, 4).Style.NumberFormat.Format = "#,##0";
            row++;
        }

        ws.Cell(row, 3).Value = "Cộng";
        ws.Cell(row, 3).Style.Font.Bold = true;
        ws.Cell(row, 4).Value = total;
        ws.Cell(row, 4).Style.Font.Bold = true;
        ws.Cell(row, 4).Style.NumberFormat.Format = "#,##0";
        ws.Columns(1, headers.Length).AdjustToContents();
    }

    private void WriteS2a(
        XLWorkbook workbook,
        List<PosSaleOrder> orders,
        HkdProfile profile,
        string periodLabel)
    {
        var ws = workbook.Worksheets.Add("S2a-HKD");
        var headers = new[]
        {
            "STT",
            "Số hiệu CT (A)",
            "Ngày CT (B)",
            "Diễn giải (C)",
            "Doanh thu (1)",
            "Thuế GTGT ước tính",
            "Thuế TNCN ước tính",
        };
        var total = orders.Sum(o => o.Total);
        var vatEst = RoundMoney(total * (decimal)(profile.VatPercent / 100.0));
        var pitEst = RoundMoney(total * (decimal)(profile.PitPercent / 100.0));
        var meta = ReportExcelMeta.FromUser(
            User,
            "SỔ DOANH THU BÁN HÀNG HÓA, DỊCH VỤ — Mẫu số S2a-HKD",
            periodLabel,
            BuildFilterLabel(profile, "Nhóm 2 — GTGT + TNCN theo % doanh thu"),
            new[]
            {
                $"MST: {NullDash(profile.TaxCode)}  |  Hộ KD: {NullDash(profile.BusinessName)}",
                $"Ngành nghề: {NullDash(profile.Industry)}  |  GTGT {profile.VatPercent}%  |  TNCN {profile.PitPercent}%",
                $"Tổng DT: {total:N0}  |  GTGT ước tính: {vatEst:N0}  |  TNCN ước tính: {pitEst:N0}",
                "Cột thuế ước tính theo tỷ lệ cấu hình cửa hàng — đối chiếu thông báo CQT khi nộp.",
            },
            orders.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

        var row = dataStartRow;
        var idx = 1;
        foreach (var o in orders)
        {
            var lineVat = RoundMoney(o.Total * (decimal)(profile.VatPercent / 100.0));
            var linePit = RoundMoney(o.Total * (decimal)(profile.PitPercent / 100.0));
            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = o.OrderNo;
            ws.Cell(row, 3).Value = (o.SaleDate ?? o.CreatedAt).ToString("dd/MM/yyyy");
            ws.Cell(row, 4).Value = BuildRevenueDescription(o, profile.Industry);
            ws.Cell(row, 5).Value = o.Total;
            ws.Cell(row, 5).Style.NumberFormat.Format = "#,##0";
            ws.Cell(row, 6).Value = lineVat;
            ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
            ws.Cell(row, 7).Value = linePit;
            ws.Cell(row, 7).Style.NumberFormat.Format = "#,##0";
            row++;
        }

        ws.Cell(row, 4).Value = "Cộng";
        ws.Cell(row, 4).Style.Font.Bold = true;
        ws.Cell(row, 5).Value = total;
        ws.Cell(row, 5).Style.Font.Bold = true;
        ws.Cell(row, 5).Style.NumberFormat.Format = "#,##0";
        ws.Cell(row, 6).Value = vatEst;
        ws.Cell(row, 6).Style.Font.Bold = true;
        ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
        ws.Cell(row, 7).Value = pitEst;
        ws.Cell(row, 7).Style.Font.Bold = true;
        ws.Cell(row, 7).Style.NumberFormat.Format = "#,##0";
        ws.Columns(1, headers.Length).AdjustToContents();
    }

    private void WriteS2b(
        XLWorkbook workbook,
        List<PosSaleOrder> orders,
        HkdProfile profile,
        string periodLabel)
    {
        var ws = workbook.Worksheets.Add("S2b-HKD");
        var headers = new[]
        {
            "STT",
            "Số hiệu CT (A)",
            "Ngày CT (B)",
            "Diễn giải (C)",
            "Doanh thu (1)",
            "Thuế GTGT ước tính",
        };
        var total = orders.Sum(o => o.Total);
        var vatEst = RoundMoney(total * (decimal)(profile.VatPercent / 100.0));
        var meta = ReportExcelMeta.FromUser(
            User,
            "SỔ DOANH THU BÁN HÀNG HÓA, DỊCH VỤ — Mẫu số S2b-HKD",
            periodLabel,
            BuildFilterLabel(profile, "Nhóm 3 — GTGT % doanh thu; TNCN theo thu nhập (xem S2c)"),
            new[]
            {
                $"MST: {NullDash(profile.TaxCode)}  |  Hộ KD: {NullDash(profile.BusinessName)}",
                $"Ngành nghề: {NullDash(profile.Industry)}  |  GTGT {profile.VatPercent}% trên doanh thu",
                $"Tổng DT: {total:N0}  |  GTGT ước tính phải nộp: {vatEst:N0}",
                "Ghi theo nhóm ngành có cùng tỷ lệ % GTGT. Dòng cuối: tổng thuế GTGT kỳ.",
            },
            orders.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

        var row = dataStartRow;
        var idx = 1;
        foreach (var o in orders)
        {
            var lineVat = RoundMoney(o.Total * (decimal)(profile.VatPercent / 100.0));
            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = o.OrderNo;
            ws.Cell(row, 3).Value = (o.SaleDate ?? o.CreatedAt).ToString("dd/MM/yyyy");
            ws.Cell(row, 4).Value = BuildRevenueDescription(o, profile.Industry);
            ws.Cell(row, 5).Value = o.Total;
            ws.Cell(row, 5).Style.NumberFormat.Format = "#,##0";
            ws.Cell(row, 6).Value = lineVat;
            ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
            row++;
        }

        ws.Cell(row, 4).Value = "Cộng doanh thu / thuế GTGT phải nộp";
        ws.Cell(row, 4).Style.Font.Bold = true;
        ws.Cell(row, 5).Value = total;
        ws.Cell(row, 5).Style.Font.Bold = true;
        ws.Cell(row, 5).Style.NumberFormat.Format = "#,##0";
        ws.Cell(row, 6).Value = vatEst;
        ws.Cell(row, 6).Style.Font.Bold = true;
        ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
        ws.Columns(1, headers.Length).AdjustToContents();
    }

    private void WriteS2c(
        XLWorkbook workbook,
        List<PosSaleOrder> orders,
        List<CashTransaction> expenses,
        List<PosStockReceipt> receipts,
        HkdProfile profile,
        string periodLabel)
    {
        var ws = workbook.Worksheets.Add("S2c-HKD");
        var headers = new[]
        {
            "STT",
            "Số hiệu CT (A)",
            "Ngày CT (B)",
            "Diễn giải (C)",
            "Loại",
            "Số tiền (1)",
        };

        var revenueTotal = orders.Sum(o => o.Total);
        var cashCost = expenses.Sum(t => t.Amount);
        var purchaseCost = receipts.Sum(r => r.TotalCost + r.TotalVat - r.DiscountAmount);
        var costTotal = cashCost + purchaseCost;
        var taxableIncome = revenueTotal - costTotal;
        var pitEst = RoundMoney(Math.Max(0, taxableIncome) * (decimal)(profile.PitPercent / 100.0));

        var meta = ReportExcelMeta.FromUser(
            User,
            "SỔ CHI TIẾT DOANH THU, CHI PHÍ — Mẫu số S2c-HKD",
            periodLabel,
            BuildFilterLabel(profile, "Nhóm 3 — căn cứ TNCN = doanh thu − chi phí hợp lý"),
            new[]
            {
                $"MST: {NullDash(profile.TaxCode)}  |  Hộ KD: {NullDash(profile.BusinessName)}",
                $"1. Tổng doanh thu: {revenueTotal:N0}  |  2. Tổng chi phí hợp lý: {costTotal:N0}",
                $"Thu nhập tính thuế: {taxableIncome:N0}  |  TNCN ước tính ({profile.PitPercent}%): {pitEst:N0}",
                "Chi phí = phiếu chi hoàn tất + phiếu nhập hàng. Hộ tự loại trừ khoản không hợp lý khi kê khai.",
            },
            orders.Count + expenses.Count + receipts.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

        var rows = new List<(DateTime Date, string Code, string Desc, string Kind, decimal Amount)>();
        foreach (var o in orders)
        {
            rows.Add((
                o.SaleDate ?? o.CreatedAt,
                o.OrderNo,
                BuildRevenueDescription(o, profile.Industry),
                "Doanh thu",
                o.Total));
        }
        foreach (var t in expenses)
        {
            var cat = t.Category?.Name;
            var desc = string.IsNullOrWhiteSpace(cat)
                ? t.Description
                : $"{cat} — {t.Description}";
            if (!string.IsNullOrWhiteSpace(t.ContactName))
                desc = $"{desc} — {t.ContactName}";
            rows.Add((t.TransactionDate, t.TransactionCode, desc, "Chi phí (thu chi)", t.Amount));
        }
        foreach (var r in receipts)
        {
            var when = r.ImportDate ?? r.CreatedAt;
            var supplier = r.Supplier?.Name;
            var desc = string.IsNullOrWhiteSpace(supplier)
                ? "Nhập hàng / mua hàng"
                : $"Nhập hàng — {supplier}";
            if (!string.IsNullOrWhiteSpace(r.Note))
                desc = $"{desc} — {r.Note}";
            var amount = r.TotalCost + r.TotalVat - r.DiscountAmount;
            rows.Add((when, r.ReceiptNo, desc, "Chi phí (nhập hàng)", amount));
        }

        rows = rows.OrderBy(x => x.Date).ThenBy(x => x.Code).ToList();

        var row = dataStartRow;
        var idx = 1;
        foreach (var item in rows)
        {
            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = item.Code;
            ws.Cell(row, 3).Value = item.Date.ToString("dd/MM/yyyy");
            ws.Cell(row, 4).Value = item.Desc;
            ws.Cell(row, 5).Value = item.Kind;
            ws.Cell(row, 6).Value = item.Amount;
            ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
            row++;
        }

        row++;
        ws.Cell(row, 4).Value = "1. Cộng doanh thu";
        ws.Cell(row, 4).Style.Font.Bold = true;
        ws.Cell(row, 6).Value = revenueTotal;
        ws.Cell(row, 6).Style.Font.Bold = true;
        ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
        row++;
        ws.Cell(row, 4).Value = "2. Cộng chi phí hợp lý";
        ws.Cell(row, 4).Style.Font.Bold = true;
        ws.Cell(row, 6).Value = costTotal;
        ws.Cell(row, 6).Style.Font.Bold = true;
        ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
        row++;
        ws.Cell(row, 4).Value = "Thu nhập tính thuế (1 − 2)";
        ws.Cell(row, 4).Style.Font.Bold = true;
        ws.Cell(row, 6).Value = taxableIncome;
        ws.Cell(row, 6).Style.Font.Bold = true;
        ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
        row++;
        ws.Cell(row, 4).Value = $"TNCN ước tính ({profile.PitPercent}%)";
        ws.Cell(row, 4).Style.Font.Bold = true;
        ws.Cell(row, 6).Value = pitEst;
        ws.Cell(row, 6).Style.Font.Bold = true;
        ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
        ws.Columns(1, headers.Length).AdjustToContents();
    }

    private void WriteS2d(
        XLWorkbook workbook,
        Dictionary<Guid, S2dProduct> products,
        List<PosStockTransaction> txs,
        HkdProfile profile,
        string periodLabel)
    {
        var ws = workbook.Worksheets.Add("S2d-HKD");
        var headers = new[]
        {
            "STT",
            "Số hiệu CT (A)",
            "Ngày CT (B)",
            "Diễn giải (C)",
            "ĐVT (D)",
            "Đơn giá (1)",
            "SL nhập (2)",
            "GT nhập (3)",
            "SL xuất (4)",
            "GT xuất (5)",
            "SL tồn (6)",
            "GT tồn (7)",
            "Mã SP",
            "Tên hàng",
        };

        var movedIds = txs.Select(t => t.ProductId).ToHashSet();
        var relevant = products
            .Where(p => movedIds.Contains(p.Key) || p.Value.OpeningQty != 0)
            .OrderBy(p => p.Value.Code)
            .ToList();

        var meta = ReportExcelMeta.FromUser(
            User,
            "SỔ CHI TIẾT VẬT LIỆU, DỤNG CỤ, SẢN PHẨM, HÀNG HÓA — Mẫu số S2d-HKD",
            periodLabel,
            BuildFilterLabel(profile, "Nhập — xuất — tồn theo thẻ kho POS"),
            new[]
            {
                $"MST: {NullDash(profile.TaxCode)}  |  Hộ KD: {NullDash(profile.BusinessName)}",
                $"Số SKU có phát sinh / tồn đầu kỳ: {relevant.Count}  |  Số dòng biến động kỳ: {txs.Count}",
                "Tồn đầu = tổng QtyChange trước kỳ. Đơn giá ưu tiên UnitCost chứng từ; thiếu thì giá vốn SP.",
                "Mỗi mặt hàng có dòng tồn đầu, các nghiệp vụ trong kỳ, rồi tồn cuối.",
            },
            txs.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

        var txsByProduct = txs.GroupBy(t => t.ProductId).ToDictionary(g => g.Key, g => g.ToList());
        var row = dataStartRow;
        var idx = 1;

        foreach (var (productId, product) in relevant)
        {
            var unitCost = product.CostPrice;
            var balQty = product.OpeningQty;
            var balVal = RoundMoney(balQty * unitCost);

            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = "";
            ws.Cell(row, 3).Value = "";
            ws.Cell(row, 4).Value = "Tồn đầu kỳ";
            ws.Cell(row, 5).Value = product.Unit;
            ws.Cell(row, 6).Value = unitCost;
            ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
            ws.Cell(row, 11).Value = balQty;
            ws.Cell(row, 11).Style.NumberFormat.Format = "#,##0.###";
            ws.Cell(row, 12).Value = balVal;
            ws.Cell(row, 12).Style.NumberFormat.Format = "#,##0";
            ws.Cell(row, 13).Value = product.Code;
            ws.Cell(row, 14).Value = product.Name;
            row++;

            if (txsByProduct.TryGetValue(productId, out var list))
            {
                foreach (var t in list)
                {
                    var qty = t.QtyChange;
                    var price = t.UnitCost
                        ?? (t.LineAmount.HasValue && qty != 0
                            ? Math.Abs(t.LineAmount.Value / qty)
                            : unitCost);
                    var absQty = Math.Abs(qty);
                    var lineVal = t.LineAmount.HasValue
                        ? Math.Abs(t.LineAmount.Value)
                        : RoundMoney(absQty * price);

                    balQty += qty;
                    if (qty > 0)
                        balVal += lineVal;
                    else if (qty < 0)
                        balVal -= lineVal;
                    else if (t.LineAmount.HasValue)
                        balVal += t.LineAmount.Value;

                    var avgCost = balQty != 0 ? RoundMoney(balVal / balQty) : price;

                    ws.Cell(row, 1).Value = idx++;
                    ws.Cell(row, 2).Value = t.ReferenceNo ?? StockTxnLabel(t.TransactionType);
                    ws.Cell(row, 3).Value = t.CreatedAt.ToString("dd/MM/yyyy");
                    ws.Cell(row, 4).Value = BuildStockDescription(t);
                    ws.Cell(row, 5).Value = product.Unit;
                    ws.Cell(row, 6).Value = price;
                    ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
                    if (qty > 0)
                    {
                        ws.Cell(row, 7).Value = absQty;
                        ws.Cell(row, 7).Style.NumberFormat.Format = "#,##0.###";
                        ws.Cell(row, 8).Value = lineVal;
                        ws.Cell(row, 8).Style.NumberFormat.Format = "#,##0";
                    }
                    else if (qty < 0)
                    {
                        ws.Cell(row, 9).Value = absQty;
                        ws.Cell(row, 9).Style.NumberFormat.Format = "#,##0.###";
                        ws.Cell(row, 10).Value = lineVal;
                        ws.Cell(row, 10).Style.NumberFormat.Format = "#,##0";
                    }
                    ws.Cell(row, 11).Value = balQty;
                    ws.Cell(row, 11).Style.NumberFormat.Format = "#,##0.###";
                    ws.Cell(row, 12).Value = RoundMoney(balVal);
                    ws.Cell(row, 12).Style.NumberFormat.Format = "#,##0";
                    ws.Cell(row, 13).Value = product.Code;
                    ws.Cell(row, 14).Value = product.Name;
                    _ = avgCost;
                    row++;
                }
            }

            ws.Cell(row, 4).Value = "Tồn cuối kỳ";
            ws.Cell(row, 4).Style.Font.Bold = true;
            ws.Cell(row, 5).Value = product.Unit;
            ws.Cell(row, 11).Value = balQty;
            ws.Cell(row, 11).Style.Font.Bold = true;
            ws.Cell(row, 11).Style.NumberFormat.Format = "#,##0.###";
            ws.Cell(row, 12).Value = RoundMoney(balVal);
            ws.Cell(row, 12).Style.Font.Bold = true;
            ws.Cell(row, 12).Style.NumberFormat.Format = "#,##0";
            ws.Cell(row, 13).Value = product.Code;
            ws.Cell(row, 14).Value = product.Name;
            row += 2;
        }

        ws.Columns(1, headers.Length).AdjustToContents();
    }

    private static string BuildStockDescription(PosStockTransaction t)
    {
        var label = StockTxnLabel(t.TransactionType);
        if (!string.IsNullOrWhiteSpace(t.Note))
            return $"{label} — {t.Note.Trim()}";
        if (!string.IsNullOrWhiteSpace(t.ReferenceNo))
            return $"{label} — {t.ReferenceNo.Trim()}";
        return label;
    }

    private static string StockTxnLabel(PosStockTransactionType type) => type switch
    {
        PosStockTransactionType.StockIn => "Nhập kho",
        PosStockTransactionType.StockOut => "Xuất kho",
        PosStockTransactionType.Adjust => "Điều chỉnh",
        PosStockTransactionType.Sale => "Bán hàng",
        PosStockTransactionType.Purchase => "Mua hàng",
        PosStockTransactionType.Return => "Khách trả",
        PosStockTransactionType.PurchaseReturn => "Trả NCC",
        _ => type.ToString(),
    };

    private void WriteS2e(
        XLWorkbook workbook,
        List<CashTransaction> txs,
        HkdProfile profile,
        string periodLabel)
    {
        var ws = workbook.Worksheets.Add("S2e-HKD");
        var headers = new[]
        {
            "STT",
            "Số hiệu CT (A)",
            "Ngày CT (B)",
            "Diễn giải (C)",
            "Thu (1)",
            "Chi (2)",
            "Hình thức",
        };
        var totalIn = txs.Where(t => t.Type == CashTransactionType.Income).Sum(t => t.Amount);
        var totalOut = txs.Where(t => t.Type == CashTransactionType.Expense).Sum(t => t.Amount);
        var meta = ReportExcelMeta.FromUser(
            User,
            "SỔ CHI TIẾT TIỀN — Mẫu số S2e-HKD",
            periodLabel,
            BuildFilterLabel(profile, "Theo dõi thu/chi tiền mặt & chuyển khoản"),
            new[]
            {
                $"MST: {NullDash(profile.TaxCode)}  |  Hộ KD: {NullDash(profile.BusinessName)}",
                $"Tổng thu: {totalIn:N0}  |  Tổng chi: {totalOut:N0}  |  Chênh lệch: {(totalIn - totalOut):N0}",
                "Căn cứ: Thông tư 152/2025/TT-BTC — có thể mở sổ riêng theo loại tiền (TM / ngân hàng).",
            },
            txs.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

        var row = dataStartRow;
        var idx = 1;
        foreach (var t in txs)
        {
            var isIn = t.Type == CashTransactionType.Income;
            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = t.TransactionCode;
            ws.Cell(row, 3).Value = t.TransactionDate.ToString("dd/MM/yyyy");
            ws.Cell(row, 4).Value = string.IsNullOrWhiteSpace(t.ContactName)
                ? t.Description
                : $"{t.Description} — {t.ContactName}";
            if (isIn)
            {
                ws.Cell(row, 5).Value = t.Amount;
                ws.Cell(row, 5).Style.NumberFormat.Format = "#,##0";
            }
            else
            {
                ws.Cell(row, 6).Value = t.Amount;
                ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
            }
            ws.Cell(row, 7).Value = PaymentMethodLabel(t.PaymentMethod);
            row++;
        }

        ws.Cell(row, 4).Value = "Cộng";
        ws.Cell(row, 4).Style.Font.Bold = true;
        ws.Cell(row, 5).Value = totalIn;
        ws.Cell(row, 5).Style.Font.Bold = true;
        ws.Cell(row, 5).Style.NumberFormat.Format = "#,##0";
        ws.Cell(row, 6).Value = totalOut;
        ws.Cell(row, 6).Style.Font.Bold = true;
        ws.Cell(row, 6).Style.NumberFormat.Format = "#,##0";
        ws.Columns(1, headers.Length).AdjustToContents();
    }

    private async Task<HkdProfile> LoadProfileAsync(Guid storeId)
    {
        var settings = await dbContext.AppSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && HkdSettingKeys.Contains(s.Key))
            .ToListAsync();
        var map = settings
            .Where(s => s.Value != null)
            .ToDictionary(s => s.Key, s => s.Value!);
        return new HkdProfile
        {
            TaxGroup = ParseInt(map, "hkd_tax_group", 2),
            TaxCode = map.GetValueOrDefault("hkd_tax_code") ?? "",
            BusinessName = map.GetValueOrDefault("hkd_business_name") ?? "",
            Industry = map.GetValueOrDefault("hkd_industry") ?? "",
            VatPercent = ParseDouble(map, "hkd_vat_percent", 0),
            PitPercent = ParseDouble(map, "hkd_pit_percent", 0),
        };
    }

    private async Task UpsertAsync(Guid storeId, string key, string value, string description)
    {
        var setting = await dbContext.AppSettings.AsTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Key == key);
        if (setting == null)
        {
            dbContext.AppSettings.Add(new AppSettings
            {
                Id = Guid.NewGuid(),
                Key = key,
                Value = value,
                Description = description,
                Group = "Hkd",
                DataType = "string",
                StoreId = storeId,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserId.ToString(),
            });
        }
        else
        {
            setting.Value = value;
            setting.Description = description;
            setting.Group = "Hkd";
            setting.LastModified = DateTime.UtcNow;
            setting.LastModifiedBy = CurrentUserId.ToString();
        }
    }

    private static (DateTime fromDt, DateTime toDt, string periodLabel) ResolvePeriod(
        DateTime? from, DateTime? to)
    {
        // Sổ HKD: ngày lịch VN → cửa sổ UTC+7 (không qua đêm; giờ cắt = 0).
        var vnNow = ZKTecoADMS.Application.Helpers.VnTimeHelper.NowVn().Date;
        var monthStart = new DateTime(vnNow.Year, vnNow.Month, 1);
        var (fromUtc, toUtc, fromVn, toVnEx) =
            ZKTecoADMS.Api.Controllers.Reports.ReportHelpers.PosBusinessRange(
                from ?? monthStart, to ?? vnNow, dayStartHour: 0);
        var label = $"{fromVn:dd/MM/yyyy} - {toVnEx.AddDays(-1):dd/MM/yyyy} (UTC+7)";
        return (fromUtc, toUtc, label);
    }

    private static string NormalizeRevenueBook(string? book)
    {
        var b = (book ?? "S1a").Trim().ToUpperInvariant().Replace("-HKD", "");
        return b switch
        {
            "S2A" or "S2" => "S2a",
            "S2B" => "S2b",
            _ => "S1a",
        };
    }

    private static string BuildRevenueDescription(PosSaleOrder o, string industry)
    {
        var parts = new List<string> { "Bán hàng" };
        if (!string.IsNullOrWhiteSpace(industry))
            parts.Add(industry.Trim());
        if (!string.IsNullOrWhiteSpace(o.CustomerName))
            parts.Add(o.CustomerName.Trim());
        if (!string.IsNullOrWhiteSpace(o.PaymentMethod))
            parts.Add(o.PaymentMethod.Trim());
        return string.Join(" — ", parts);
    }

    private static string BuildFilterLabel(HkdProfile profile, string note) =>
        $"Nhóm {profile.TaxGroup}  |  {note}";

    private static string PaymentMethodLabel(PaymentMethodType m) => m switch
    {
        PaymentMethodType.Cash => "Tiền mặt",
        PaymentMethodType.BankTransfer => "Chuyển khoản",
        PaymentMethodType.VietQR => "VietQR",
        PaymentMethodType.Card => "Thẻ",
        _ => m.ToString(),
    };

    private static object DefaultSettings() => new
    {
        taxGroup = 2,
        taxCode = "",
        businessName = "",
        industry = "",
        vatPercent = 0.0,
        pitPercent = 0.0,
        recommendedBooks = RecommendedBooks(2),
    };

    private static object MapSettings(Dictionary<string, string> map)
    {
        var group = ParseInt(map, "hkd_tax_group", 2);
        return new
        {
            taxGroup = group,
            taxCode = map.GetValueOrDefault("hkd_tax_code") ?? "",
            businessName = map.GetValueOrDefault("hkd_business_name") ?? "",
            industry = map.GetValueOrDefault("hkd_industry") ?? "",
            vatPercent = ParseDouble(map, "hkd_vat_percent", 0),
            pitPercent = ParseDouble(map, "hkd_pit_percent", 0),
            recommendedBooks = RecommendedBooks(group),
        };
    }

    private static string[] RecommendedBooks(int group) => group switch
    {
        1 => ["S1a-HKD"],
        3 => ["S2b-HKD", "S2c-HKD", "S2d-HKD", "S2e-HKD"],
        _ => ["S2a-HKD", "S2e-HKD"],
    };

    private static string NullDash(string? v) =>
        string.IsNullOrWhiteSpace(v) ? "—" : v.Trim();

    private static decimal RoundMoney(decimal v) =>
        Math.Round(v, 0, MidpointRounding.AwayFromZero);

    private static double ParseDouble(IReadOnlyDictionary<string, string> map, string key, double fallback) =>
        map.TryGetValue(key, out var v) &&
        double.TryParse(v, NumberStyles.Any, CultureInfo.InvariantCulture, out var d)
            ? d
            : fallback;

    private static int ParseInt(IReadOnlyDictionary<string, string> map, string key, int fallback) =>
        map.TryGetValue(key, out var v) && int.TryParse(v, out var i) ? i : fallback;

    private sealed class HkdProfile
    {
        public int TaxGroup { get; init; }
        public string TaxCode { get; init; } = "";
        public string BusinessName { get; init; } = "";
        public string Industry { get; init; } = "";
        public double VatPercent { get; init; }
        public double PitPercent { get; init; }
    }

    private sealed record S2dProduct(
        string Code,
        string Name,
        string Unit,
        decimal CostPrice,
        decimal OpeningQty);

    public class UpdateHkdSettingsRequest
    {
        public int? TaxGroup { get; set; }
        public string? TaxCode { get; set; }
        public string? BusinessName { get; set; }
        public string? Industry { get; set; }
        public double? VatPercent { get; set; }
        public double? PitPercent { get; set; }
    }
}
