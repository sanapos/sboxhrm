using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

public static class PosStaffCommissionHelper
{
    public record StaffAssignDto(Guid? ComponentProductId, Guid AssignedEmployeeId, string? AssignedEmployeeName);

    static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public static string? SerializeAssignments(IReadOnlyList<StaffAssignDto>? rows)
    {
        if (rows == null || rows.Count == 0) return null;
        return JsonSerializer.Serialize(rows, JsonOpts);
    }

    public static List<StaffAssignDto> ParseAssignments(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return JsonSerializer.Deserialize<List<StaffAssignDto>>(json, JsonOpts) ?? [];
        }
        catch
        {
            return [];
        }
    }

    public static async Task<string?> ValidateRequiredStaffAsync(
        ZKTecoDbContext db,
        Guid storeId,
        IReadOnlyList<PosSaleOrderLine> lines,
        IReadOnlyDictionary<Guid, PosProduct> products,
        bool requireStaffOnService)
    {
        if (!requireStaffOnService) return null;

        var comboIds = lines
            .Where(l => products.TryGetValue(l.ProductId, out var p) && p.ProductType == PosProductType.Combo)
            .Select(l => l.ProductId)
            .Distinct()
            .ToList();
        var comboMap = comboIds.Count == 0
            ? new Dictionary<Guid, List<PosProductComboLine>>()
            : await db.PosProductComboLines.AsNoTracking()
                .Include(c => c.ComponentProduct)
                .Where(c => comboIds.Contains(c.ComboProductId) && c.Deleted == null)
                .GroupBy(c => c.ComboProductId)
                .ToDictionaryAsync(g => g.Key, g => g.ToList());

        foreach (var line in lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p)) continue;
            var assigns = ParseAssignments(line.StaffAssignmentsJson);
            if (IsPerSessionPack(p)) continue;
            if (p.ProductType == PosProductType.Service &&
                line.AssignedEmployeeId == null &&
                assigns.All(a => a.AssignedEmployeeId == Guid.Empty))
                return $"«{p.Name}» là dịch vụ — cần chọn nhân viên làm";

            if (p.ProductType != PosProductType.Combo) continue;
            if (!comboMap.TryGetValue(p.Id, out var comps)) continue;
            foreach (var cl in comps)
            {
                if (cl.ComponentProduct?.ProductType != PosProductType.Service) continue;
                if (IsPerSessionComponent(p, cl.ComponentProduct)) continue;
                var hit = assigns.FirstOrDefault(a => a.ComponentProductId == cl.ComponentProductId);
                if (hit == null && line.AssignedEmployeeId == null)
                    return $"Combo «{p.Name}»: chưa chọn NV cho «{cl.ComponentProduct.Name}»";
            }
        }

        return null;
    }

    /// <summary>Gói nhiều buổi (không phải thẻ thời gian) chọn «hoa hồng mỗi buổi».</summary>
    public static bool IsPerSessionPack(PosProduct p) =>
        p.CommissionPerSession && p.SessionPackCount > 0
        && !PosCustomerSessionBalance.IsUnlimitedCount(p.SessionPackCount);

    /// <summary>Thành phần combo là liệu trình nhiều buổi, combo hoặc chính nó chọn «hoa hồng mỗi buổi».</summary>
    public static bool IsPerSessionComponent(PosProduct combo, PosProduct? component) =>
        component != null && component.SessionPackCount > 0
        && !PosCustomerSessionBalance.IsUnlimitedCount(component.SessionPackCount)
        && (combo.CommissionPerSession || component.CommissionPerSession);

    /// <summary>
    /// Trừ buổi gói liệu trình: nếu gói tính hoa hồng mỗi buổi → ghi hoa hồng cho NV làm buổi.
    /// Doanh thu 1 buổi = tiền dòng bán gói (hoặc phần combo phân bổ) / tổng số buổi của gói.
    /// </summary>
    public static async Task<PosSaleCommissionLine?> AddSessionCommissionAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosCustomerSessionBalance balance,
        Guid sessionTxnId,
        int sessions,
        Guid employeeId,
        string? employeeName,
        DateTime performedAt,
        string? createdBy)
    {
        if (balance.ProductId is not Guid packProductId || sessions <= 0 || balance.TotalSessions <= 0
            || PosCustomerSessionBalance.IsUnlimitedCount(balance.TotalSessions))
            return null;
        var purchaseOrderId = await db.PosCustomerSessionTransactions.AsNoTracking()
            .Where(t => t.BalanceId == balance.Id && t.Deleted == null
                        && t.TransactionType == PosSessionTxnType.Purchase && t.SaleOrderId != null)
            .Select(t => t.SaleOrderId)
            .FirstOrDefaultAsync();
        if (purchaseOrderId is not Guid orderId) return null;

        var lines = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.SaleOrderId == orderId && l.Deleted == null)
            .ToListAsync();
        if (lines.Count == 0) return null;
        var productIds = lines.Select(l => l.ProductId).Append(packProductId).Distinct().ToList();
        var products = await db.PosProducts.AsNoTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId)
            .ToDictionaryAsync(p => p.Id);
        if (!products.TryGetValue(packProductId, out var pack)) return null;

        PosSaleOrderLine? srcLine = null;
        Guid? comboId = null;
        decimal packRevenue = 0;
        decimal catalogPrice = pack.BasePrice;

        // 1) Gói bán lẻ: dòng đơn chính là gói.
        var direct = lines.Where(l => l.ProductId == packProductId).ToList();
        if (direct.Count > 0 && IsPerSessionPack(pack))
        {
            srcLine = direct.FirstOrDefault(l =>
                          pack.SessionPackCount * (int)Math.Max(1, Math.Round(l.Qty)) == balance.TotalSessions)
                      ?? direct[0];
            packRevenue = srcLine.LineTotal;
            catalogPrice = balance.TotalSessions > 0
                ? pack.BasePrice * Math.Max(1, srcLine.Qty) / balance.TotalSessions
                : pack.BasePrice;
        }
        else
        {
            // 2) Liệu trình trong combo: lấy phần doanh thu combo phân bổ cho thành phần này.
            var comboLineIds = lines
                .Where(l => products.TryGetValue(l.ProductId, out var p) && p.ProductType == PosProductType.Combo)
                .ToList();
            if (comboLineIds.Count == 0) return null;
            var cids = comboLineIds.Select(l => l.ProductId).Distinct().ToList();
            var comps = await db.PosProductComboLines.AsNoTracking()
                .Include(c => c.ComponentProduct)
                .Where(c => cids.Contains(c.ComboProductId) && c.Deleted == null)
                .ToListAsync();
            foreach (var cl in comboLineIds)
            {
                var myComps = comps.Where(c => c.ComboProductId == cl.ProductId).ToList();
                if (myComps.All(c => c.ComponentProductId != packProductId)) continue;
                var combo = products[cl.ProductId];
                if (!IsPerSessionComponent(combo, pack)) return null;
                var share = PosStaffCommissionMath.AllocateComboRevenue(
                        cl.LineTotal, cl.Qty,
                        myComps.Select(c => (c.ComponentProductId, c.Qty, c.ComponentProduct?.BasePrice ?? 0m)).ToList())
                    .FirstOrDefault(x => x.ProductId == packProductId);
                if (share == null) continue;
                srcLine = cl;
                comboId = combo.Id;
                packRevenue = share.Revenue;
                catalogPrice = balance.TotalSessions > 0
                    ? share.CatalogPrice * share.Qty / balance.TotalSessions
                    : share.CatalogPrice;
                break;
            }
            if (srcLine == null) return null;
        }

        var revenue = Math.Round(packRevenue * sessions / balance.TotalSessions, 0, MidpointRounding.AwayFromZero);
        var row = new PosSaleCommissionLine
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SaleOrderId = orderId,
            SaleOrderLineId = srcLine.Id,
            ProductId = pack.Id,
            ProductName = $"{pack.Name} (buổi)",
            ParentComboProductId = comboId,
            EmployeeId = employeeId,
            EmployeeName = employeeName ?? "",
            Qty = sessions,
            RevenueAmount = revenue,
            CommissionMode = pack.CommissionMode,
            CommissionPercent = pack.CommissionPercent,
            CommissionFixed = pack.CommissionFixed,
            // Cố định = tiền mỗi buổi; % giá niêm yết = % giá 1 buổi theo niêm yết.
            CommissionAmount = PosStaffCommissionMath.CalcCommission(
                pack.CommissionMode, pack.CommissionPercent, pack.CommissionFixed,
                revenue, sessions, catalogPrice),
            PerformedAt = performedAt,
            SessionTransactionId = sessionTxnId,
            IsActive = true,
            CreatedBy = createdBy,
        };
        db.PosSaleCommissionLines.Add(row);
        return row;
    }

    public static async Task ReplaceLinesAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        IReadOnlyList<PosSaleOrderLine> lines,
        IReadOnlyDictionary<Guid, PosProduct> products,
        string? createdBy)
    {
        var old = await db.PosSaleCommissionLines
            .Where(x => x.SaleOrderId == order.Id && x.Deleted == null && x.SessionTransactionId == null)
            .ToListAsync();
        if (old.Count > 0) db.PosSaleCommissionLines.RemoveRange(old);

        if (lines.Count == 0) return;

        var comboIds = lines
            .Where(l => products.TryGetValue(l.ProductId, out var p) && p.ProductType == PosProductType.Combo)
            .Select(l => l.ProductId)
            .Distinct()
            .ToList();
        var comboMap = comboIds.Count == 0
            ? new Dictionary<Guid, List<PosProductComboLine>>()
            : await db.PosProductComboLines.AsNoTracking()
                .Include(c => c.ComponentProduct)
                .Where(c => comboIds.Contains(c.ComboProductId) && c.StoreId == storeId && c.Deleted == null)
                .GroupBy(c => c.ComboProductId)
                .ToDictionaryAsync(g => g.Key, g => g.ToList());

        var employeeIds = new HashSet<Guid>();
        foreach (var line in lines)
        {
            if (line.AssignedEmployeeId is { } aid) employeeIds.Add(aid);
            foreach (var a in ParseAssignments(line.StaffAssignmentsJson))
                if (a.AssignedEmployeeId != Guid.Empty) employeeIds.Add(a.AssignedEmployeeId);
        }

        var empNames = employeeIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await db.Employees.AsNoTracking()
                .Where(e => employeeIds.Contains(e.Id) && e.Deleted == null)
                .ToDictionaryAsync(e => e.Id, e => (e.LastName + " " + e.FirstName).Trim());

        foreach (var line in lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p)) continue;
            var assigns = ParseAssignments(line.StaffAssignmentsJson);

            if (p.ProductType == PosProductType.Combo &&
                comboMap.TryGetValue(p.Id, out var comps) &&
                comps.Count > 0)
            {
                var shares = PosStaffCommissionMath.AllocateComboRevenue(
                    line.LineTotal, line.Qty,
                    comps.Select(c => (
                        c.ComponentProductId,
                        c.Qty,
                        c.ComponentProduct?.BasePrice ?? 0m)).ToList());
                foreach (var share in shares)
                {
                    var comp = comps.First(c => c.ComponentProductId == share.ProductId);
                    var cp = comp.ComponentProduct;
                    // Liệu trình trong combo tính hoa hồng mỗi buổi → ghi lúc trừ buổi, không ghi lúc bán.
                    if (IsPerSessionComponent(p, cp)) continue;
                    var assign = assigns.FirstOrDefault(a => a.ComponentProductId == share.ProductId)
                                 ?? assigns.FirstOrDefault(a => a.ComponentProductId == null);
                    var empId = assign?.AssignedEmployeeId
                                ?? line.AssignedEmployeeId;
                    if (empId == null || empId == Guid.Empty) continue;
                    var mode = cp?.CommissionMode ?? PosCommissionMode.None;
                    var pct = cp?.CommissionPercent ?? 0;
                    var fix = cp?.CommissionFixed ?? 0;
                    empNames.TryGetValue(empId.Value, out var empName);
                    db.PosSaleCommissionLines.Add(new PosSaleCommissionLine
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        SaleOrderId = order.Id,
                        SaleOrderLineId = line.Id,
                        ProductId = share.ProductId,
                        ProductName = cp?.Name ?? share.ProductId.ToString(),
                        ParentComboProductId = p.Id,
                        EmployeeId = empId.Value,
                        EmployeeName = !string.IsNullOrWhiteSpace(assign?.AssignedEmployeeName)
                            ? assign!.AssignedEmployeeName!.Trim()
                            : (empName ?? ""),
                        Qty = share.Qty,
                        RevenueAmount = share.Revenue,
                        CommissionMode = mode,
                        CommissionPercent = pct,
                        CommissionFixed = fix,
                        CommissionAmount = PosStaffCommissionMath.CalcCommission(
                            mode, pct, fix, share.Revenue, share.Qty, share.CatalogPrice),
                        IsActive = true,
                        CreatedBy = createdBy,
                    });
                }
                continue;
            }

            if (IsPerSessionPack(p)) continue;
            var lineEmp = line.AssignedEmployeeId
                          ?? assigns.FirstOrDefault()?.AssignedEmployeeId;
            if (lineEmp == null || lineEmp == Guid.Empty) continue;
            empNames.TryGetValue(lineEmp.Value, out var name);
            db.PosSaleCommissionLines.Add(new PosSaleCommissionLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                SaleOrderId = order.Id,
                SaleOrderLineId = line.Id,
                ProductId = p.Id,
                ProductName = line.ProductName,
                ParentComboProductId = null,
                EmployeeId = lineEmp.Value,
                EmployeeName = name ?? assigns.FirstOrDefault()?.AssignedEmployeeName?.Trim() ?? "",
                Qty = line.Qty,
                RevenueAmount = line.LineTotal,
                CommissionMode = p.CommissionMode,
                CommissionPercent = p.CommissionPercent,
                CommissionFixed = p.CommissionFixed,
                CommissionAmount = PosStaffCommissionMath.CalcCommission(
                    p.CommissionMode, p.CommissionPercent, p.CommissionFixed,
                    line.LineTotal, line.Qty, p.BasePrice),
                IsActive = true,
                CreatedBy = createdBy,
            });
        }
    }
}
