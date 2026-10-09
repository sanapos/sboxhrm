using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Sổ seri máy: nhập kho → bán → trả khách / trả nhà cung cấp. Hàng bắt buộc seri đã có trong sổ thì khi bán
/// chỉ được chọn seri đang «trong kho»; cửa hàng chưa từng nhập seri (dữ liệu cũ) vẫn bán được như trước.
/// </summary>
public static class PosSerialRegistry
{
    /// <summary>Lọc máy đang ở chi nhánh [branch] (null = không lọc). Trụ sở khớp cả BranchId null lẫn id trụ sở.</summary>
    public static IQueryable<PosProductSerial> InBranch(this IQueryable<PosProductSerial> q, Guid? branch, Guid? hq)
    {
        if (branch == null) return q;
        var isHq = branch == hq;
        return q.Where(x => x.BranchId == branch || (isHq && x.BranchId == null));
    }

    public static string Normalize(string? s) => PosSaleWarrantyHelper.NormalizeSerial(s);

    /// <summary>Tách chuỗi nhiều seri (xuống dòng / ; / ,) → danh sách đã chuẩn hóa, giữ cả trùng để báo lỗi.</summary>
    public static List<string> Parse(string? text) =>
        string.IsNullOrWhiteSpace(text)
            ? []
            : text.Split(['\r', '\n', ';', ','], StringSplitOptions.RemoveEmptyEntries)
                .Select(Normalize).Where(x => x.Length > 0).ToList();

    public static string Join(IEnumerable<string>? serials) =>
        string.Join("\n", (serials ?? []).Select(Normalize).Where(x => x.Length > 0));

    /// <summary>Hàng đã quản lý seri trong sổ chưa.</summary>
    public static async Task<bool> IsTrackedAsync(ZKTecoDbContext db, Guid storeId, Guid productId) =>
        await db.PosProductSerials.AsNoTracking()
            .AnyAsync(x => x.StoreId == storeId && x.Deleted == null && x.ProductId == productId);

    /// <summary>
    /// Xuất kho / xuất hủy: hàng quản lý seri thì bỏ đúng các máy được chọn khỏi kho; không chọn → lấy theo thứ tự
    /// nhập (FIFO). Ném InvalidOperationException nếu không đủ máy trong kho.
    /// </summary>
    public static async Task IssueAsync(
        ZKTecoDbContext db, Guid storeId, PosStockIssue issue,
        IReadOnlyList<PosStockIssueLine> lines, IReadOnlyDictionary<Guid, PosProduct> products, string? by,
        Guid? hqBranchId = null)
    {
        foreach (var line in lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p) || !p.RequiresSerial) continue;
            // Xuất kho theo báo giá chỉ trừ tồn; seri được chọn khi lập biên bản bàn giao / nghiệm thu.
            if (issue.QuoteId.HasValue) continue;
            if (!await IsTrackedAsync(db, storeId, p.Id)) continue;

