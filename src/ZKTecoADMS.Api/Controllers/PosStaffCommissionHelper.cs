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
            if (p.ProductType == PosProductType.Service &&
                line.AssignedEmployeeId == null &&
                assigns.All(a => a.AssignedEmployeeId == Guid.Empty))
                return $"«{p.Name}» là dịch vụ — cần chọn nhân viên làm";

            if (p.ProductType != PosProductType.Combo) continue;
            if (!comboMap.TryGetValue(p.Id, out var comps)) continue;
            foreach (var cl in comps)
            {
                if (cl.ComponentProduct?.ProductType != PosProductType.Service) continue;
                var hit = assigns.FirstOrDefault(a => a.ComponentProductId == cl.ComponentProductId);
                if (hit == null && line.AssignedEmployeeId == null)
                    return $"Combo «{p.Name}»: chưa chọn NV cho «{cl.ComponentProduct.Name}»";
            }
        }

        return null;
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
            .Where(x => x.SaleOrderId == order.Id && x.Deleted == null)
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
