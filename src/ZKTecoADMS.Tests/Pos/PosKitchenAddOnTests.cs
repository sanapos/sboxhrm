using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Đổi topping / ghi chú của món đã báo bếp là phần bổ sung, không phải món mới.</summary>
public class PosKitchenAddOnTests
{
    const string Tc = """{"id":"A1","name":"Trân châu","price":5000.0,"qty":1}""";
    const string Thach = """{"id":"b2","name":"Thạch","price":3000.0,"qty":1}""";
    static readonly Guid Tea = Guid.NewGuid();

    static string Arr(params string[] items) => $"[{string.Join(",", items)}]";

    [Fact]
    public void Them_topping_van_cung_khoa_ghep_voi_dong_da_bao()
    {
        var sent = PosKitchenContent.Serialize(null, null);
        Assert.Equal(
            PosKitchenContent.CarryKey(Tea, null, null, null, null),
            PosKitchenContent.CarryKey(Tea, null, Arr(Tc), null, sent));
    }

    [Fact]
    public void Khoa_ghep_khong_phu_thuoc_thu_tu_va_dinh_dang_json()
    {
        Assert.Equal(
            PosKitchenContent.CarryKey(Tea, null, Arr(Tc, Thach), "ít đá", null),
            PosKitchenContent.CarryKey(Tea, null, Arr(Thach.Replace("3000.0", "3000"), Tc.Replace("A1", "a1")), " ít đá ", null));
    }

    [Fact]
    public void Topping_khac_khi_chua_co_moc_la_dong_khac()
    {
        Assert.NotEqual(
            PosKitchenContent.CarryKey(Tea, null, null, null, null),
            PosKitchenContent.CarryKey(Tea, null, Arr(Tc), null, null));
    }

    [Fact]
    public void Phieu_bo_sung_chi_ghi_phan_chenh_lech()
    {
        var sent = PosKitchenContent.Serialize(Arr(Tc), "ít đá");
        Assert.Equal("+ Thạch", PosKitchenContent.ChangeNote(sent, Arr(Tc, Thach), "ít đá"));
        Assert.Equal("- Bỏ Trân châu", PosKitchenContent.ChangeNote(sent, null, "ít đá"));
        Assert.Equal("không đá", PosKitchenContent.ChangeNote(sent, Arr(Tc), "không đá"));
        Assert.Equal("Bỏ ghi chú: ít đá", PosKitchenContent.ChangeNote(sent, Arr(Tc), null));
        Assert.Equal("+ Trân châu x2",
            PosKitchenContent.ChangeNote(sent, Arr(Tc.Replace("\"qty\":1", "\"qty\":3")), "ít đá"));
    }

    [Fact]
    public void Doi_roi_doi_lai_khong_con_gi_de_bao()
    {
        var sent = PosKitchenContent.Serialize(Arr(Tc, Thach), "ít đá");
        Assert.Null(PosKitchenContent.ChangeNote(sent, Arr(Thach, Tc), "ít đá"));
        Assert.False(PosKitchenContent.Changed(sent, Arr(Thach, Tc), "ít đá"));
    }

    [Fact]
    public void Chua_co_moc_khong_coi_la_doi()
    {
        Assert.Null(PosKitchenContent.ChangeNote(null, Arr(Tc), null));
        Assert.False(PosKitchenContent.Changed(null, Arr(Tc), null));
        Assert.False(PosKitchenContent.Changed("không phải json", Arr(Tc), null));
    }

    [Fact]
    public void Settle_danh_dau_cho_bao_va_xoa_moc_khi_chua_bao()
    {
        var line = new PosSaleOrderLine
        {
            KitchenSentQty = 1,
            ToppingsJson = Arr(Tc),
            KitchenSentContent = PosKitchenContent.Serialize(null, null),
        };
        PosKitchenContent.Settle(line);
        Assert.True(line.KitchenContentPending);

        var legacy = new PosSaleOrderLine { KitchenSentQty = 1, ToppingsJson = Arr(Tc) };
        PosKitchenContent.Settle(legacy);
        Assert.False(legacy.KitchenContentPending);
        Assert.NotNull(legacy.KitchenSentContent);

        var unsent = new PosSaleOrderLine
        {
            KitchenSentQty = 0,
            KitchenSentContent = "x",
            KitchenContentPending = true,
            KitchenAddOnNote = "+ Thạch",
        };
        PosKitchenContent.Settle(unsent);
        Assert.Null(unsent.KitchenSentContent);
        Assert.False(unsent.KitchenContentPending);
        Assert.Null(unsent.KitchenAddOnNote);
    }

    [Fact]
    public void Kds_hien_phan_bo_sung_len_dau()
    {
        Assert.Equal("Bổ sung:\n+ Thạch\n---\n+ Trân châu\n+ Thạch",
            PosKitchenContent.KdsNote("+ Thạch", "+ Trân châu\n+ Thạch"));
        Assert.Equal("Bổ sung:\n+ Thạch", PosKitchenContent.KdsNote("+ Thạch", null));
        Assert.Equal("ít đá", PosKitchenContent.KdsNote(null, "ít đá"));
    }
}
