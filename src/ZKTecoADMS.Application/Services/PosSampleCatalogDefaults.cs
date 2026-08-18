using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Services;

/// <summary>Từ điển hàng mẫu Super Admin — F&amp;B + gói theo hồ sơ ngành.</summary>
public static class PosSampleCatalogDefaults
{
    public const string PackagedCommon = "Retail,Restaurant,Hotel,RoomHourly,Gym";
    public const string FnB = nameof(PosSellProfile.Restaurant);
    public const string FnBHotel = "Restaurant,Hotel";
    public const string Retail = nameof(PosSellProfile.Retail);
    public const string Salon = nameof(PosSellProfile.Salon);
    public const string Gym = nameof(PosSellProfile.Gym);
    public const string RoomHourly = nameof(PosSellProfile.RoomHourly);
    public const string Hotel = nameof(PosSellProfile.Hotel);

    public sealed record Row(
        PosProductSampleKind Kind,
        PosProductType ProductType,
        string Name,
        string Unit,
        string Category,
        string? Barcode = null,
        decimal? Price = null,
        decimal? Cost = null,
        string? Brand = null,
        decimal Vat = 8,
        bool VatExempt = false,
        int Sort = 0,
        string? Desc = null,
        string? SellProfiles = null,
        PosServiceBillingMode Billing = PosServiceBillingMode.Flat,
        int SessionPackCount = 0,
        int SessionPackValidDays = 0);

    public static IReadOnlyList<Row> All() =>
    [
        ..FnBPackaged(),
        ..FnBFood(),
        ..FnBDrinks(),
        ..FnBExtras(),
        ..SalonPack(),
        ..GymPack(),
        ..RoomHourlyPack(),
        ..HotelPack(),
        ..RetailPack(),
    ];

    public static PosProductSampleCatalog ToEntity(Row r, string? by)
    {
        var e = new PosProductSampleCatalog
        {
            Id = Guid.NewGuid(),
            CreatedBy = by ?? "seed",
            IsActive = true,
        };
        Apply(e, r);
        return e;
    }

    public static void Apply(PosProductSampleCatalog e, Row r)
    {
        e.Kind = r.Kind;
        e.ProductType = r.ProductType;
        e.Name = r.Name;
        e.UnitName = r.Unit;
        e.CategoryName = r.Category;
        e.BrandName = r.Brand;
        e.Barcode = r.Barcode;
        e.DefaultPrice = r.Price;
        e.DefaultCostPrice = r.Cost;
        e.VatRate = r.VatExempt ? 0 : r.Vat;
        e.VatExempt = r.VatExempt;
        e.Description = r.Desc;
        e.SortOrder = r.Sort;
        e.SellProfiles = PosSampleSellProfileHelper.Normalize(r.SellProfiles);
        e.ServiceBillingMode = r.Billing;
        e.SessionPackCount = r.SessionPackCount;
        e.SessionPackValidDays = r.SessionPackValidDays;
    }

    public static IEnumerable<Row> FnBPackaged() =>
    [
        new(PosProductSampleKind.Packaged, PosProductType.Goods, "Coca Cola 330ml", "Lon", "Nước giải khát",
            "8934588012013", 10000, 7000, "Coca-Cola", Sort: 1, SellProfiles: PackagedCommon),
        new(PosProductSampleKind.Packaged, PosProductType.Goods, "Pepsi 330ml", "Lon", "Nước giải khát",
            "8934588012020", 10000, 7000, "Pepsi", Sort: 2, SellProfiles: PackagedCommon),
        new(PosProductSampleKind.Packaged, PosProductType.Goods, "Sting dâu 330ml", "Lon", "Nước giải khát",
            "8934588012037", 11000, 7500, "Sting", Sort: 3, SellProfiles: PackagedCommon),
        new(PosProductSampleKind.Packaged, PosProductType.Goods, "Aquafina 500ml", "Chai", "Nước suối",
            "8934588060014", 7000, 4000, "Aquafina", Sort: 4, SellProfiles: PackagedCommon),
    ];

