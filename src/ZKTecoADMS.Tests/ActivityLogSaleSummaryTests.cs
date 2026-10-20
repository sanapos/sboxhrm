using System.Text.Json;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>Bán 1 đơn (dữ liệu thật: coca cola 15k) phải đọc thành 1 dòng gọn, chi tiết không «một tràn».</summary>
public class ActivityLogSaleSummaryTests
{
    // Rút gọn từ nhật ký thật khi thanh toán HD201020260003 (PUT /api/pos/sales/{id}).
    const string CheckoutDetails = """
    {"source":"StoreActivity","endpoint":"PUT /api/pos/sales/{id:guid}","changes":[
     {"type":"PosStockTransaction","id":"89aef056","op":"Create","label":null,"fields":[
       {"field":"ProductId","old":null,"new":"e79875b9-c150-42be-aef7-8d03c1c1d94b"},
       {"field":"QtyChange","old":null,"new":"-1"},{"field":"ReferenceNo","old":null,"new":"HD201020260003"}]},
     {"type":"CashTransaction","id":"9d15cb4b","op":"Create","label":null,"fields":[
       {"field":"Amount","old":null,"new":"15000"},
       {"field":"InternalNote","old":null,"new":"pos bán hàng #9c17c03a-aebd-47f4-9eb4-07b363c3e854|0"}]},
     {"type":"PosSaleOrderLine","id":"ecbe53d1","op":"Create","label":"coca cola","fields":[
       {"field":"KitchenSentQty","old":null,"new":"0"},{"field":"LineTotal","old":null,"new":"15000"},
       {"field":"ProductName","old":null,"new":"coca cola"},{"field":"Qty","old":null,"new":"1"},
       {"field":"DiscountAmount","old":null,"new":"0"}]},
     {"type":"PosSaleOrder","id":"9c17c03a","op":"Update","label":"HD201020260003","fields":[
       {"field":"PaidAmount","old":"0","new":"15000"},
       {"field":"SaleDate","old":"2026-10-20 11:39","new":"2026-10-20 11:39"},
       {"field":"Status","old":"Draft","new":"Completed"}]},
     {"type":"PosProduct","id":"e79875b9-c150-42be-aef7-8d03c1c1d94b","op":"Update","label":"coca cola","fields":[
       {"field":"OnHandQty","old":"49","new":"48"},{"field":"ReservedQty","old":"1","new":"0"}]},
     {"type":"PosSaleOrderLine","id":"da450c71","op":"Delete","label":"coca cola","fields":[]},
     {"type":"PosSaleOrder","id":"9c17c03a","op":"Update","label":"HD201020260003","fields":[
       {"field":"ResourceSessionId","old":"0040934b-4b9f-4547-aa8b-c2e33b76f32c","new":null}]}]}
    """;

    static AuditLog Log(string action) => new()
    {
        Id = Guid.NewGuid(), Action = action, EntityType = "PosSell", Details = CheckoutDetails,
        Timestamp = new DateTime(2026, 10, 20, 11, 39, 0),
    };

    [Theory]
    [InlineData("Update")] // nhật ký cũ (trước khi ghi thanh toán thành «Thêm»)
    [InlineData("Create")]
    public void Checkout_reads_as_one_compact_line(string action)
    {
        var row = ActivityLogsController.ToRow(Log(action));
        Assert.Equal("Hóa đơn / đơn hàng «HD201020260003» · 15.000đ · coca cola ×1", row.EntityName);
        Assert.Equal(0, row.FieldCount);
    }

    [Fact]
    public void Checkout_detail_keeps_only_invoice_and_items()
    {
        var json = JsonSerializer.Serialize(ActivityLogsController.LocalizedDetails(CheckoutDetails),
            new JsonSerializerOptions(JsonSerializerDefaults.Web));
        using var doc = JsonDocument.Parse(json);
        var changes = doc.RootElement.GetProperty("changes").EnumerateArray().ToList();

        // Hóa đơn lên đầu, chỉ còn Đã trả + Trạng thái (giờ bán không đổi đã bỏ); bản hóa đơn phụ bị bỏ.
        Assert.Equal("PosSaleOrder", changes[0].GetProperty("type").GetString());
        var orderFields = changes[0].GetProperty("fields").EnumerateArray().Select(f => f.GetProperty("field").GetString()).ToList();
        Assert.Equal(["PaidAmount", "Status"], orderFields);
        Assert.Equal("15.000", changes[0].GetProperty("fields")[0].GetProperty("new").GetString());
        Assert.Single(changes, c => c.GetProperty("type").GetString() == "PosSaleOrder");

        // Dòng hàng: một dòng (bỏ bản xóa), chỉ trường chính, giảm giá 0 và Kitchen* đã bỏ.
        var line = Assert.Single(changes, c => c.GetProperty("type").GetString() == "PosSaleOrderLine");
        var lineFields = line.GetProperty("fields").EnumerateArray().Select(f => f.GetProperty("field").GetString()).ToList();
        Assert.Equal(["LineTotal", "ProductName", "Qty"], lineFields);

        // Kho, phiếu thu, tồn hàng hóa: chỉ tiêu đề.
        foreach (var t in new[] { "PosStockTransaction", "CashTransaction", "PosProduct" })
            Assert.Empty(changes.Single(c => c.GetProperty("type").GetString() == t).GetProperty("fields").EnumerateArray());
    }
}