            var units = (int)Math.Ceiling(line.Qty);
            var wanted = Parse(line.SerialNumbersText);
            List<PosProductSerial> rows;
            if (wanted.Count > 0)
            {
                if (wanted.Count != units)
                    throw new InvalidOperationException($"«{line.ProductName}» cần chọn đủ {units} seri (đang có {wanted.Count})");
                rows = await db.PosProductSerials.AsTracking()
                    .Where(x => x.StoreId == storeId && x.ProductId == p.Id && x.Deleted == null &&
                                x.Status == PosSerialStatus.InStock && wanted.Contains(x.SerialNumber))
                    .ToListAsync();
                if (rows.Count != wanted.Count)
                    throw new InvalidOperationException(
                        $"Seri không còn trong kho: {string.Join(", ", wanted.Except(rows.Select(r => r.SerialNumber)))}");
            }
            else
            {
                rows = await db.PosProductSerials.AsTracking()
                    .Where(x => x.StoreId == storeId && x.ProductId == p.Id && x.Deleted == null &&
                                x.Status == PosSerialStatus.InStock && x.TransferId == null)
                    .InBranch(issue.BranchId, hqBranchId)
                    .OrderBy(x => x.ReceivedDate).ThenBy(x => x.SerialNumber)
                    .Take(units).ToListAsync();
                if (rows.Count < units)
                    throw new InvalidOperationException(
                        $"Không đủ seri trong kho cho «{line.ProductName}» (cần {units}, còn {rows.Count})");
                line.SerialNumbersText = Join(rows.Select(r => r.SerialNumber));
            }
            // Giao khách theo báo giá → máy ở chỗ khách («Sold»); xuất hủy / dùng nội bộ → ra khỏi kho («Removed»).
            var toCustomer = issue.QuoteId.HasValue;
            foreach (var r in rows)
            {
                r.Status = toCustomer ? PosSerialStatus.Sold : PosSerialStatus.Removed;
                r.SoldDate = toCustomer ? DateTime.UtcNow : null;
                r.Note = toCustomer ? $"Giao khách theo phiếu {issue.IssueNo}" : $"Xuất kho {issue.IssueNo}";
                r.UpdatedAt = DateTime.UtcNow;
                r.UpdatedBy = by;
            }
        }
    }

    /// <summary>
    /// Bàn giao / nghiệm thu: gán seri máy cho dòng báo giá. Máy chọn phải đang trong kho đúng mặt hàng
    /// (hoặc đã gán cho chính dòng này). Dòng đã có seri được thay bằng lựa chọn mới. Trả lỗi (null nếu ổn).
    /// </summary>
    public static async Task<string?> AssignQuoteSerialsAsync(
        ZKTecoDbContext db, Guid storeId, PosQuote quote, IReadOnlyDictionary<Guid, List<string>>? picks, string? by)
    {
        var lines = quote.Lines.Where(l => l.Deleted == null && l.ProductId.HasValue && l.Qty > 0).ToList();
        var needIds = await SerialProductIdsAsync(db, storeId, lines.Select(l => l.ProductId!.Value));
        var needLines = lines.Where(l => needIds.Contains(l.ProductId!.Value)).ToList();
        if (needLines.Count == 0) return null;

        var all = new List<string>();
        foreach (var l in needLines)
        {
            var units = (int)Math.Ceiling(l.Qty);
            List<string> serials;
            if (picks != null && picks.TryGetValue(l.Id, out var p) && p.Count > 0)
                serials = p.Select(Normalize).Where(x => x.Length > 0).ToList();
            else
            {
                var existing = Parse(l.SerialNumbersText);
                if (existing.Count == units) continue; // đã gán đủ từ trước
                return $"Chọn đủ {units} seri máy giao khách cho «{l.ProductName}»";
            }
            if (serials.Count != units)
                return $"«{l.ProductName}» cần chọn đủ {units} seri (đang có {serials.Count})";
            if (serials.Count != serials.Distinct().Count())
                return $"Seri bị trùng trong «{l.ProductName}»";
            all.AddRange(serials);
        }
        if (all.Count != all.Distinct().Count())
            return "Một seri không thể giao cho hai dòng hàng";

        var note = $"Bàn giao báo giá {quote.QuoteNo}";
        foreach (var l in needLines)
        {
            if (picks == null || !picks.TryGetValue(l.Id, out var p) || p.Count == 0) continue;
            var serials = p.Select(Normalize).Where(x => x.Length > 0).ToList();
            var old = Parse(l.SerialNumbersText);

            // Trả máy gán trước đó về kho rồi gán lại theo lựa chọn mới.
            if (old.Count > 0)
            {
                var oldRows = await db.PosProductSerials.AsTracking()
                    .Where(x => x.StoreId == storeId && x.ProductId == l.ProductId && x.Deleted == null &&
                                x.Status == PosSerialStatus.Sold && x.Note == note && old.Contains(x.SerialNumber))
                    .ToListAsync();
                foreach (var r in oldRows) { r.Status = PosSerialStatus.InStock; r.SoldDate = null; r.Note = null; }
            }

            var rows = await db.PosProductSerials.AsTracking()
                .Where(x => x.StoreId == storeId && x.ProductId == l.ProductId && x.Deleted == null &&
                            x.Status == PosSerialStatus.InStock && serials.Contains(x.SerialNumber))
                .ToListAsync();
            if (rows.Count != serials.Count)
            {
                var found = rows.Select(r => r.SerialNumber).ToHashSet();
                return $"Seri không còn trong kho: {string.Join(", ", serials.Where(s => !found.Contains(s)))}";
            }
            foreach (var r in rows)
            {
                r.Status = PosSerialStatus.Sold;
                r.SoldDate = DateTime.UtcNow;
                r.Note = note;
                r.UpdatedAt = DateTime.UtcNow;
                r.UpdatedBy = by;
            }
            l.SerialNumbersText = Join(serials);
        }
        return null;
    }

    /// <summary>Hủy phiếu xuất → máy về lại kho (chỉ các máy do chính phiếu đó lấy ra).</summary>
    public static async Task RestoreIssueAsync(
        ZKTecoDbContext db, Guid storeId, PosStockIssue issue, IReadOnlyList<PosStockIssueLine> lines)
    {
        foreach (var line in lines)
        {
            var serials = Parse(line.SerialNumbersText);
            if (serials.Count == 0) continue;
            var rows = await db.PosProductSerials.AsTracking()
                .Where(x => x.StoreId == storeId && x.ProductId == line.ProductId && x.Deleted == null &&
                            (x.Status == PosSerialStatus.Removed || x.Status == PosSerialStatus.Sold) &&
                            x.Note != null && x.Note.Contains(issue.IssueNo) && serials.Contains(x.SerialNumber))
                .ToListAsync();
            foreach (var r in rows)
            {
                r.Status = PosSerialStatus.InStock;
                r.SoldDate = null;
                r.Note = null;
                r.UpdatedAt = DateTime.UtcNow;
            }
        }
    }

    /// <summary>Dòng báo giá cần chọn seri khi xuất kho: hàng bắt buộc seri đã quản lý trong sổ.</summary>
    public static async Task<HashSet<Guid>> SerialProductIdsAsync(
        ZKTecoDbContext db, Guid storeId, IEnumerable<Guid> productIds)
    {
        var ids = productIds.Distinct().ToList();
        var req = await db.PosProducts.AsNoTracking()
            .Where(p => ids.Contains(p.Id) && p.StoreId == storeId && p.RequiresSerial)
            .Select(p => p.Id).ToListAsync();
        var tracked = await TrackedProductsAsync(db, storeId, req);
        return tracked;
    }

    /// <summary>Tìm máy theo seri hoặc mã thẻ RFID (không phân biệt hoa/thường).</summary>
    public static async Task<PosProductSerial?> ResolveCodeAsync(ZKTecoDbContext db, Guid storeId, string code)
    {
        var c = Normalize(code);
        if (c.Length == 0) return null;
        return await db.PosProductSerials.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && (x.SerialNumber == c || x.TagCode == c))
            .OrderBy(x => x.Status == PosSerialStatus.InStock ? 0 : x.Status == PosSerialStatus.Sold ? 1 : 2)
            .FirstOrDefaultAsync();
    }

    /// <summary>Phiếu nhập hoàn thành → ghi máy vào kho. Ném InvalidOperationException nếu thiếu / trùng seri.</summary>
    public static async Task ReceiveAsync(
        ZKTecoDbContext db, Guid storeId, PosStockReceipt receipt,
        IReadOnlyList<PosStockReceiptLine> lines, IReadOnlyDictionary<Guid, PosProduct> products, string? by)
    {
        var batch = new List<(PosStockReceiptLine Line, List<string> Serials)>();
        foreach (var line in lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p) || !p.RequiresSerial) continue;
            var units = (int)Math.Ceiling(line.Qty);
            if (line.Qty != units)
                throw new InvalidOperationException($"Số lượng phải là số nguyên: {line.ProductName}");
            var serials = Parse(line.SerialNumbersText);
            if (serials.Count != units)
                throw new InvalidOperationException(
                    $"«{line.ProductName}» cần nhập đủ {units} seri (đang có {serials.Count})");
            batch.Add((line, serials));
        }
        if (batch.Count == 0) return;

        var all = batch.SelectMany(b => b.Serials).ToList();
        if (all.Count != all.Distinct().Count())
            throw new InvalidOperationException("Seri bị trùng trong phiếu nhập");

        var existing = await db.PosProductSerials.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null &&
                        (x.Status == PosSerialStatus.InStock || x.Status == PosSerialStatus.Sold) &&
                        all.Contains(x.SerialNumber))
            .Select(x => x.SerialNumber).ToListAsync();
        if (existing.Count > 0)
            throw new InvalidOperationException($"Seri đã có trong sổ (trong kho / đã bán): {string.Join(", ", existing)}");

        var warranted = await db.PosProductWarrantyRegistrations.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.Status == PosWarrantyStatus.Active &&
                        all.Contains(r.SerialNumber.ToUpper()))
            .Select(r => r.SerialNumber).ToListAsync();
        if (warranted.Count > 0)
            throw new InvalidOperationException($"Seri đang còn bảo hành (đã bán cho khách): {string.Join(", ", warranted)}");

        var now = DateTime.UtcNow;
        foreach (var (line, serials) in batch)
        {
            foreach (var sn in serials)
            {
                db.PosProductSerials.Add(new PosProductSerial
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ProductId = line.ProductId,
                    VariantId = line.VariantId,
                    SerialNumber = sn,
                    Status = PosSerialStatus.InStock,
                    ReceiptId = receipt.Id,
                    BranchId = receipt.BranchId,
                    ReceivedDate = receipt.ImportDate ?? now,
                    CostPrice = line.CostPrice,
                    IsActive = true,
                    CreatedBy = by,
                });
            }
        }
    }

    /// <summary>
    /// Gửi phiếu chuyển kho: hàng bắt buộc seri đã quản lý trong sổ phải chọn đủ máy (không chọn → lấy theo thứ tự nhập
    /// ở kho đi); máy chuyển sang «đang trên đường» và không bán được. Trả lỗi (null nếu ổn).
    /// </summary>
    public static async Task<string?> SendTransferAsync(
        ZKTecoDbContext db, Guid storeId, PosStockTransfer t, Guid? hqBranchId)
    {
        var ids = t.Lines.Select(l => l.ProductId).Distinct().ToList();
        var req = await db.PosProducts.AsNoTracking()
            .Where(p => ids.Contains(p.Id) && p.RequiresSerial).Select(p => p.Id).ToListAsync();
        var tracked = await TrackedProductsAsync(db, storeId, req);
        foreach (var line in t.Lines.Where(l => tracked.Contains(l.ProductId)))
        {
            var units = (int)Math.Ceiling(line.Qty);
            var wanted = Parse(line.SerialNumbersText);
            List<PosProductSerial> rows;
            var q = db.PosProductSerials.AsTracking()
                .Where(x => x.StoreId == storeId && x.ProductId == line.ProductId && x.Deleted == null &&
                            x.Status == PosSerialStatus.InStock && x.TransferId == null)
                .InBranch(t.FromBranchId, hqBranchId);
            if (wanted.Count > 0)
            {
                if (wanted.Count != units)
                    return $"«{line.ProductName}» cần chọn đủ {units} seri chuyển kho (đang có {wanted.Count})";
                rows = await q.Where(x => wanted.Contains(x.SerialNumber)).ToListAsync();
                if (rows.Count != wanted.Count)
                    return $"Seri không có ở kho đi: {string.Join(", ", wanted.Except(rows.Select(r => r.SerialNumber)))}";
            }
            else
            {
                rows = await q.OrderBy(x => x.ReceivedDate).ThenBy(x => x.SerialNumber).Take(units).ToListAsync();
                if (rows.Count < units)
                    return $"«{line.ProductName}»: kho đi chỉ còn {rows.Count} seri (cần {units})";
                line.SerialNumbersText = Join(rows.Select(r => r.SerialNumber));
            }
            foreach (var r in rows) { r.TransferId = t.Id; r.UpdatedAt = DateTime.UtcNow; }
        }
        return null;
    }

    /// <summary>Nhận chuyển kho: máy nhận đủ về chi nhánh đến; máy thiếu quay về kho đi.</summary>
    public static async Task ReceiveTransferAsync(ZKTecoDbContext db, Guid storeId, PosStockTransfer t)
    {
        foreach (var line in t.Lines)
        {
            var serials = Parse(line.SerialNumbersText);
            if (serials.Count == 0) continue;
            var got = (int)Math.Clamp(Math.Floor(line.ReceivedQty ?? line.Qty), 0, serials.Count);
            var rows = await db.PosProductSerials.AsTracking()
                .Where(x => x.StoreId == storeId && x.TransferId == t.Id && x.ProductId == line.ProductId &&
                            serials.Contains(x.SerialNumber))
                .ToListAsync();
            var order = serials.Select((s, i) => (s, i)).ToDictionary(x => x.s, x => x.i);
            foreach (var r in rows.OrderBy(r => order.GetValueOrDefault(r.SerialNumber)).Select((r, i) => (r, i)))
            {
                r.r.TransferId = null;
                if (r.i < got) r.r.BranchId = t.ToBranchId;
                r.r.UpdatedAt = DateTime.UtcNow;
            }
        }
    }

    /// <summary>Hủy chuyển kho đang gửi: máy quay về kho đi (vẫn thuộc chi nhánh cũ).</summary>
    public static async Task CancelTransferAsync(ZKTecoDbContext db, Guid storeId, Guid transferId)
    {
        var rows = await db.PosProductSerials.AsTracking()
            .Where(x => x.StoreId == storeId && x.TransferId == transferId).ToListAsync();
        foreach (var r in rows) { r.TransferId = null; r.UpdatedAt = DateTime.UtcNow; }
    }

    /// <summary>Hủy phiếu nhập → gỡ máy khỏi kho. Máy đã bán thì không hủy được.</summary>
    public static async Task RemoveForReceiptAsync(ZKTecoDbContext db, Guid storeId, Guid receiptId, string? by)
    {
        var rows = await db.PosProductSerials.AsTracking()
            .Where(x => x.StoreId == storeId && x.ReceiptId == receiptId && x.Deleted == null &&
                        x.Status != PosSerialStatus.Removed)
            .ToListAsync();
        var sold = rows.Where(x => x.Status == PosSerialStatus.Sold).Select(x => x.SerialNumber).ToList();
        if (sold.Count > 0)
            throw new InvalidOperationException($"Không hủy được phiếu nhập: seri {string.Join(", ", sold)} đã bán");
        foreach (var r in rows)
        {
            r.Status = PosSerialStatus.Removed;
            r.Note = "Hủy phiếu nhập";
            r.UpdatedAt = DateTime.UtcNow;
            r.UpdatedBy = by;
        }
    }

    /// <summary>Hàng này đã được quản lý seri trong sổ chưa (có ít nhất một dòng chưa xóa)?</summary>
    private static async Task<HashSet<Guid>> TrackedProductsAsync(ZKTecoDbContext db, Guid storeId, IEnumerable<Guid> productIds)
    {
        var ids = productIds.Distinct().ToList();
        var tracked = await db.PosProductSerials.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && ids.Contains(x.ProductId))
            .Select(x => x.ProductId).Distinct().ToListAsync();
        return tracked.ToHashSet();
    }

    /// <summary>Bán: với hàng đã quản lý seri, mỗi seri phải đang «trong kho» đúng mặt hàng.</summary>
    public static async Task<string?> ValidateForSaleAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyList<(PosProduct Product, List<string> Serials)> lines,
        Guid? branchId = null, Guid? hqBranchId = null)
    {
        var candidates = lines.Where(l => l.Product.RequiresSerial).ToList();
        if (candidates.Count == 0) return null;
        var tracked = await TrackedProductsAsync(db, storeId, candidates.Select(c => c.Product.Id));
        foreach (var (product, serials) in candidates)
        {
            if (!tracked.Contains(product.Id)) continue;
            var rows = await db.PosProductSerials.AsNoTracking()
                .Where(x => x.StoreId == storeId && x.Deleted == null && serials.Contains(x.SerialNumber))
                .Select(x => new { x.SerialNumber, x.ProductId, x.Status, x.BranchId, x.TransferId })
                .ToListAsync();
            foreach (var sn in serials)
            {
                var row = rows.Where(r => r.SerialNumber == sn)
                    .OrderBy(r => r.Status == PosSerialStatus.InStock ? 0 : 1).FirstOrDefault();
                if (row == null)
                    return $"Seri {sn} chưa được nhập kho cho «{product.Name}» — nhập hàng với seri này trước khi bán";
                if (row.ProductId != product.Id)
                    return $"Seri {sn} thuộc mặt hàng khác";
                if (row.Status == PosSerialStatus.Sold)
                    return $"Seri {sn} đã bán";
                if (row.Status == PosSerialStatus.Removed)
                    return $"Seri {sn} không còn trong kho";
                if (row.TransferId != null)
                    return $"Seri {sn} đang trên đường chuyển kho";
                if (branchId != null && !(row.BranchId == branchId || (branchId == hqBranchId && row.BranchId == null)))
                    return $"Seri {sn} đang ở chi nhánh khác — chuyển kho về chi nhánh này trước khi bán";
            }
        }
        return null;
    }

    public static async Task MarkSoldAsync(
        ZKTecoDbContext db, Guid storeId, Guid saleOrderId, Guid productId,
        IEnumerable<string> serials, DateTime soldDate)
    {
        var list = serials.Select(Normalize).ToList();
        if (list.Count == 0) return;
        var rows = await db.PosProductSerials.AsTracking()
            .Where(x => x.StoreId == storeId && x.ProductId == productId && x.Deleted == null &&
                        x.Status == PosSerialStatus.InStock && list.Contains(x.SerialNumber))
            .ToListAsync();
        foreach (var r in rows)
        {
            r.Status = PosSerialStatus.Sold;
            r.SaleOrderId = saleOrderId;
            r.SoldDate = soldDate;
            r.UpdatedAt = DateTime.UtcNow;
        }
    }

    /// <summary>Máy quay lại kho (khách trả hàng / hủy đơn): chỉ các seri đang giữ bởi đơn đó.</summary>
    public static async Task RestoreAsync(
        ZKTecoDbContext db, Guid storeId, Guid saleOrderId, IEnumerable<string>? serials = null)
    {
        var list = serials?.Select(Normalize).ToList();
        var q = db.PosProductSerials.AsTracking()
            .Where(x => x.StoreId == storeId && x.SaleOrderId == saleOrderId && x.Deleted == null &&
                        x.Status == PosSerialStatus.Sold);
        if (list != null)
            q = q.Where(x => list.Contains(x.SerialNumber));
        foreach (var r in await q.ToListAsync())
        {
            r.Status = PosSerialStatus.InStock;
            r.SaleOrderId = null;
            r.SoldDate = null;
            r.UpdatedAt = DateTime.UtcNow;
        }
    }

    /// <summary>Đổi máy bảo hành: máy cũ thu hồi (ra khỏi kho bán), máy mới xuất cho khách nếu đang trong kho.</summary>
    public static async Task<string?> ReplaceAsync(
        ZKTecoDbContext db, Guid storeId, Guid saleOrderId, Guid productId,
        string oldSerial, string newSerial, string? by)
    {
        var oldSn = Normalize(oldSerial);
        var newSn = Normalize(newSerial);
        var old = await db.PosProductSerials.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null && x.SerialNumber == oldSn &&
                                      x.Status == PosSerialStatus.Sold);
        var fresh = await db.PosProductSerials.AsTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.SerialNumber == newSn &&
                        (x.Status == PosSerialStatus.InStock || x.Status == PosSerialStatus.Sold))
            .FirstOrDefaultAsync();
        if (fresh != null)
        {
            if (fresh.Status == PosSerialStatus.Sold) return $"Seri {newSn} đã bán cho khách khác";
            if (fresh.ProductId != productId) return $"Seri {newSn} thuộc mặt hàng khác";
        }
        if (old != null)
        {
            old.Status = PosSerialStatus.Removed;
            old.Note = "Thu hồi — đổi máy bảo hành";
            old.UpdatedAt = DateTime.UtcNow;
            old.UpdatedBy = by;
        }
        if (fresh != null)
        {
            fresh.Status = PosSerialStatus.Sold;
            fresh.SaleOrderId = saleOrderId;
            fresh.SoldDate = DateTime.UtcNow;
            fresh.UpdatedAt = DateTime.UtcNow;
            fresh.UpdatedBy = by;
        }
        return null;
    }

    /// <summary>Trả nhà cung cấp: các máy phải đang trong kho; bỏ khỏi kho bán. Ném InvalidOperationException nếu sai.</summary>
    public static async Task ReturnToSupplierAsync(
        ZKTecoDbContext db, Guid storeId, PosPurchaseReturn ret,
        IReadOnlyList<PosPurchaseReturnLine> lines, IReadOnlyDictionary<Guid, PosProduct> products, string? by)
    {
        var tracked = await TrackedProductsAsync(db, storeId, lines.Select(l => l.ProductId));
        foreach (var line in lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p) || !p.RequiresSerial) continue;
            var serials = Parse(line.SerialNumbersText);
            if (!tracked.Contains(p.Id) && serials.Count == 0) continue;

            var units = (int)Math.Ceiling(line.Qty);
            if (serials.Count != units)
                throw new InvalidOperationException(
                    $"Chọn đủ {units} seri máy trả nhà cung cấp cho «{line.ProductName}» (đang có {serials.Count})");
            if (serials.Count != serials.Distinct().Count())
                throw new InvalidOperationException($"Seri bị trùng: {line.ProductName}");

            var rows = await db.PosProductSerials.AsTracking()
                .Where(x => x.StoreId == storeId && x.ProductId == p.Id && x.Deleted == null &&
                            x.Status == PosSerialStatus.InStock && serials.Contains(x.SerialNumber))
                .ToListAsync();
            if (rows.Count != serials.Count)
            {
                var found = rows.Select(r => r.SerialNumber).ToHashSet();
                throw new InvalidOperationException(
                    $"Seri không còn trong kho: {string.Join(", ", serials.Where(s => !found.Contains(s)))}");
            }
            foreach (var r in rows)
            {
                r.Status = PosSerialStatus.Removed;
                r.PurchaseReturnId = ret.Id;
                r.Note = $"Trả NCC {ret.ReturnNo}";
                r.UpdatedAt = DateTime.UtcNow;
                r.UpdatedBy = by;
            }
        }
    }

    /// <summary>Hủy phiếu trả NCC → máy về lại kho.</summary>
    public static async Task RestoreFromSupplierReturnAsync(ZKTecoDbContext db, Guid storeId, Guid returnId)
    {
        var rows = await db.PosProductSerials.AsTracking()
            .Where(x => x.StoreId == storeId && x.PurchaseReturnId == returnId && x.Deleted == null &&
                        x.Status == PosSerialStatus.Removed)
            .ToListAsync();
        foreach (var r in rows)
        {
            r.Status = PosSerialStatus.InStock;
            r.PurchaseReturnId = null;
            r.Note = null;
            r.UpdatedAt = DateTime.UtcNow;
        }
    }
}
