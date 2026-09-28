using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services.Production;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Sản lượng: tính lại đơn giá, khóa sổ theo lương, báo cáo phân tích.</summary>
public partial class ProductionController
{
    public enum UpsertOutcome { Created, Updated, Locked }

    /// <summary>
    /// Ghi sản lượng từ Excel / Google Sheet: cùng NV + SP + ngày đã có → cập nhật số lượng
    /// (đồng bộ lại không nhân đôi); tháng đã chốt lương → bỏ qua.
    /// </summary>
    sealed class EntryUpserter(ZKTecoDbContext db, Guid storeId, string userId)
    {
        readonly Dictionary<DateTime, Dictionary<(Guid, Guid), ProductionEntry>> _byDate = [];
        HashSet<string>? _locked;

        public async Task<UpsertOutcome> UpsertAsync(
            Guid employeeId, Guid productItemId, DateTime workDate, decimal quantity, string note)
        {
            var date = workDate.Date;
            _locked ??= await LoadLockedAsync();
            if (_locked.Contains(ProductionPricing.LockKey(employeeId, date)))
                return UpsertOutcome.Locked;

            if (!_byDate.TryGetValue(date, out var existing))
            {
                existing = (await db.ProductionEntries.AsTracking()
                        .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkDate == date)
                        .ToListAsync())
                    .GroupBy(e => (e.EmployeeId, e.ProductItemId))
                    .ToDictionary(g => g.Key, g => g.First());
                _byDate[date] = existing;
            }

            if (existing.TryGetValue((employeeId, productItemId), out var row))
            {
                row.Quantity = quantity;
                row.Note = note;
                row.UpdatedAt = DateTime.Now;
                row.UpdatedBy = userId;
                return UpsertOutcome.Updated;
            }

            row = new ProductionEntry
            {
                EmployeeId = employeeId,
                ProductItemId = productItemId,
                WorkDate = date,
                Quantity = quantity,
                Note = note,
                StoreId = storeId,
                IsActive = true,
                CreatedBy = userId,
            };
            db.ProductionEntries.Add(row);
            existing[(employeeId, productItemId)] = row;
            return UpsertOutcome.Created;
        }