    public static IEnumerable<Row> FnBFood() =>
    [
        new(PosProductSampleKind.Food, PosProductType.Goods, "Cơm tấm sườn", "Phần", "Món chính",
            Price: 45000, Cost: 25000, Sort: 1, SellProfiles: FnB),
        new(PosProductSampleKind.Food, PosProductType.Goods, "Phở bò", "Tô", "Món chính",
            Price: 55000, Cost: 30000, Sort: 2, SellProfiles: FnB),
        new(PosProductSampleKind.Food, PosProductType.Goods, "Bún chả", "Suất", "Món chính",
            Price: 50000, Cost: 28000, Sort: 3, SellProfiles: FnB),
        new(PosProductSampleKind.Food, PosProductType.Goods, "Bánh mì thịt", "Cái", "Ăn nhanh",
            Price: 25000, Cost: 12000, Sort: 4, SellProfiles: FnB),
        new(PosProductSampleKind.Food, PosProductType.Goods, "Gỏi cuốn", "Phần", "Khai vị",
            Price: 35000, Cost: 18000, Sort: 5, SellProfiles: FnB),
        new(PosProductSampleKind.Food, PosProductType.Goods, "Nem rán", "Phần", "Khai vị",
            Price: 30000, Cost: 15000, Sort: 6, SellProfiles: FnB),
    ];

    public static IEnumerable<Row> FnBDrinks() =>
    [
        new(PosProductSampleKind.Drink, PosProductType.Goods, "Trà sữa truyền thống", "Ly", "Trà sữa",
            Price: 30000, Cost: 12000, Sort: 1, SellProfiles: FnBHotel),
        new(PosProductSampleKind.Drink, PosProductType.Goods, "Trà đào cam sả", "Ly", "Trà trái cây",
            Price: 35000, Cost: 14000, Sort: 2, SellProfiles: FnBHotel),
        new(PosProductSampleKind.Drink, PosProductType.Goods, "Cà phê sữa đá", "Ly", "Cà phê",
            Price: 25000, Cost: 8000, Sort: 3, SellProfiles: FnBHotel),
        new(PosProductSampleKind.Drink, PosProductType.Goods, "Cà phê đen", "Ly", "Cà phê",
            Price: 20000, Cost: 6000, Sort: 4, SellProfiles: FnBHotel),
        new(PosProductSampleKind.Drink, PosProductType.Goods, "Nước cam ép", "Ly", "Nước ép",
            Price: 35000, Cost: 15000, Sort: 5, SellProfiles: FnBHotel),
        new(PosProductSampleKind.Drink, PosProductType.Goods, "Sinh tố bơ", "Ly", "Sinh tố",
            Price: 40000, Cost: 18000, Sort: 6, SellProfiles: FnBHotel),
    ];

    public static IEnumerable<Row> FnBExtras() =>
    [
        new(PosProductSampleKind.Food, PosProductType.Service, "Phí giao hàng", "Lần", "Dịch vụ",
            Price: 15000, Cost: 0, Sort: 10, Desc: "Phí ship nội thành", SellProfiles: "Restaurant,Retail"),
        new(PosProductSampleKind.Drink, PosProductType.Topping, "Trân châu đen", "Phần", "Topping",
            Price: 5000, Cost: 2000, Sort: 11, SellProfiles: FnB),
        new(PosProductSampleKind.Drink, PosProductType.Topping, "Thạch rau câu", "Phần", "Topping",
            Price: 5000, Cost: 1500, Sort: 12, SellProfiles: FnB),
        new(PosProductSampleKind.Food, PosProductType.Material, "Gạo tấm", "Kg", "Nguyên liệu",
            Price: 0, Cost: 18000, VatExempt: true, Sort: 13, Desc: "NVL — không bán trực tiếp", SellProfiles: FnB),
        new(PosProductSampleKind.Food, PosProductType.Combo, "Combo cơm + nước", "Suất", "Combo",
            Price: 59000, Cost: 32000, Sort: 14, Desc: "Combo mẫu", SellProfiles: FnB),
    ];

