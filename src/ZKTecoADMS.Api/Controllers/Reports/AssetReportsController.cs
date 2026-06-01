using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Assets;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// Báo cáo tài sản: tổng hợp, danh mục, cấp phát, lịch sử chuyển giao.
/// </summary>
[ApiController]
[Route("api/reports/assets")]
[Authorize]
public class AssetReportsController(
    ZKTecoDbContext db,
    ILogger<AssetReportsController> logger
) : AuthenticatedControllerBase
{
    // GET /api/reports/assets/summary?status=&assetType=&categoryId=
    [HttpGet("summary")]
    [RequireModulePermission("AssetReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetSummary(
        [FromQuery] AssetStatus? status = null,
        [FromQuery] AssetType? assetType = null,
        [FromQuery] Guid? categoryId = null,
        CancellationToken ct = default)
    {
        try
        {
            var assets = await QueryAssets(status, assetType, categoryId).ToListAsync(ct);
            var stats = BuildStatistics(assets);
            return Ok(AppResponse<AssetStatisticsDto>.Success(stats));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Asset report summary failed");
            return StatusCode(500, AppResponse<AssetStatisticsDto>.Fail(ex.Message));
        }
    }

    // GET /api/reports/assets/register?status=&assetType=&categoryId=&search=&format=excel
    [HttpGet("register")]
    [RequireModulePermission("AssetReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetRegister(
        [FromQuery] AssetStatus? status = null,
        [FromQuery] AssetType? assetType = null,
        [FromQuery] Guid? categoryId = null,
        [FromQuery] string? search = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var assets = await QueryAssets(status, assetType, categoryId, search).ToListAsync(ct);
            var items = assets.Select(MapRegisterRow).OrderBy(i => i.AssetCode).ToList();
            var report = new AssetRegisterReportDto
            {
                TotalCount = items.Count,
                TotalPurchaseValue = assets.Sum(a => a.PurchasePrice * a.Quantity),
                TotalCurrentValue = assets.Sum(a => (a.CurrentValue ?? a.PurchasePrice) * a.Quantity),
                Items = items
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Danh muc tai san",
                    ["Mã TS", "Tên", "Loại", "Danh mục", "Trạng thái", "SL", "ĐVT", "Giá mua", "Giá trị HT", "Vị trí", "Người giữ", "Ngày cấp", "Bảo hành", "Serial"],
                    (ws, dataStartRow) => { var row = dataStartRow;
                        foreach (var i in items)
                        {
                            ws.Cell(row, 1).Value = i.AssetCode;
                            ws.Cell(row, 2).Value = i.Name;
                            ws.Cell(row, 3).Value = i.AssetTypeName;
                            ws.Cell(row, 4).Value = i.CategoryName ?? "";
                            ws.Cell(row, 5).Value = i.StatusName;
                            ws.Cell(row, 6).Value = i.Quantity;
                            ws.Cell(row, 7).Value = i.Unit;
                            ReportHelpers.MoneyCell(ws.Cell(row, 8), i.PurchasePrice);
                            ReportHelpers.MoneyCell(ws.Cell(row, 9), i.CurrentValue ?? i.PurchasePrice);
                            ws.Cell(row, 10).Value = i.Location ?? "";
                            ws.Cell(row, 11).Value = i.AssigneeName ?? "";
                            if (i.AssignedDate.HasValue) ReportHelpers.DateCell(ws.Cell(row, 12), i.AssignedDate.Value);
                            if (i.WarrantyExpiry.HasValue) ReportHelpers.DateCell(ws.Cell(row, 13), i.WarrantyExpiry.Value);
                            ws.Cell(row, 14).Value = i.SerialNumber ?? "";
                            row++;
                        }
                    },
                    "asset-register.xlsx", user: User);
            }

            return Ok(AppResponse<AssetRegisterReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Asset register report failed");
            return StatusCode(500, AppResponse<AssetRegisterReportDto>.Fail(ex.Message));
        }
    }

    // GET /api/reports/assets/assignments?status=&department=&assignedOnly=true&format=excel
    [HttpGet("assignments")]
    [RequireModulePermission("AssetReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetAssignments(
        [FromQuery] AssetStatus? status = null,
        [FromQuery] string? department = null,
        [FromQuery] bool assignedOnly = true,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var q = QueryAssets(status, null, null);
            if (assignedOnly)
                q = q.Where(a => a.CurrentAssigneeId != null);

            var assets = await q.ToListAsync(ct);
            var rows = assets.Select(a => new
            {
                Asset = a,
                Emp = a.CurrentAssignee,
                Dept = a.CurrentAssignee?.Department
            }).ToList();

            if (!string.IsNullOrWhiteSpace(department))
            {
                rows = rows.Where(r => (r.Dept ?? "").Contains(department, StringComparison.OrdinalIgnoreCase)).ToList();
            }

            var byStatus = rows.GroupBy(r => r.Asset.Status)
                .Select(g => new AssetByStatusDto
                {
                    Status = g.Key,
                    StatusName = AssetReportLabels.Status(g.Key),
                    Count = g.Count()
                })
                .OrderByDescending(x => x.Count)
                .ToList();

            var assignments = rows
                .Where(r => r.Emp != null)
                .Select(r => new AssetReportAssignmentRowDto
                {
                    AssetCode = r.Asset.AssetCode,
                    AssetName = r.Asset.Name,
                    Brand = r.Asset.Brand,
                    SerialNumber = r.Asset.SerialNumber,
                    StatusName = AssetReportLabels.Status(r.Asset.Status),
                    EmployeeCode = r.Emp!.EmployeeCode,
                    EmployeeName = $"{r.Emp.FirstName} {r.Emp.LastName}".Trim(),
                    Department = r.Dept,
                    AssignedDate = r.Asset.AssignedDate,
                    Value = r.Asset.CurrentValue ?? r.Asset.PurchasePrice
                })
                .OrderBy(i => i.Department).ThenBy(i => i.EmployeeName)
                .ToList();

            var all = rows.Select(r => r.Asset).ToList();
            var report = new AssetReportAssignmentDto
            {
                TotalAssets = all.Count,
                AssignedCount = assignments.Count,
                InStockCount = all.Count(a => a.Status == AssetStatus.InStock),
                BrokenCount = all.Count(a => a.Status == AssetStatus.Broken),
                LostCount = all.Count(a => a.Status == AssetStatus.Lost),
                DisposedCount = all.Count(a => a.Status == AssetStatus.Disposed),
                TotalValue = all.Sum(a => a.CurrentValue ?? a.PurchasePrice),
                ByStatus = byStatus,
                Assignments = assignments
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Cap phat tai san",
                    ["Mã TS", "Tên", "Hãng", "Serial", "Trạng thái", "Mã NV", "Họ tên", "Phòng ban", "Ngày cấp", "Giá trị"],
                    (ws, dataStartRow) => { var row = dataStartRow;
                        foreach (var i in assignments)
                        {
                            ws.Cell(row, 1).Value = i.AssetCode;
                            ws.Cell(row, 2).Value = i.AssetName;
                            ws.Cell(row, 3).Value = i.Brand ?? "";
                            ws.Cell(row, 4).Value = i.SerialNumber ?? "";
                            ws.Cell(row, 5).Value = i.StatusName;
                            ws.Cell(row, 6).Value = i.EmployeeCode ?? "";
                            ws.Cell(row, 7).Value = i.EmployeeName ?? "";
                            ws.Cell(row, 8).Value = i.Department ?? "";
                            if (i.AssignedDate.HasValue) ReportHelpers.DateCell(ws.Cell(row, 9), i.AssignedDate.Value);
                            ReportHelpers.MoneyCell(ws.Cell(row, 10), i.Value);
                            row++;
                        }
                    },
                    "asset-assignments.xlsx", user: User);
            }

            return Ok(AppResponse<AssetReportAssignmentDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Asset assignments report failed");
            return StatusCode(500, AppResponse<AssetReportAssignmentDto>.Fail(ex.Message));
        }
    }

    // GET /api/reports/assets/transfers?from=&to=&transferType=&format=excel
    [HttpGet("transfers")]
    [RequireModulePermission("AssetReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetTransfers(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] AssetTransferType? transferType = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (_, _, utcStart, utcEnd) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var q = db.AssetTransfers
                .AsNoTracking()
                .Include(t => t.Asset)
                .Include(t => t.FromUser)
                .Include(t => t.ToUser)
                .Where(t => t.Asset != null && t.Asset.StoreId == storeId
                    && t.TransferDate >= utcStart && t.TransferDate < utcEnd);

            if (transferType.HasValue)
                q = q.Where(t => t.TransferType == transferType.Value);

            var transfers = await q.OrderByDescending(t => t.TransferDate).ToListAsync(ct);

            var items = transfers.Select(t => new AssetTransferReportRowDto
            {
                TransferDate = ReportHelpers.ToVn(t.TransferDate),
                TransferTypeName = AssetReportLabels.TransferType(t.TransferType),
                AssetCode = t.Asset?.AssetCode ?? "",
                AssetName = t.Asset?.Name ?? "",
                Quantity = t.Quantity,
                FromUserName = t.FromUserName,
                ToUserName = t.ToUserName,
                Reason = t.Reason,
                IsConfirmed = t.IsConfirmed
            }).ToList();

            var report = new AssetTransferReportDto
            {
                TotalCount = items.Count,
                Items = items
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Lich su chuyen giao",
                    ["Ngày", "Loại", "Mã TS", "Tên TS", "SL", "Từ", "Đến", "Lý do", "Xác nhận"],
                    (ws, dataStartRow) => { var row = dataStartRow;
                        foreach (var i in items)
                        {
                            ReportHelpers.DateCell(ws.Cell(row, 1), i.TransferDate);
                            ws.Cell(row, 2).Value = i.TransferTypeName;
                            ws.Cell(row, 3).Value = i.AssetCode;
                            ws.Cell(row, 4).Value = i.AssetName;
                            ws.Cell(row, 5).Value = i.Quantity;
                            ws.Cell(row, 6).Value = i.FromUserName ?? "";
                            ws.Cell(row, 7).Value = i.ToUserName ?? "";
                            ws.Cell(row, 8).Value = i.Reason ?? "";
                            ws.Cell(row, 9).Value = i.IsConfirmed ? "Có" : "Chưa";
                            row++;
                        }
                    },
                    "asset-transfers.xlsx", user: User);
            }

            return Ok(AppResponse<AssetTransferReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Asset transfers report failed");
            return StatusCode(500, AppResponse<AssetTransferReportDto>.Fail(ex.Message));
        }
    }

    // GET /api/reports/assets/stock-ledger?from=&to=&transactionType=&format=excel
    [HttpGet("stock-ledger")]
    [RequireModulePermission("AssetReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetStockLedger(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] StockTransactionType? transactionType = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (_, _, utcStart, utcEnd) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var q = db.StockTransactions.AsNoTracking()
                .Include(t => t.Asset)
                .Include(t => t.PerformedBy)
                .Where(t => t.StoreId == storeId
                    && t.TransactionDate >= utcStart
                    && t.TransactionDate < utcEnd);

            if (transactionType.HasValue)
                q = q.Where(t => t.TransactionType == transactionType.Value);

            var transactions = await q.OrderByDescending(t => t.TransactionDate).ToListAsync(ct);

            var items = transactions.Select(t => new AssetStockLedgerRowDto
            {
                TransactionDate = ReportHelpers.ToVn(t.TransactionDate),
                TransactionTypeName = AssetReportLabels.StockType(t.TransactionType),
                AssetCode = t.Asset?.AssetCode ?? "",
                AssetName = t.Asset?.Name ?? "",
                Quantity = t.Quantity,
                BalanceAfter = t.BalanceAfter,
                ReferenceCode = t.ReferenceCode,
                Reason = t.Reason,
                PerformedByName = t.PerformedBy?.FullName
            }).ToList();

            var report = new AssetStockLedgerReportDto
            {
                TotalCount = items.Count,
                TotalStockIn = transactions.Where(t => t.TransactionType == StockTransactionType.StockIn)
                    .Sum(t => t.Quantity),
                TotalStockOut = transactions.Where(t => t.TransactionType == StockTransactionType.StockOut)
                    .Sum(t => Math.Abs(t.Quantity)),
                TotalAdjustments = transactions.Count(t => t.TransactionType == StockTransactionType.Adjustment),
                Items = items
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Nhap xuat kho",
                    ["Ngày", "Loại", "Mã TS", "Tên", "SL", "Tồn sau", "Mã phiếu", "Lý do", "Người TH"],
                    (ws, dataStartRow) => { var row = dataStartRow;
                        foreach (var i in items)
                        {
                            ReportHelpers.DateCell(ws.Cell(row, 1), i.TransactionDate);
                            ws.Cell(row, 2).Value = i.TransactionTypeName;
                            ws.Cell(row, 3).Value = i.AssetCode;
                            ws.Cell(row, 4).Value = i.AssetName;
                            ws.Cell(row, 5).Value = i.Quantity;
                            ws.Cell(row, 6).Value = i.BalanceAfter;
                            ws.Cell(row, 7).Value = i.ReferenceCode ?? "";
                            ws.Cell(row, 8).Value = i.Reason ?? "";
                            ws.Cell(row, 9).Value = i.PerformedByName ?? "";
                            row++;
                        }
                    },
                    "asset-stock-ledger.xlsx", user: User);
            }

            return Ok(AppResponse<AssetStockLedgerReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Asset stock ledger report failed");
            return StatusCode(500, AppResponse<AssetStockLedgerReportDto>.Fail(ex.Message));
        }
    }

    // GET /api/reports/assets/inventory-variance?inventoryId=&onlyVariance=true&inventoryStatus=&format=excel
    [HttpGet("inventory-variance")]
    [RequireModulePermission("AssetReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetInventoryVariance(
        [FromQuery] Guid? inventoryId = null,
        [FromQuery] bool onlyVariance = true,
        [FromQuery] int? inventoryStatus = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var storeId = RequiredStoreId;
            var (_, toLocal, _, _) = ReportHelpers.VnRange(from, to);

            var invQ = db.AssetInventories.AsNoTracking()
                .Where(i => i.StoreId == storeId);

            if (inventoryId.HasValue)
                invQ = invQ.Where(i => i.Id == inventoryId.Value);
            if (inventoryStatus.HasValue)
                invQ = invQ.Where(i => i.Status == inventoryStatus.Value);
            if (from.HasValue)
                invQ = invQ.Where(i => i.StartDate >= from.Value.Date);
            if (to.HasValue)
                invQ = invQ.Where(i => i.StartDate <= toLocal);

            var inventoryIds = await invQ.Select(i => i.Id).ToListAsync(ct);

            var itemQ = db.AssetInventoryItems.AsNoTracking()
                .Include(x => x.Asset)
                .Include(x => x.Inventory)
                .Where(x => inventoryIds.Contains(x.InventoryId) && x.IsChecked);

            if (onlyVariance)
            {
                itemQ = itemQ.Where(x =>
                    x.QuantityMismatch ||
                    x.HasIssue ||
                    x.Condition == InventoryCondition.NotFound);
            }

            var raw = await itemQ.OrderBy(x => x.Inventory!.InventoryCode).ThenBy(x => x.Asset!.AssetCode)
                .ToListAsync(ct);

            var items = raw.Select(x =>
            {
                var expected = x.StoredExpectedQuantity > 0
                    ? x.StoredExpectedQuantity
                    : (x.Asset?.Quantity ?? 0);
                var actual = x.ActualQuantity ?? 0;
                return new AssetInventoryVarianceRowDto
                {
                    InventoryCode = x.Inventory?.InventoryCode ?? "",
                    InventoryName = x.Inventory?.Name ?? "",
                    InventoryStatusName = AssetReportLabels.InventoryStatus(x.Inventory?.Status ?? 0),
                    AssetCode = x.Asset?.AssetCode ?? "",
                    AssetName = x.Asset?.Name ?? "",
                    ExpectedQuantity = expected,
                    ActualQuantity = x.ActualQuantity,
                    Variance = actual - expected,
                    QuantityMismatch = x.QuantityMismatch,
                    HasIssue = x.HasIssue,
                    ConditionName = x.Condition.HasValue
                        ? AssetReportLabels.Condition(x.Condition.Value)
                        : null,
                    IssueDescription = x.IssueDescription,
                    ActualLocation = x.ActualLocation,
                    CheckedAt = x.CheckedAt.HasValue ? ReportHelpers.ToVn(x.CheckedAt.Value) : null
                };
            }).ToList();

            var report = new AssetInventoryVarianceReportDto
            {
                TotalCount = items.Count,
                VarianceCount = items.Count(i => i.QuantityMismatch),
                IssueCount = items.Count(i => i.HasIssue),
                Items = items
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Kiem ke chenh lech",
                    ["Đợt KK", "Mã TS", "Tên", "SL kỳ vọng", "SL thực tế", "Chênh", "Tình trạng", "Vấn đề", "Mô tả"],
                    (ws, dataStartRow) => { var row = dataStartRow;
                        foreach (var i in items)
                        {
                            ws.Cell(row, 1).Value = i.InventoryCode;
                            ws.Cell(row, 2).Value = i.AssetCode;
                            ws.Cell(row, 3).Value = i.AssetName;
                            ws.Cell(row, 4).Value = i.ExpectedQuantity;
                            ws.Cell(row, 5).Value = i.ActualQuantity ?? 0;
                            ws.Cell(row, 6).Value = i.Variance;
                            ws.Cell(row, 7).Value = i.ConditionName ?? "";
                            ws.Cell(row, 8).Value = i.HasIssue ? "Có" : "";
                            ws.Cell(row, 9).Value = i.IssueDescription ?? "";
                            row++;
                        }
                    },
                    "asset-inventory-variance.xlsx", user: User);
            }

            return Ok(AppResponse<AssetInventoryVarianceReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Asset inventory variance report failed");
            return StatusCode(500, AppResponse<AssetInventoryVarianceReportDto>.Fail(ex.Message));
        }
    }

    // GET /api/reports/assets/warranty-expiring?days=30&includeExpired=false&format=excel
    [HttpGet("warranty-expiring")]
    [RequireModulePermission("AssetReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetWarrantyExpiring(
        [FromQuery] int days = 30,
        [FromQuery] bool includeExpired = false,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            if (days < 1) days = 30;
            if (days > 365) days = 365;

            var now = DateTime.UtcNow;
            var windowEnd = now.AddDays(days);

            var assets = await QueryAssets(null, null, null).ToListAsync(ct);

            var candidates = assets
                .Where(a => a.WarrantyExpiry.HasValue)
                .Where(a => includeExpired
                    ? a.WarrantyExpiry!.Value <= windowEnd
                    : a.WarrantyExpiry!.Value > now && a.WarrantyExpiry.Value <= windowEnd)
                .Select(a =>
                {
                    var daysLeft = (int)(a.WarrantyExpiry!.Value.Date - now.Date).TotalDays;
                    return new AssetWarrantyExpiringRowDto
                    {
                        AssetCode = a.AssetCode,
                        Name = a.Name,
                        CategoryName = a.Category?.Name,
                        StatusName = AssetReportLabels.Status(a.Status),
                        WarrantyExpiry = a.WarrantyExpiry,
                        DaysRemaining = daysLeft,
                        IsExpired = daysLeft < 0,
                        AssigneeName = a.CurrentAssigneeName,
                        SerialNumber = a.SerialNumber
                    };
                })
                .OrderBy(i => i.DaysRemaining)
                .ToList();

            var report = new AssetWarrantyExpiringReportDto
            {
                DaysWindow = days,
                TotalCount = candidates.Count,
                ExpiredCount = candidates.Count(i => i.IsExpired),
                ExpiringSoonCount = candidates.Count(i => !i.IsExpired),
                Items = candidates
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Bao hanh sap het",
                    ["Mã TS", "Tên", "Danh mục", "Trạng thái", "Hết BH", "Còn (ngày)", "Người giữ", "Serial"],
                    (ws, dataStartRow) => { var row = dataStartRow;
                        foreach (var i in candidates)
                        {
                            ws.Cell(row, 1).Value = i.AssetCode;
                            ws.Cell(row, 2).Value = i.Name;
                            ws.Cell(row, 3).Value = i.CategoryName ?? "";
                            ws.Cell(row, 4).Value = i.StatusName;
                            if (i.WarrantyExpiry.HasValue)
                                ReportHelpers.DateCell(ws.Cell(row, 5), i.WarrantyExpiry.Value);
                            ws.Cell(row, 6).Value = i.DaysRemaining;
                            ws.Cell(row, 7).Value = i.AssigneeName ?? "";
                            ws.Cell(row, 8).Value = i.SerialNumber ?? "";
                            row++;
                        }
                    },
                    "asset-warranty-expiring.xlsx", user: User);
            }

            return Ok(AppResponse<AssetWarrantyExpiringReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Asset warranty expiring report failed");
            return StatusCode(500, AppResponse<AssetWarrantyExpiringReportDto>.Fail(ex.Message));
        }
    }

    private IQueryable<Domain.Entities.Asset> QueryAssets(
        AssetStatus? status,
        AssetType? assetType,
        Guid? categoryId,
        string? search = null)
    {
        var storeId = RequiredStoreId;
        var q = db.Assets.AsNoTracking()
            .Include(a => a.Category)
            .Include(a => a.CurrentAssignee)
            .Where(a => a.StoreId == storeId && a.IsActive);

        if (status.HasValue) q = q.Where(a => a.Status == status.Value);
        if (assetType.HasValue) q = q.Where(a => a.AssetType == assetType.Value);
        if (categoryId.HasValue) q = q.Where(a => a.CategoryId == categoryId);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            q = q.Where(a =>
                a.AssetCode.Contains(s) ||
                a.Name.Contains(s) ||
                (a.SerialNumber != null && a.SerialNumber.Contains(s)) ||
                (a.QrCode != null && a.QrCode.Contains(s)));
        }

        return q;
    }

    private static AssetStatisticsDto BuildStatistics(List<Domain.Entities.Asset> assets)
    {
        var now = DateTime.UtcNow;
        var warningDate = now.AddDays(30);

        return new AssetStatisticsDto
        {
            TotalAssets = assets.Count,
            ActiveAssets = assets.Count(a => a.Status == AssetStatus.Active),
            InStockAssets = assets.Count(a => a.Status == AssetStatus.InStock),
            AssignedAssets = assets.Count(a => a.CurrentAssigneeId != null),
            MaintenanceAssets = assets.Count(a => a.Status == AssetStatus.InMaintenance),
            BrokenAssets = assets.Count(a => a.Status == AssetStatus.Broken),
            DisposedAssets = assets.Count(a => a.Status == AssetStatus.Disposed),
            TotalPurchaseValue = assets.Sum(a => a.PurchasePrice * a.Quantity),
            TotalCurrentValue = assets.Sum(a => (a.CurrentValue ?? a.PurchasePrice) * a.Quantity),
            WarrantyExpiringSoon = assets.Count(a =>
                a.WarrantyExpiry.HasValue &&
                a.WarrantyExpiry.Value <= warningDate &&
                a.WarrantyExpiry.Value > now),
            ByType = assets.GroupBy(a => a.AssetType).Select(g => new AssetByTypeDto
            {
                AssetType = g.Key,
                AssetTypeName = AssetReportLabels.Type(g.Key),
                Count = g.Count(),
                TotalValue = g.Sum(a => a.PurchasePrice * a.Quantity)
            }).OrderByDescending(x => x.Count).ToList(),
            ByCategory = assets.Where(a => a.CategoryId != null).GroupBy(a => new { a.CategoryId, a.Category!.Name })
                .Select(g => new AssetByCategoryDto
                {
                    CategoryId = g.Key.CategoryId,
                    CategoryName = g.Key.Name,
                    Count = g.Count(),
                    TotalValue = g.Sum(a => a.PurchasePrice * a.Quantity)
                }).OrderByDescending(x => x.Count).ToList(),
            ByAssignee = assets.Where(a => a.CurrentAssigneeId != null)
                .GroupBy(a => new { a.CurrentAssigneeId, a.CurrentAssignee!.FirstName, a.CurrentAssignee.LastName })
                .Select(g => new AssetByAssigneeDto
                {
                    AssigneeId = g.Key.CurrentAssigneeId?.ToString(),
                    AssigneeName = $"{g.Key.FirstName} {g.Key.LastName}".Trim(),
                    Count = g.Count(),
                    TotalValue = g.Sum(a => a.PurchasePrice * a.Quantity)
                }).OrderByDescending(x => x.Count).ToList(),
            ByStatus = assets.GroupBy(a => a.Status).Select(g => new AssetByStatusDto
            {
                Status = g.Key,
                StatusName = AssetReportLabels.Status(g.Key),
                Count = g.Count()
            }).ToList()
        };
    }

    private static AssetRegisterRowDto MapRegisterRow(Domain.Entities.Asset a) => new()
    {
        AssetCode = a.AssetCode,
        Name = a.Name,
        AssetTypeName = AssetReportLabels.Type(a.AssetType),
        CategoryName = a.Category?.Name,
        StatusName = AssetReportLabels.Status(a.Status),
        Quantity = a.Quantity,
        Unit = a.Unit,
        PurchasePrice = a.PurchasePrice,
        CurrentValue = a.CurrentValue,
        Location = a.Location,
        AssigneeName = a.CurrentAssigneeName,
        AssignedDate = a.AssignedDate,
        WarrantyExpiry = a.WarrantyExpiry,
        SerialNumber = a.SerialNumber
    };
}