        async Task<HashSet<string>> LoadLockedAsync()
        {
            var years = new[] { DateTime.Now.Year - 1, DateTime.Now.Year, DateTime.Now.Year + 1 };
            var rows = await db.Payslips.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null && years.Contains(p.Year) &&
                            (p.Status == Domain.Enums.PayslipStatus.Approved ||
                             p.Status == Domain.Enums.PayslipStatus.Paid))
                .Select(p => new { p.EmployeeId, p.Year, p.Month })
                .ToListAsync();
            return rows.Select(r => ProductionPricing.LockKey(r.EmployeeId, r.Year, r.Month)).ToHashSet();
        }
    }

    /// <summary>Lưu rồi tính lại đơn giá lũy tiến cả tháng cho mọi (NV, SP, tháng) vừa thay đổi.</summary>
    async Task SaveAndRepriceAsync(Guid storeId)
    {
        var keys = new List<ProductionPriceKey>();
        foreach (var e in dbContext.ChangeTracker.Entries<ProductionEntry>())
        {
            if (e.State is not (EntityState.Added or EntityState.Modified or EntityState.Deleted)) continue;
            keys.Add(ProductionPriceKey.Of(e.Entity.EmployeeId, e.Entity.ProductItemId, e.Entity.WorkDate));
            if (e.State == EntityState.Modified)
            {
                // Đổi NV / SP / ngày: tháng cũ cũng phải tính lại.
                keys.Add(ProductionPriceKey.Of(
                    (Guid)e.OriginalValues[nameof(ProductionEntry.EmployeeId)]!,
                    (Guid)e.OriginalValues[nameof(ProductionEntry.ProductItemId)]!,
                    (DateTime)e.OriginalValues[nameof(ProductionEntry.WorkDate)]!));
            }
        }
        await dbContext.SaveChangesAsync();
        await ProductionPricing.RepriceAsync(dbContext, storeId, keys);
        await dbContext.SaveChangesAsync();
    }

    /// <summary>Tháng đã chốt lương (phiếu lương Đã duyệt / Đã trả) → không cho thêm / sửa / xóa sản lượng.</summary>
    async Task<string?> LockErrorAsync(Guid storeId, IEnumerable<(Guid EmployeeId, DateTime WorkDate)> items)
    {
        var list = items.ToList();
        var locked = await ProductionPricing.LockedEmployeeMonthsAsync(dbContext, storeId, list);
        var hit = list.FirstOrDefault(x => locked.Contains(ProductionPricing.LockKey(x.EmployeeId, x.WorkDate)));
        return hit == default
            ? null
            : $"Tháng {hit.WorkDate:MM/yyyy} của nhân viên này đã chốt lương (phiếu lương đã duyệt / đã trả) — " +
              "không sửa sản lượng được. Hủy duyệt phiếu lương nếu cần điều chỉnh.";
    }

    async Task<bool> ItemCodeTakenAsync(Guid storeId, string? code, Guid? exceptId)
    {
        var c = (code ?? "").Trim();
        if (c.Length == 0) return false;
        return await dbContext.ProductItems.AnyAsync(p =>
            p.StoreId == storeId && p.Deleted == null && p.Code == c &&
            (!exceptId.HasValue || p.Id != exceptId.Value));
    }

    public record RepriceMonthDto(int Year, int Month, Guid? ProductItemId);

    /// <summary>
    /// Tính lại đơn giá / thành tiền cả tháng theo bảng giá hiện tại (sau khi sửa bậc giá).
    /// Nhân viên đã chốt lương tháng đó được giữ nguyên.
    /// </summary>
    [HttpPost("reprice")]
    [RequireModulePermission("Production", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> RepriceMonth([FromBody] RepriceMonthDto dto)
    {
        if (dto.Month is < 1 or > 12)
            return BadRequest(AppResponse<object>.Fail("Tháng không hợp lệ"));
        var storeId = RequiredStoreId;
        var monthStart = new DateTime(dto.Year, dto.Month, 1);
        var monthEnd = monthStart.AddMonths(1);
        var pairs = await dbContext.ProductionEntries.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null &&
                        e.WorkDate >= monthStart && e.WorkDate < monthEnd &&
                        (!dto.ProductItemId.HasValue || e.ProductItemId == dto.ProductItemId.Value))
            .Select(e => new { e.EmployeeId, e.ProductItemId })
            .Distinct()
            .ToListAsync();
        var locked = await ProductionPricing.LockedEmployeeMonthsAsync(
            dbContext, storeId, pairs.Select(p => (p.EmployeeId, monthStart)));
        var keys = pairs
            .Where(p => !locked.Contains(ProductionPricing.LockKey(p.EmployeeId, monthStart)))
            .Select(p => new ProductionPriceKey(p.EmployeeId, p.ProductItemId, monthStart))
            .ToList();
        var before = await MonthAmountAsync(storeId, monthStart, monthEnd, dto.ProductItemId);
        await ProductionPricing.RepriceAsync(dbContext, storeId, keys);
        await dbContext.SaveChangesAsync();
        var after = await MonthAmountAsync(storeId, monthStart, monthEnd, dto.ProductItemId);
        return Ok(AppResponse<object>.Success(new
        {
            repriced = keys.Count,
            lockedSkipped = pairs.Count - keys.Count,
            amountBefore = before,
            amountAfter = after,
        }));
    }

    Task<decimal> MonthAmountAsync(Guid storeId, DateTime from, DateTime to, Guid? productItemId) =>
        dbContext.ProductionEntries.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkDate >= from && e.WorkDate < to &&
                        (!productItemId.HasValue || e.ProductItemId == productItemId.Value))
            .SumAsync(e => e.Amount ?? 0);

    /// <summary>
    /// Báo cáo sản lượng: tổng hợp, theo ngày, theo sản phẩm / nhóm, xếp hạng nhân viên,
    /// so sánh với kỳ trước cùng độ dài.
    /// </summary>
    [HttpGet("report")]
    [RequireModulePermission("Production", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetReport(
        [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate,
        [FromQuery] Guid? employeeId, [FromQuery] Guid? productGroupId)
    {
        var storeId = RequiredStoreId;
        if (IsEmployee && !IsManager)
        {
            if (!EmployeeId.HasValue)
                return Ok(AppResponse<object>.Success(new { }));
            employeeId = EmployeeId.Value;
        }
        var from = fromDate.Date;
        var to = toDate.Date.AddDays(1);
        if (to <= from) to = from.AddDays(1);

        IQueryable<ProductionEntry> Scope(DateTime a, DateTime b)
        {
            var q = dbContext.ProductionEntries.AsNoTracking()
                .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkDate >= a && e.WorkDate < b);
            if (employeeId.HasValue) q = q.Where(e => e.EmployeeId == employeeId.Value);
            if (productGroupId.HasValue) q = q.Where(e => e.ProductItem.ProductGroupId == productGroupId.Value);
            return q;
        }

        var rows = await Scope(from, to)
            .Select(e => new
            {
                e.EmployeeId,
                EmployeeName = (e.Employee.LastName + " " + e.Employee.FirstName).Trim(),
                e.Employee.EmployeeCode,
                e.Employee.Department,
                e.ProductItemId,
                ProductName = e.ProductItem.Name,
                ProductCode = e.ProductItem.Code,
                e.ProductItem.Unit,
                GroupId = e.ProductItem.ProductGroupId,
                GroupName = e.ProductItem.ProductGroup.Name,
                e.WorkDate,
                e.Quantity,
                Amount = e.Amount ?? 0,
            })
            .ToListAsync();

        var span = to - from;
        var prev = await Scope(from - span, from)
            .GroupBy(_ => 1)
            .Select(g => new { Qty = g.Sum(e => e.Quantity), Amount = g.Sum(e => e.Amount ?? 0) })
            .FirstOrDefaultAsync();

        var totalQty = rows.Sum(r => r.Quantity);
        var totalAmount = rows.Sum(r => r.Amount);
        var employees = rows.Select(r => r.EmployeeId).Distinct().Count();
        var workDays = rows.Select(r => r.WorkDate.Date).Distinct().Count();

        static decimal? Change(decimal now, decimal? before) =>
            before is > 0 ? Math.Round((now - before.Value) / before.Value * 100m, 1) : null;

        var byEmployee = rows
            .GroupBy(r => r.EmployeeId)
            .Select(g =>
            {
                var days = g.Select(x => x.WorkDate.Date).Distinct().Count();
                var amount = g.Sum(x => x.Amount);
                return new
                {
                    employeeId = g.Key,
                    employeeCode = g.First().EmployeeCode,
                    employeeName = g.First().EmployeeName,
                    department = g.First().Department,
                    quantity = g.Sum(x => x.Quantity),
                    amount,
                    workDays = days,
                    amountPerDay = days > 0 ? Math.Round(amount / days, 0) : 0,
                    products = g.Select(x => x.ProductItemId).Distinct().Count(),
                };
            })
            .OrderByDescending(x => x.amount)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            from,
            to = to.AddDays(-1),
            totals = new
            {
                quantity = totalQty,
                amount = totalAmount,
                entries = rows.Count,
                employees,
                products = rows.Select(r => r.ProductItemId).Distinct().Count(),
                workDays,
                amountPerEmployee = employees > 0 ? Math.Round(totalAmount / employees, 0) : 0,
                amountPerDay = workDays > 0 ? Math.Round(totalAmount / workDays, 0) : 0,
                previousQuantity = prev?.Qty ?? 0,
                previousAmount = prev?.Amount ?? 0,
                quantityChangePct = Change(totalQty, prev?.Qty),
                amountChangePct = Change(totalAmount, prev?.Amount),
            },
            daily = rows
                .GroupBy(r => r.WorkDate.Date)
                .OrderBy(g => g.Key)
                .Select(g => new
                {
                    date = g.Key.ToString("yyyy-MM-dd"),
                    quantity = g.Sum(x => x.Quantity),
                    amount = g.Sum(x => x.Amount),
                    employees = g.Select(x => x.EmployeeId).Distinct().Count(),
                }),
            byProduct = rows
                .GroupBy(r => r.ProductItemId)
                .Select(g => new
                {
                    productItemId = g.Key,
                    code = g.First().ProductCode,
                    name = g.First().ProductName,
                    unit = g.First().Unit,
                    groupName = g.First().GroupName,
                    quantity = g.Sum(x => x.Quantity),
                    amount = g.Sum(x => x.Amount),
                    avgUnitPrice = g.Sum(x => x.Quantity) > 0
                        ? Math.Round(g.Sum(x => x.Amount) / g.Sum(x => x.Quantity), 0) : 0,
                    employees = g.Select(x => x.EmployeeId).Distinct().Count(),
                })
                .OrderByDescending(x => x.amount),
            byGroup = rows
                .GroupBy(r => r.GroupId)
                .Select(g => new
                {
                    groupId = g.Key,
                    name = g.First().GroupName,
                    quantity = g.Sum(x => x.Quantity),
                    amount = g.Sum(x => x.Amount),
                })
                .OrderByDescending(x => x.amount),
            byEmployee,
        }));
    }
}