    public static IEnumerable<Row> SalonPack() =>
    [
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Cắt tóc nam", "Lần", "Tóc",
            Price: 80000, Cost: 0, Sort: 20, SellProfiles: Salon),
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Cắt tóc nữ", "Lần", "Tóc",
            Price: 120000, Cost: 0, Sort: 21, SellProfiles: Salon),
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Gội dưỡng", "Lần", "Tóc",
            Price: 50000, Cost: 0, Sort: 22, SellProfiles: Salon),
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Nhuộm tóc", "Lần", "Tóc",
            Price: 250000, Cost: 0, Sort: 23, SellProfiles: Salon),
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Nail gel", "Lần", "Nail",
            Price: 150000, Cost: 0, Sort: 24, SellProfiles: Salon),
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Massage vai cổ", "Lần", "Spa",
            Price: 80000, Cost: 0, Sort: 25, Desc: "15–20 phút", SellProfiles: Salon),
    ];

    public static IEnumerable<Row> GymPack() =>
    [
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Gói 1 buổi PT", "Gói", "Gói tập",
            Price: 200000, Cost: 0, Sort: 30, SellProfiles: Gym,
            Billing: PosServiceBillingMode.PerSession, SessionPackCount: 1, SessionPackValidDays: 30),
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Gói 10 buổi PT", "Gói", "Gói tập",
            Price: 1800000, Cost: 0, Sort: 31, SellProfiles: Gym,
            Billing: PosServiceBillingMode.PerSession, SessionPackCount: 10, SessionPackValidDays: 90),
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Gói tháng gym", "Tháng", "Membership",
            Price: 800000, Cost: 0, Sort: 32, SellProfiles: Gym,
            Billing: PosServiceBillingMode.PerSession, SessionPackCount: 12, SessionPackValidDays: 35),
        new(PosProductSampleKind.Packaged, PosProductType.Goods, "Whey protein gói", "Gói", "Thực phẩm",
            Price: 45000, Cost: 25000, Brand: "Generic", Sort: 33, SellProfiles: Gym),
    ];

    public static IEnumerable<Row> RoomHourlyPack() =>
    [
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Giờ phòng karaoke", "Giờ", "Phòng",
            Price: 150000, Cost: 0, Sort: 40, Desc: "Tính giờ phòng thường",
            SellProfiles: RoomHourly, Billing: PosServiceBillingMode.PerHour),
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Giờ phòng VIP", "Giờ", "Phòng",
            Price: 250000, Cost: 0, Sort: 41, SellProfiles: RoomHourly, Billing: PosServiceBillingMode.PerHour),
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Giờ bàn bi-a", "Giờ", "Bi-a",
            Price: 80000, Cost: 0, Sort: 42, SellProfiles: RoomHourly, Billing: PosServiceBillingMode.PerHour),
        new(PosProductSampleKind.Packaged, PosProductType.Goods, "Snack khoai tây", "Gói", "Đồ ăn vặt",
            Price: 15000, Cost: 8000, Sort: 43, SellProfiles: "RoomHourly,Hotel,Retail"),
    ];

    public static IEnumerable<Row> HotelPack() =>
    [
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Phòng Standard / đêm", "Đêm", "Lưu trú",
            Price: 500000, Cost: 0, Sort: 50, SellProfiles: Hotel, Billing: PosServiceBillingMode.PerDay),
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Phòng Deluxe / đêm", "Đêm", "Lưu trú",
            Price: 800000, Cost: 0, Sort: 51, SellProfiles: Hotel, Billing: PosServiceBillingMode.PerDay),
        new(PosProductSampleKind.Packaged, PosProductType.Service, "Giặt ủi", "Lần", "Dịch vụ phòng",
            Price: 50000, Cost: 0, Sort: 52, SellProfiles: Hotel),
        new(PosProductSampleKind.Packaged, PosProductType.Goods, "Minibar snack", "Gói", "Minibar",
            Price: 25000, Cost: 12000, Sort: 53, SellProfiles: Hotel),
    ];

    public static IEnumerable<Row> RetailPack() =>
    [
        new(PosProductSampleKind.Packaged, PosProductType.Goods, "Mì Hảo Hảo tôm chua cay", "Gói", "Mì ăn liền",
            "8934563138165", 4500, 2800, "Acecook", Sort: 60, SellProfiles: Retail),
        new(PosProductSampleKind.Packaged, PosProductType.Goods, "Dầu gội Clear 170g", "Chai", "Chăm sóc tóc",
            "8934868130015", 55000, 38000, "Clear", Sort: 61, SellProfiles: Retail),
        new(PosProductSampleKind.Packaged, PosProductType.Goods, "Khăn giấy Bless You", "Bịch", "Gia dụng",
            Price: 12000, Cost: 7000, Brand: "Bless You", Sort: 62, SellProfiles: Retail),
        new(PosProductSampleKind.Packaged, PosProductType.Goods, "Pin AA Maxell", "Vỉ", "Điện tử",
            Price: 15000, Cost: 9000, Brand: "Maxell", Sort: 63, SellProfiles: Retail),
    ];
}