internal static class AssetReportLabels
{
    public static string Type(AssetType type) => type switch
    {
        AssetType.Electronics => "Thiết bị điện tử",
        AssetType.Furniture => "Nội thất",
        AssetType.Vehicle => "Phương tiện",
        AssetType.Tool => "Công cụ dụng cụ",
        AssetType.Machinery => "Máy móc",
        AssetType.Software => "Phần mềm",
        _ => "Khác"
    };

    public static string Status(AssetStatus status) => status switch
    {
        AssetStatus.Active => "Đang sử dụng",
        AssetStatus.InMaintenance => "Đang bảo trì",
        AssetStatus.Broken => "Hỏng",
        AssetStatus.Disposed => "Đã thanh lý",
        AssetStatus.Lost => "Đã mất",
        AssetStatus.InStock => "Trong kho",
        _ => "Không xác định"
    };

    public static string TransferType(AssetTransferType type) => type switch
    {
        AssetTransferType.Assignment => "Cấp mới",
        AssetTransferType.Transfer => "Chuyển giao",
        AssetTransferType.Return => "Thu hồi",
        AssetTransferType.Maintenance => "Bảo trì",
        AssetTransferType.Disposal => "Thanh lý",
        _ => "Khác"
    };

    public static string StockType(StockTransactionType type) => type switch
    {
        StockTransactionType.StockIn => "Nhập kho",
        StockTransactionType.StockOut => "Xuất kho",
        StockTransactionType.Adjustment => "Điều chỉnh",
        _ => "Khác"
    };

    public static string InventoryStatus(int status) => status switch
    {
        0 => "Đang kiểm kê",
        1 => "Hoàn thành",
        2 => "Đã hủy",
        _ => "Không xác định"
    };

    public static string Condition(InventoryCondition condition) => condition switch
    {
        InventoryCondition.Good => "Tốt",
        InventoryCondition.Fair => "Bình thường",
        InventoryCondition.Poor => "Kém",
        InventoryCondition.Damaged => "Hỏng",
        InventoryCondition.NotFound => "Không tìm thấy",
        _ => "Không xác định"
    };
}
