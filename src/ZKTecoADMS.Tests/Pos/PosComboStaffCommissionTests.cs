using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Combo dịch vụ nhiều bước (cắt – gội…) gán mỗi bước một NV: lưu đơn tạm / thanh toán ghi hoa hồng từng bước.</summary>
[Collection("pos-pg")]
public class PosComboStaffCommissionTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Fact]
    public async Task Combo_gan_NV_tung_buoc_luu_don_tam_roi_thanh_toan()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var cut = await Fx.AddProductAsync(store, "Cắt tóc", PosProductType.Service, 0, 0, 80_000);
        var wash = await Fx.AddProductAsync(store, "Gội đầu", PosProductType.Service, 0, 0, 60_000);
        var combo = await Fx.AddProductAsync(store, "Combo tóc", PosProductType.Combo, 0, 0, 120_000);
        await AddComboLineAsync(store, combo.Id, cut.Id, 1);
        await AddComboLineAsync(store, combo.Id, wash.Id, 1);

        Guid an, binh;
        await using (var db = Fx.NewDb())
        {
            var manager = await db.Users.Where(u => u.StoreId == store).Select(u => u.Id).FirstAsync();
            Employee E(string name) => new()
            {
                Id = Guid.NewGuid(), StoreId = store, ManagerId = manager, EmployeeCode = name,
                CompanyEmail = name + "@t.vn", FirstName = name, LastName = "NV",
            };
            var e1 = E("An");
            var e2 = E("Binh");
            db.Employees.AddRange(e1, e2);
            await db.SaveChangesAsync();
            an = e1.Id;
            binh = e2.Id;
        }

        List<PosSalesController.SaleLineDto> Lines() =>
        [
            new(combo.Id, 1, null, 120_000, null,
                AssignedEmployeeId: an,
                StaffAssignments:
                [
                    new(cut.Id, an, "An NV"),
                    new(wash.Id, binh, "Binh NV"),
                ]),
        ];

        // Đơn tạm (như màn bán tự lưu khi gán NV).
        PosSalesController.SaleOrderDto draft;
        await using (var db = Fx.NewDb())
        {
            draft = Data(await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
                Lines(), 0, 0, "Tiền mặt", null, null, null, Complete: false)));
        }

        // Lưu lại đơn tạm lần 2 (dòng bị thay mới) — trước đây lỗi FK hoa hồng → 500.
        await using (var db = Fx.NewDb())
        {
            var r = await Sales(db, store).UpdateSale(draft.Id, new PosSalesController.UpdateSaleDto(
                Lines(), 0, 0, "Tiền mặt", null, null, null, Complete: false));
            Assert.Null(Error(r));
        }

        // Thanh toán.
        await using (var db = Fx.NewDb())
        {
            var r = await Sales(db, store).UpdateSale(draft.Id, new PosSalesController.UpdateSaleDto(
                Lines(), 0, 120_000, "Tiền mặt", null, null, null, Complete: true));
            Assert.Null(Error(r));
        }

        await using (var db = Fx.NewDb())
        {
            var rows = await db.PosSaleCommissionLines
                .Where(c => c.SaleOrderId == draft.Id && c.Deleted == null)
                .ToListAsync();
            Assert.Equal(2, rows.Count);
            Assert.Equal(an, rows.Single(r => r.ProductId == cut.Id).EmployeeId);
            Assert.Equal(binh, rows.Single(r => r.ProductId == wash.Id).EmployeeId);
            Assert.Equal(120_000m, rows.Sum(r => r.RevenueAmount));
        }
    }
}
