using System.Globalization;
using System.Text;
using System.Text.Json;

namespace ZKTecoADMS.Api.Seo;

/// <summary>
/// Trang dịch vụ theo tỉnh/thành (sboxhrm.com): /lap-dat-may-cham-cong và /lap-dat-may-cham-cong/{tinh}.
/// 34 tỉnh/thành sau sắp xếp đơn vị hành chính 2025, mỗi trang nêu tên tỉnh cũ người dùng vẫn hay tìm,
/// địa bàn, đặc điểm doanh nghiệp và gợi ý cấu hình máy riêng — không phải trang chỉ thay tên tỉnh.
/// Chính sách (chủ cửa hàng xác nhận 10/2026): bán + lắp máy ZKTeco (không phải đại lý chính thức của hãng),
/// lắp tận nơi toàn quốc, mua máy được miễn phí lắp đặt + tặng phần mềm chấm công.
/// </summary>
public static partial class SeoPages
{
    /// <summary>Tags: kcn (khu công nghiệp), dulich, nongnghiep, thuysan, thuongmai, cuakhau, vungcao.</summary>
    public record Province(string Slug, string Name, string Region, string[] Old, string[] Places, string[] Tags, string Profile);

    public static readonly IReadOnlyList<Province> Provinces =
    [
        // ── Miền Bắc ──
        new("ha-noi", "Hà Nội", "Miền Bắc", [], ["Hoàn Kiếm", "Cầu Giấy", "Hà Đông", "Long Biên", "Đông Anh", "Sóc Sơn", "Sơn Tây"], ["thuongmai", "kcn"],
            "Thủ đô tập trung dày đặc văn phòng, chuỗi bán lẻ, nhà hàng và các khu công nghiệp vùng ven như Thăng Long, Quang Minh, Phú Nghĩa. Doanh nghiệp thường có nhiều chi nhánh trong nội thành và cần xem công tập trung."),
        new("hai-phong", "Hải Phòng", "Miền Bắc", ["Hải Dương"], ["Hồng Bàng", "Lê Chân", "Hải An", "Thủy Nguyên", "Hải Dương", "Chí Linh", "Kinh Môn"], ["kcn", "thuongmai"],
            "Thành phố cảng với các khu công nghiệp lớn như Đình Vũ, VSIP Hải Phòng, Tràng Duệ và vùng sản xuất của Hải Dương cũ (Đại An, Nam Sách). Nhà máy nhiều công nhân, làm ca kíp và tăng ca thường xuyên."),
        new("quang-ninh", "Quảng Ninh", "Miền Bắc", [], ["Hạ Long", "Cẩm Phả", "Uông Bí", "Móng Cái", "Quảng Yên", "Vân Đồn"], ["dulich", "kcn", "cuakhau"],
            "Kết hợp du lịch Hạ Long – Vân Đồn, khai thác than và các khu công nghiệp Đông Mai, Sông Khoai cùng kinh tế cửa khẩu Móng Cái. Khách sạn, nhà hàng làm nhiều ca; doanh nghiệp sản xuất cần chấm công theo kíp."),
        new("bac-ninh", "Bắc Ninh", "Miền Bắc", ["Bắc Giang"], ["Bắc Ninh", "Từ Sơn", "Yên Phong", "Quế Võ", "Bắc Giang", "Việt Yên", "Lục Nam"], ["kcn"],
            "Trung tâm công nghiệp điện tử với Yên Phong, Quế Võ, VSIP Bắc Ninh và các khu công nghiệp Quang Châu, Vân Trung, Đình Trám của Bắc Giang cũ. Nhà máy và nhà thầu phụ cần chấm công nhanh cho hàng nghìn công nhân mỗi ca."),
        new("hung-yen", "Hưng Yên", "Miền Bắc", ["Thái Bình"], ["Hưng Yên", "Mỹ Hào", "Văn Lâm", "Văn Giang", "Thái Bình", "Tiền Hải"], ["kcn", "nongnghiep"],
            "Các khu công nghiệp Phố Nối, Thăng Long II, Minh Đức cùng vùng công nghiệp mới của Thái Bình cũ (Liên Hà Thái, Tiền Hải). Doanh nghiệp vừa sản xuất vừa có xưởng vệ tinh, cần gom công nhiều điểm."),
        new("ninh-binh", "Ninh Bình", "Miền Bắc", ["Hà Nam", "Nam Định"], ["Hoa Lư", "Tam Điệp", "Phủ Lý", "Duy Tiên", "Nam Định", "Hải Hậu"], ["kcn", "dulich"],
            "Gộp ba tỉnh với du lịch Tràng An – Tam Cốc, dệt may Nam Định và các khu công nghiệp Đồng Văn, Hòa Mạc của Hà Nam cũ. Có cả nhà máy đông công nhân lẫn khu du lịch, nhà hàng làm việc theo ca."),
        new("phu-tho", "Phú Thọ", "Miền Bắc", ["Vĩnh Phúc", "Hòa Bình"], ["Việt Trì", "Phú Thọ", "Vĩnh Yên", "Phúc Yên", "Hòa Bình", "Lương Sơn"], ["kcn", "dulich"],
            "Vùng công nghiệp ô tô, xe máy, linh kiện của Vĩnh Phúc cũ (Bá Thiện, Bình Xuyên, Khai Quang), các khu công nghiệp Thụy Vân, Phú Hà và khu nghỉ dưỡng Hòa Bình. Nhà máy cần nhiều máy chấm công tại các cổng."),
        new("thai-nguyen", "Thái Nguyên", "Miền Bắc", ["Bắc Kạn"], ["Thái Nguyên", "Phổ Yên", "Sông Công", "Đại Từ", "Bắc Kạn", "Ba Bể"], ["kcn", "vungcao"],
            "Khu công nghiệp Yên Bình, Điềm Thụy với các nhà máy điện tử lớn, cùng vùng trà và du lịch Ba Bể của Bắc Kạn cũ. Công nhân đông, nhiều ca, cần máy khuôn mặt chấm nhanh."),
        new("tuyen-quang", "Tuyên Quang", "Miền Bắc", ["Hà Giang"], ["Tuyên Quang", "Sơn Dương", "Hà Giang", "Đồng Văn", "Mèo Vạc"], ["vungcao", "dulich"],
            "Địa bàn rộng, nhiều huyện vùng cao của Hà Giang cũ với du lịch cao nguyên đá và các cơ sở chế biến, sản xuất của Tuyên Quang. Nhân viên làm việc phân tán, khoảng cách xa nên chấm công điện thoại theo vị trí rất hữu ích."),
        new("lao-cai", "Lào Cai", "Miền Bắc", ["Yên Bái"], ["Lào Cai", "Sa Pa", "Bát Xát", "Yên Bái", "Nghĩa Lộ", "Mù Cang Chải"], ["dulich", "cuakhau", "vungcao"],
            "Du lịch Sa Pa, kinh tế cửa khẩu Lào Cai, khai khoáng và vùng sản xuất của Yên Bái cũ. Khách sạn, homestay, nhà hàng dùng nhiều lao động thời vụ theo mùa du lịch."),
        new("lang-son", "Lạng Sơn", "Miền Bắc", [], ["Lạng Sơn", "Đồng Đăng", "Hữu Lũng", "Cao Lộc"], ["cuakhau", "thuongmai"],
            "Kinh tế cửa khẩu Hữu Nghị, Tân Thanh với nhiều doanh nghiệp logistics, kho bãi, xuất nhập khẩu. Kho vận hoạt động cả ngày lẫn đêm, cần chấm công theo ca và theo từng điểm kho."),
        new("cao-bang", "Cao Bằng", "Miền Bắc", [], ["Cao Bằng", "Trùng Khánh", "Trà Lĩnh", "Hòa An"], ["vungcao", "dulich", "cuakhau"],
            "Du lịch thác Bản Giốc, cửa khẩu Trà Lĩnh và các đơn vị sản xuất, dịch vụ quy mô vừa. Địa hình đồi núi, các điểm làm việc cách xa nhau."),
        new("dien-bien", "Điện Biên", "Miền Bắc", [], ["Điện Biên Phủ", "Mường Lay", "Tuần Giáo"], ["vungcao", "dulich"],
            "Doanh nghiệp dịch vụ, du lịch lịch sử và cơ sở sản xuất nông sản. Nhiều đơn vị có nhân viên làm việc tại hiện trường, xa trụ sở."),
        new("lai-chau", "Lai Châu", "Miền Bắc", [], ["Lai Châu", "Tam Đường", "Than Uyên", "Sìn Hồ"], ["vungcao", "nongnghiep"],
            "Thủy điện, trồng chè và các công trình hạ tầng với lực lượng lao động làm việc tại công trường, nương chè phân tán."),
        new("son-la", "Sơn La", "Miền Bắc", [], ["Sơn La", "Mộc Châu", "Mai Sơn", "Yên Châu"], ["nongnghiep", "dulich"],
            "Vùng cây ăn quả, bò sữa, chè Mộc Châu và du lịch cao nguyên. Doanh nghiệp chế biến nông sản tuyển nhiều lao động thời vụ theo mùa thu hoạch."),

        // ── Miền Trung ──
        new("thanh-hoa", "Thanh Hóa", "Miền Trung", [], ["Thanh Hóa", "Sầm Sơn", "Bỉm Sơn", "Nghi Sơn", "Thọ Xuân"], ["kcn", "dulich"],
            "Khu kinh tế Nghi Sơn với lọc hóa dầu, xi măng, cùng du lịch biển Sầm Sơn và nhiều nhà máy da giày, may mặc. Số lượng công nhân lớn, nhiều xưởng vệ tinh ở các huyện."),
        new("nghe-an", "Nghệ An", "Miền Trung", [], ["Vinh", "Cửa Lò", "Hoàng Mai", "Nghi Lộc", "Diễn Châu"], ["kcn", "thuongmai"],
            "Các khu công nghiệp VSIP Nghệ An, WHA, Nam Cấm thu hút nhà máy điện tử, cùng trung tâm thương mại – dịch vụ Vinh. Doanh nghiệp mới mở rộng nhanh, cần hệ thống chấm công dễ nhân bản."),
        new("ha-tinh", "Hà Tĩnh", "Miền Trung", [], ["Hà Tĩnh", "Kỳ Anh", "Hồng Lĩnh", "Vũng Áng"], ["kcn"],
            "Khu kinh tế Vũng Áng với thép, nhiệt điện và nhiều nhà thầu, nhà cung cấp dịch vụ đi kèm. Lao động làm việc tại công trường và nhà máy theo ca."),
        new("quang-tri", "Quảng Trị", "Miền Trung", ["Quảng Bình"], ["Đông Hà", "Lao Bảo", "Đồng Hới", "Phong Nha", "Ba Đồn"], ["dulich", "cuakhau"],
            "Du lịch hang động Phong Nha – Kẻ Bàng của Quảng Bình cũ, biển Nhật Lệ, cửa khẩu Lao Bảo và các khu công nghiệp Nam Đông Hà, Hòn La. Dịch vụ du lịch làm việc theo mùa và theo ca."),
        new("hue", "Huế", "Miền Trung", [], ["Phú Xuân", "Thuận Hóa", "Hương Thủy", "Hương Trà", "Phong Điền", "Chân Mây"], ["dulich", "thuongmai"],
            "Du lịch di sản, khách sạn, nhà hàng và các khu công nghiệp Phú Bài, Phong Điền, Chân Mây – Lăng Cô. Ngành lưu trú, ăn uống cần chấm công ca xoay, ca gãy."),
        new("da-nang", "Đà Nẵng", "Miền Trung", ["Quảng Nam"], ["Hải Châu", "Thanh Khê", "Sơn Trà", "Ngũ Hành Sơn", "Cẩm Lệ", "Liên Chiểu", "Hòa Khánh", "Hòa Vang", "Hội An", "Tam Kỳ", "Điện Bàn", "Núi Thành", "Chu Lai"], ["dulich", "kcn", "thuongmai"],
            "Nơi đặt văn phòng của SBOX. Đà Nẵng mới kết hợp du lịch Đà Nẵng – Hội An, các khu công nghiệp Hòa Khánh, Liên Chiểu, Điện Nam – Điện Ngọc và khu kinh tế Chu Lai của Quảng Nam cũ. Khách sạn, resort, nhà máy và chuỗi cửa hàng đều có nhu cầu chấm công nhiều điểm."),
        new("quang-ngai", "Quảng Ngãi", "Miền Trung", ["Kon Tum"], ["Quảng Ngãi", "Dung Quất", "Đức Phổ", "Kon Tum", "Ngọc Hồi"], ["kcn", "vungcao"],
            "Khu kinh tế Dung Quất với lọc dầu, thép và cơ khí, cùng vùng Kon Tum cũ với nông lâm nghiệp và cửa khẩu Bờ Y. Lao động phân bố từ nhà máy ven biển đến vùng cao."),
        new("gia-lai", "Gia Lai", "Miền Trung", ["Bình Định"], ["Pleiku", "An Khê", "Quy Nhơn", "An Nhơn", "Hoài Nhơn", "Phù Cát"], ["nongnghiep", "dulich", "kcn"],
            "Trải dài từ cao nguyên Pleiku với cà phê, cao su, hồ tiêu đến Quy Nhơn với du lịch biển, cảng và khu công nghiệp Phú Tài, Nhơn Hội của Bình Định cũ. Doanh nghiệp có nhiều điểm làm việc cách xa nhau."),
        new("khanh-hoa", "Khánh Hòa", "Miền Trung", ["Ninh Thuận"], ["Nha Trang", "Cam Ranh", "Ninh Hòa", "Vạn Ninh", "Phan Rang", "Ninh Hải"], ["dulich", "thuysan"],
            "Du lịch biển Nha Trang – Cam Ranh với mật độ khách sạn, resort cao, cùng năng lượng tái tạo và nông nghiệp của Ninh Thuận cũ. Ngành khách sạn – nhà hàng chấm công ca xoay 24/7."),

        // ── Tây Nguyên ──
        new("dak-lak", "Đắk Lắk", "Tây Nguyên", ["Phú Yên"], ["Buôn Ma Thuột", "Buôn Hồ", "Ea Kar", "Tuy Hòa", "Sông Cầu", "Đông Hòa"], ["nongnghiep", "dulich", "thuysan"],
            "Thủ phủ cà phê Buôn Ma Thuột với nhiều doanh nghiệp chế biến nông sản, nối với vùng biển Tuy Hòa của Phú Yên cũ. Lao động thời vụ tăng mạnh vào mùa thu hoạch."),
        new("lam-dong", "Lâm Đồng", "Tây Nguyên", ["Đắk Nông", "Bình Thuận"], ["Đà Lạt", "Bảo Lộc", "Đức Trọng", "Gia Nghĩa", "Phan Thiết", "Mũi Né", "La Gi"], ["dulich", "nongnghiep"],
            "Du lịch Đà Lạt và Mũi Né – Phan Thiết, nông nghiệp công nghệ cao, chè Bảo Lộc và khai khoáng của Đắk Nông cũ. Nông trại, nhà kính và khu nghỉ dưỡng cần chấm công theo vị trí."),

        // ── Miền Nam ──
        new("ho-chi-minh", "TP. Hồ Chí Minh", "Miền Nam", ["Bình Dương", "Bà Rịa – Vũng Tàu"], ["Quận 1", "Tân Bình", "Gò Vấp", "Thủ Đức", "Thủ Dầu Một", "Dĩ An", "Thuận An", "Bến Cát", "Vũng Tàu", "Bà Rịa", "Phú Mỹ"], ["kcn", "thuongmai", "dulich"],
            "Trung tâm kinh tế lớn nhất cả nước, nay gồm cả Bình Dương với VSIP, Mỹ Phước, Sóng Thần và Bà Rịa – Vũng Tàu với cảng Cái Mép, khu công nghiệp Phú Mỹ. Từ chuỗi F&B, bán lẻ, văn phòng đến nhà máy hàng nghìn công nhân đều cần chấm công tập trung nhiều chi nhánh."),
        new("dong-nai", "Đồng Nai", "Miền Nam", ["Bình Phước"], ["Biên Hòa", "Long Khánh", "Long Thành", "Nhơn Trạch", "Trảng Bom", "Đồng Xoài", "Chơn Thành"], ["kcn", "nongnghiep"],
            "Một trong những địa phương nhiều khu công nghiệp nhất (Amata, Biên Hòa, Nhơn Trạch, Long Thành), thêm các khu công nghiệp Chơn Thành, Minh Hưng và vùng cao su, điều của Bình Phước cũ. Nhà máy da giày, may mặc, điện tử đông công nhân."),
        new("tay-ninh", "Tây Ninh", "Miền Nam", ["Long An"], ["Tây Ninh", "Trảng Bàng", "Hòa Thành", "Tân An", "Bến Lức", "Đức Hòa", "Cần Giuộc"], ["kcn", "nongnghiep", "cuakhau"],
            "Khu công nghiệp Phước Đông – Trảng Bàng, cửa khẩu Mộc Bài cùng hành lang công nghiệp Bến Lức, Đức Hòa của Long An cũ giáp TP. Hồ Chí Minh. Doanh nghiệp sản xuất, kho vận tăng trưởng nhanh."),
        new("can-tho", "Cần Thơ", "Miền Nam", ["Sóc Trăng", "Hậu Giang"], ["Ninh Kiều", "Cái Răng", "Bình Thủy", "Sóc Trăng", "Vị Thanh", "Ngã Bảy"], ["thuongmai", "thuysan", "nongnghiep"],
            "Trung tâm vùng Đồng bằng sông Cửu Long với thương mại – dịch vụ, chế biến thủy sản, lúa gạo và các khu công nghiệp Trà Nóc, Hòa Phú. Nhà máy chế biến dùng nhiều lao động ca kíp."),
        new("vinh-long", "Vĩnh Long", "Miền Nam", ["Bến Tre", "Trà Vinh"], ["Vĩnh Long", "Bình Minh", "Bến Tre", "Mỏ Cày", "Trà Vinh", "Duyên Hải"], ["nongnghiep", "thuysan"],
            "Vùng dừa Bến Tre, cây ăn trái, thủy sản và năng lượng gió Trà Vinh. Doanh nghiệp chế biến nông – thủy sản có nhiều xưởng và lao động thời vụ."),
        new("dong-thap", "Đồng Tháp", "Miền Nam", ["Tiền Giang"], ["Cao Lãnh", "Sa Đéc", "Hồng Ngự", "Mỹ Tho", "Gò Công", "Cai Lậy"], ["nongnghiep", "thuysan", "kcn"],
            "Lúa gạo, cá tra, hoa kiểng Sa Đéc và khu công nghiệp Long Giang, Tân Hương của Tiền Giang cũ. Chế biến thủy sản xuất khẩu cần chấm công chính xác cho ca đêm."),
        new("an-giang", "An Giang", "Miền Nam", ["Kiên Giang"], ["Long Xuyên", "Châu Đốc", "Tân Châu", "Rạch Giá", "Hà Tiên", "Phú Quốc"], ["dulich", "thuysan", "cuakhau"],
            "Từ Long Xuyên, Châu Đốc với lúa gạo, cá tra đến du lịch đảo Phú Quốc, Hà Tiên của Kiên Giang cũ. Resort, khách sạn trên đảo và nhà máy chế biến đều cần chấm công nhiều điểm."),
        new("ca-mau", "Cà Mau", "Miền Nam", ["Bạc Liêu"], ["Cà Mau", "Năm Căn", "Sông Đốc", "Bạc Liêu", "Giá Rai"], ["thuysan", "nongnghiep"],
            "Thủ phủ tôm và chế biến thủy sản, khí – điện – đạm Cà Mau, điện gió Bạc Liêu. Nhà máy chế biến làm ca liên tục với lượng công nhân lớn."),
    ];

    public static Province? FindProvince(string slug) =>
        Provinces.FirstOrDefault(p => p.Slug.Equals(slug, StringComparison.OrdinalIgnoreCase));

    const string LocalBase = "/lap-dat-may-cham-cong";

    /// <summary>Tỉnh đặt văn phòng SBOX (khớp địa chỉ trong Organization()).</summary>
    const string OfficeSlug = "da-nang";
    const string OfficeAddress = "184 Nam Cao, Hòa Khánh, Đà Nẵng";

    /// <summary>Máy chấm công đang bán — Super Admin nhập ở Thiết lập › Landing «Sản phẩm thiết bị» (landing_products).</summary>
    public record DeviceOffer(string Name, string? Sub, string? Price, string? OldPrice, string? Specs, string? Brand);

    public static List<DeviceOffer> ParseDevices(string? json)
    {
        var list = new List<DeviceOffer>();
        if (string.IsNullOrWhiteSpace(json)) return list;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return list;
            string? Str(JsonElement e, string k) =>
                e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(v.GetString()) ? v.GetString()!.Trim() : null;
            foreach (var e in doc.RootElement.EnumerateArray())
            {
                if (e.ValueKind != JsonValueKind.Object || Str(e, "name") is not { } name) continue;
                list.Add(new DeviceOffer(name, Str(e, "sub"), Str(e, "price"), Str(e, "oldPrice"), Str(e, "specs"), Str(e, "brand")));
            }
        }
        catch (JsonException) { }
        return list;
    }

    /// <summary>"1.950.000 d" → 1950000; "Liên hệ" → null.</summary>
    static long? PriceValue(string? price)
    {
        var digits = new string((price ?? "").Where(char.IsDigit).ToArray());
        return digits.Length is >= 5 and <= 10 ? long.Parse(digits) : null;
    }

    static string Vnd(long v) => v.ToString("#,0", CultureInfo.InvariantCulture).Replace(',', '.') + " đ";

    static string DeviceSection(IReadOnlyList<DeviceOffer> devices, string where)
    {
        if (devices.Count == 0) return "";
        var sb = new StringBuilder($"<h2 id=\"bang-gia-may\">Bảng giá máy chấm công tham khảo{where}</h2>\n");
        sb.Append("<div class=\"table-wrap\"><table><thead><tr><th>Máy chấm công</th><th>Chấm công bằng</th><th>Giá tham khảo</th></tr></thead><tbody>");
        foreach (var d in devices)
        {
            var price = PriceValue(d.Price) is { } v ? Vnd(v) : (d.Price ?? "Liên hệ");
            var old = PriceValue(d.OldPrice) is { } o && PriceValue(d.Price) is { } n && o > n ? $" <s style=\"color:var(--m);font-weight:400\">{E(Vnd(o))}</s>" : "";
            sb.Append($"<tr><td><strong>{E(d.Name)}</strong>{(d.Sub == null ? "" : $"<br><span style=\"color:var(--m);font-size:14px\">{E(d.Sub)}</span>")}</td>")
              .Append($"<td>{E(d.Specs ?? "")}</td><td><strong>{E(price)}</strong>{old}</td></tr>");
        }
        sb.Append("</tbody></table></div>\n");
        sb.Append("<p style=\"font-size:15px;color:var(--m)\">Giá tham khảo, có thể thay đổi theo thời điểm và số lượng. Khi mua máy được <strong>miễn phí lắp đặt</strong> và <strong>tặng phần mềm chấm công SBOX HRM</strong>. <a href=\"#bao-gia\">Nhận báo giá chính xác →</a></p>\n");
        return sb.ToString();
    }

    static (long Min, long Max, string MinName)? PriceRange(IReadOnlyList<DeviceOffer> devices)
    {
        var priced = devices.Select(d => (d, v: PriceValue(d.Price))).Where(x => x.v.HasValue).ToList();
        if (priced.Count == 0) return null;
        var min = priced.MinBy(x => x.v)!;
        return (min.v!.Value, priced.Max(x => x.v!.Value), min.d.Name);
    }

    static string MapEmbedUrl => "https://www.google.com/maps?q=" + Uri.EscapeDataString(OfficeAddress) + "&output=embed";
    static string MapLinkUrl => "https://www.google.com/maps/search/?api=1&query=" + Uri.EscapeDataString(OfficeAddress);

    static string OfficeSection() => $"""
<h2 id="van-phong">Văn phòng SBOX tại Đà Nẵng</h2>
<p>SBOX đặt văn phòng tại <strong>{E(OfficeAddress)}</strong> (khu Hòa Khánh – Liên Chiểu). Doanh nghiệp tại Đà Nẵng và Quảng Nam cũ được kỹ thuật đến khảo sát, lắp máy tận nơi; có thể gọi trước để hẹn qua văn phòng trao đổi trực tiếp.</p>
<ul>
<li><strong>Địa chỉ:</strong> {E(OfficeAddress)} — <a href="{E(MapLinkUrl)}" target="_blank" rel="noopener">Chỉ đường Google Maps</a></li>
<li><strong>Hotline / Zalo:</strong> <a href="tel:+84973024042">0973 024 042</a></li>
<li><strong>Email:</strong> <a href="mailto:support@sboxhrm.com">support@sboxhrm.com</a></li>
</ul>
<div style="border-radius:14px;overflow:hidden;border:1px solid var(--b, #e2e8f0);margin:12px 0 8px"><iframe src="{E(MapEmbedUrl)}" title="Bản đồ văn phòng SBOX tại Đà Nẵng" width="100%" height="320" style="border:0;display:block" loading="lazy" referrerpolicy="no-referrer-when-downgrade"></iframe></div>
""";

    /// <summary>Doanh nghiệp tại địa chỉ văn phòng — chỉ gắn trên trang Đà Nẵng.</summary>
    static object OfficeBusiness(SiteInfo s, string pageUrl) => new Dictionary<string, object>
    {
        ["@context"] = "https://schema.org",
        ["@type"] = "LocalBusiness",
        ["@id"] = s.Origin + "/#local-da-nang",
        ["name"] = s.Brand + " – Máy chấm công Đà Nẵng",
        ["url"] = pageUrl,
        ["image"] = s.Origin + s.Logo,
        ["telephone"] = "+84-973-024-042",
        ["email"] = "support@sboxhrm.com",
        ["address"] = new Dictionary<string, object>
        {
            ["@type"] = "PostalAddress", ["streetAddress"] = "184 Nam Cao", ["addressLocality"] = "Hòa Khánh",
            ["addressRegion"] = "Đà Nẵng", ["addressCountry"] = "VN",
        },
        ["hasMap"] = MapLinkUrl,
        ["areaServed"] = new[] { "Đà Nẵng", "Quảng Nam" },
        ["parentOrganization"] = new Dictionary<string, object> { ["@id"] = s.Origin + "/#organization" },
    };

    /// <summary>
    /// Chấm công trên điện thoại / MacBook / trình duyệt và so sánh với phần mềm chấm công cài máy tính Windows kiểu cũ
    /// (loại đi kèm máy chấm công, kết nối LAN/USB). Không nêu tên sản phẩm cụ thể trong bảng — chỉ mô tả kiểu cài đặt.
    /// </summary>
    static string CloudSection(string where, string? name) => $"""
<h2 id="cham-cong-moi-noi">Quản lý chấm công qua điện thoại, MacBook, trình duyệt web{where}</h2>
<p>Máy chấm công lắp{where} tự gửi dữ liệu lên SBOX HRM qua Internet. Chủ doanh nghiệp, kế toán xem bảng công <strong>trên điện thoại (Android, iOS), MacBook, máy tính Windows hoặc bất kỳ trình duyệt web nào</strong> — không phải cài phần mềm, không cần để một máy tính bật suốt ở văn phòng{(name == null ? "" : $", kể cả khi đang đi công tác ngoài {E(name)}")}.</p>
<div class="table-wrap"><table><thead><tr><th>Nhu cầu</th><th>Phần mềm chấm công cài máy tính kiểu cũ</th><th>SBOX HRM (online)</th></tr></thead><tbody>
<tr><td><strong>Xem công trên MacBook, điện thoại</strong></td><td>Thường chỉ chạy trên máy tính Windows đã cài đặt</td><td>Mở trình duyệt hoặc app trên mọi thiết bị</td></tr>
<tr><td><strong>Lấy dữ liệu từ máy chấm công</strong></td><td>Tải về qua mạng LAN / USB, phải ngồi tại văn phòng</td><td>Máy tự đẩy dữ liệu qua Internet (ADMS) vài giây sau khi chấm</td></tr>
<tr><td><strong>Nhiều chi nhánh</strong></td><td>Mỗi nơi một máy tính, gom dữ liệu thủ công</td><td>Một tài khoản xem công toàn bộ chi nhánh</td></tr>
<tr><td><strong>Chấm công không cần máy</strong></td><td>Không có</td><td>Chấm công qua điện thoại: khuôn mặt + GPS + WiFi</td></tr>
<tr><td><strong>Đơn từ, phiếu lương</strong></td><td>Giấy tờ, nhập tay</td><td>Nhân viên gửi đơn nghỉ phép, tăng ca và xem phiếu lương trên app</td></tr>
<tr><td><strong>Tính lương</strong></td><td>Xuất Excel rồi tính tay</td><td>Tự tính ngày công, tăng ca, phụ cấp, BHXH, thuế TNCN</td></tr>
<tr><td><strong>Sao lưu dữ liệu</strong></td><td>Mất khi hỏng ổ cứng, cài lại Windows</td><td>Lưu trên máy chủ, đổi máy tính không mất dữ liệu</td></tr>
</tbody></table></div>
<p>Đang dùng phần mềm chấm công cài trên máy tính? Máy ZKTeco có hỗ trợ ADMS vẫn giữ nguyên và chuyển sang kết nối SBOX HRM — xem <a href="/bai-viet/chuyen-phan-mem-cham-cong-cai-may-sang-online">hướng dẫn chuyển sang chấm công online</a>.</p>
""";

    /// <summary>Ảnh lắp đặt thực tế của SBOX (flutter_client/web/images/lap-dat; bản -sm.webp rộng 480px).</summary>
    public record InstallPhoto(int No, string Alt, int W, int H)
    {
        public string Src => $"/images/lap-dat/lap-dat-may-cham-cong-{No:00}.webp";
        public string Small => $"/images/lap-dat/lap-dat-may-cham-cong-{No:00}-sm.webp";
    }

    public static readonly IReadOnlyList<InstallPhoto> InstallPhotos =
    [
        new(1, "Máy chấm công vân tay, thẻ từ ZKTeco lắp trên cửa kính văn phòng", 800, 620),
        new(2, "Kỹ thuật SBOX lắp máy chấm công vân tay tại cửa kính văn phòng", 682, 733),
        new(3, "Máy chấm công khuôn mặt, vân tay ZKTeco mới nguyên hộp trước khi lắp đặt", 960, 1280),
        new(4, "Máy chấm công vân tay gắn tường đã cấp nguồn, sẵn sàng chấm công", 960, 1280),
        new(5, "Máy chấm công vân tay màn hình màu đặt trên bàn", 960, 1280),
        new(6, "Máy chấm công vân tay lắp tường cạnh ổ điện, đi dây gọn", 960, 1280),
        new(7, "Máy chấm công vân tay lắp tại hành lang văn phòng công ty", 960, 585),
        new(8, "Máy chấm công vân tay lắp ở lối vào khu làm việc", 960, 946),
        new(9, "Máy chấm công vân tay gắn cột cạnh cửa phòng làm việc", 900, 1200),
        new(10, "Máy chấm công khuôn mặt, vân tay ZKTeco lắp trên cột gỗ", 960, 1280),
    ];

    /// <summary>Mỗi tỉnh một bộ 4 ảnh (xoay vòng theo thứ tự tỉnh) — 34 trang không dùng y hệt một bộ ảnh.</summary>
    static List<InstallPhoto> PhotosFor(Province? p)
    {
        // Trang tổng và Đà Nẵng (nơi đặt văn phòng) hiện đủ bộ ảnh.
        if (p == null || p.Slug == OfficeSlug) return InstallPhotos.ToList();
        var i = Math.Max(0, Provinces.ToList().FindIndex(x => x.Slug == p.Slug));
        return Enumerable.Range(0, 4).Select(k => InstallPhotos[(i * 3 + k) % InstallPhotos.Count]).ToList();
    }

    static string HeroImage(InstallPhoto ph) =>
        $"<div><img src=\"{ph.Src}\" alt=\"{E(ph.Alt)}\" width=\"{ph.W}\" height=\"{ph.H}\" fetchpriority=\"high\" style=\"max-height:420px;width:auto;max-width:100%;margin:0 auto;display:block;border-radius:16px;object-fit:contain\"></div></div></section>\n";

    static string GallerySection(IReadOnlyList<InstallPhoto> photos, string where) =>
        "<h2 id=\"hinh-anh\">Hình ảnh lắp đặt máy chấm công thực tế</h2>\n"
        + $"<p>Một số công trình máy chấm công vân tay, khuôn mặt do kỹ thuật SBOX lắp đặt — cùng quy trình áp dụng cho khách hàng{where}.</p>\n"
        + "<div style=\"display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px;margin:14px 0 8px\">"
        + string.Concat(photos.Select(ph =>
            $"<a href=\"{ph.Src}\" target=\"_blank\" rel=\"noopener\" style=\"display:block;border-radius:12px;overflow:hidden;background:#f1f5f9;aspect-ratio:3/4\">"
            + $"<img src=\"{ph.Small}\" alt=\"{E(ph.Alt)}\" width=\"480\" height=\"{ph.H * 480 / ph.W}\" loading=\"lazy\" decoding=\"async\" style=\"width:100%;height:100%;object-fit:cover;display:block;margin:0\"></a>"))
        + "</div>\n";

    static string OldText(Province p) => p.Old.Length == 0 ? "" : $" (gồm {string.Join(", ", p.Old)} cũ)";

    /// <summary>Gợi ý cấu hình theo đặc điểm doanh nghiệp của tỉnh.</summary>
    static List<(string Need, string Fit)> Advice(Province p)
    {
        var a = new List<(string, string)>();
        if (p.Tags.Contains("kcn"))
            a.Add(("Nhà máy, xưởng đông công nhân", "Máy chấm công khuôn mặt ZKTeco tốc độ cao đặt tại cổng ra vào, kết nối Internet (ADMS); xếp ca 2–3 kíp, tính tăng ca tự động"));
        if (p.Tags.Contains("dulich"))
            a.Add(("Khách sạn, resort, nhà hàng", "Máy khuôn mặt nhỏ gọn ở khu nhân viên hoặc chấm công điện thoại theo WiFi; ca xoay, ca gãy, lao động thời vụ"));
        if (p.Tags.Contains("thuongmai"))
            a.Add(("Chuỗi cửa hàng, văn phòng nhiều chi nhánh", "Mỗi chi nhánh một máy vân tay / khuôn mặt hoặc điện thoại theo vị trí; xem công toàn chuỗi trên một màn hình"));
        if (p.Tags.Contains("nongnghiep"))
            a.Add(("Nông trại, cơ sở chế biến nông sản", "Chấm công điện thoại theo vị trí GPS cho lao động ngoài đồng; máy khuôn mặt tại xưởng chế biến; tính công lao động thời vụ"));
        if (p.Tags.Contains("thuysan"))
            a.Add(("Nhà máy chế biến thủy sản", "Máy khuôn mặt không chạm (tay ướt, đeo găng vẫn chấm được); ca đêm, tăng ca theo đơn hàng"));
        if (p.Tags.Contains("cuakhau"))
            a.Add(("Kho vận, logistics, xuất nhập khẩu", "Máy chấm công tại từng kho kết nối Internet, ca ngày – ca đêm; nhân viên giao nhận chấm công điện thoại"));
        if (p.Tags.Contains("vungcao"))
            a.Add(("Điểm làm việc phân tán, vùng sâu vùng xa", "Chấm công điện thoại có khuôn mặt + GPS, không cần đi dây; máy chấm công chỉ đặt ở trụ sở chính"));
        return a;
    }

    static object LocalService(Province? p) => new Dictionary<string, object>
    {
        ["@context"] = "https://schema.org",
        ["@type"] = "Service",
        ["name"] = p == null ? "Lắp đặt máy chấm công vân tay, khuôn mặt ZKTeco toàn quốc" : $"Lắp đặt máy chấm công tại {p.Name}",
        ["serviceType"] = "Cung cấp, lắp đặt máy chấm công vân tay, khuôn mặt và phần mềm chấm công",
        ["provider"] = Organization(Hrm),
        ["areaServed"] = p == null
            ? new Dictionary<string, object> { ["@type"] = "Country", ["name"] = "Việt Nam" }
            : new Dictionary<string, object> { ["@type"] = "AdministrativeArea", ["name"] = p.Name, ["containedInPlace"] = new Dictionary<string, object> { ["@type"] = "Country", ["name"] = "Việt Nam" } },
        ["offers"] = new Dictionary<string, object>
        {
            ["@type"] = "Offer", ["priceCurrency"] = "VND", ["price"] = "0",
            ["description"] = "Miễn phí lắp đặt và tặng phần mềm chấm công SBOX HRM khi mua máy chấm công",
        },
    };

    static List<FaqItem> LocalFaq(Province? p, IReadOnlyList<DeviceOffer>? devices = null)
    {
        var at = p == null ? "" : $" tại {p.Name}";
        var own = new List<FaqItem>();
        if (p?.Slug == OfficeSlug)
            own.Add(new("Mua máy chấm công ở đâu tại Đà Nẵng",
                $"Văn phòng SBOX ở {OfficeAddress}. Gọi hoặc nhắn Zalo 0973 024 042 để được tư vấn, báo giá và hẹn kỹ thuật đến lắp tận nơi tại Đà Nẵng, Hội An, Tam Kỳ, Điện Bàn và các địa bàn Quảng Nam cũ."));
        if (PriceRange(devices ?? []) is { } r)
            own.Add(new($"Giá máy chấm công{at} bao nhiêu",
                r.Min == r.Max
                    ? $"Máy chấm công SBOX đang cung cấp có giá tham khảo {Vnd(r.Min)}, miễn phí lắp đặt{at} và tặng phần mềm chấm công SBOX HRM."
                    : $"Giá tham khảo từ {Vnd(r.Min)} ({r.MinName}) đến {Vnd(r.Max)} tùy loại vân tay hay khuôn mặt; khi mua máy được miễn phí lắp đặt{at} và tặng phần mềm chấm công SBOX HRM. Giá thay đổi theo số lượng — gọi 0973 024 042 để nhận báo giá."));
        if (p != null)
            foreach (var (need, fit) in Advice(p).Take(2))
                own.Add(new($"{need} tại {p.Name} nên dùng máy chấm công nào", fit + "."));
        return
        [
            .. own,
            new($"Lắp đặt máy chấm công{at} có mất phí không",
                $"Khi mua máy chấm công tại SBOX, khách hàng{at} được miễn phí lắp đặt, cài đặt kết nối Internet và tặng phần mềm chấm công SBOX HRM theo chương trình ưu đãi hiện hành. Gọi hoặc nhắn Zalo 0973 024 042 để nhận báo giá máy."),
            new($"SBOX có lắp đặt tận nơi{at} không",
                $"Có. SBOX nhận lắp đặt tận nơi trên toàn quốc{(p == null ? "" : $", bao gồm các địa bàn của {p.Name}{OldText(p)}")}. Kỹ thuật hẹn lịch, lắp máy, đăng ký vân tay – khuôn mặt cho nhân viên và hướng dẫn sử dụng phần mềm."),
            new("SBOX có phải nhà phân phối máy chấm công ZKTeco không",
                "SBOX là đơn vị cung cấp, lắp đặt máy chấm công ZKTeco và phát triển phần mềm chấm công – tính lương SBOX HRM; SBOX không phải nhà phân phối độc quyền hay đại lý chính thức của hãng ZKTeco. Phần mềm SBOX HRM kết nối các máy ZKTeco có hỗ trợ ADMS, kể cả máy doanh nghiệp đã mua ở nơi khác."),
            new("Không lắp máy thì có chấm công bằng điện thoại được không",
                "Được. Nhân viên chấm công bằng app SBOX HRM trên điện thoại với nhận diện khuôn mặt, kiểm tra vị trí GPS hoặc WiFi nơi làm việc và khóa thiết bị đã đăng ký — phù hợp cửa hàng nhỏ, nhân viên đi thị trường hoặc làm việc phân tán."),
            new($"Xem bảng chấm công{at} trên MacBook, điện thoại được không",
                "Được. SBOX HRM chạy trên trình duyệt web (Chrome, Safari, Edge) nên dùng được trên MacBook, máy tính Windows, máy tính bảng; quản lý và nhân viên dùng thêm app SBOX HRM trên Android, iOS. Không cần cài phần mềm hay để máy tính bật ở văn phòng như phần mềm chấm công cài máy kiểu cũ."),
            new("Nên chọn máy chấm công vân tay hay khuôn mặt",
                "Văn phòng ít người có thể dùng máy vân tay giá tốt; nhà xưởng đông công nhân, nhân viên làm việc tay chân hoặc cần chấm nhanh nên chọn máy khuôn mặt không chạm. Nên chọn máy có ADMS để kết nối phần mềm qua Internet."),
        ];
    }

    static string LocalLeadSection(string plan) =>
        "<section id=\"bao-gia\" class=\"lp-sec\"><h2 class=\"t\">Nhận báo giá máy chấm công & lịch lắp đặt</h2>"
        + "<p class=\"s\">Để lại số điện thoại — SBOX gọi lại tư vấn loại máy phù hợp, báo giá tốt và hẹn lịch lắp đặt miễn phí.</p>"
        + LeadForm("bao-gia-form", "/api/public/leads", "Nhận báo giá", plan, withNote: true) + "</section>\n";

    static string ProcessSection(string where) => $"""
<h2 id="quy-trinh">Quy trình lắp đặt máy chấm công{where}</h2>
<ol>
<li><strong>Tư vấn & báo giá</strong>: số nhân viên, số cửa ra vào, ca làm việc → chọn loại máy (vân tay, khuôn mặt, thẻ) và số lượng.</li>
<li><strong>Hẹn lịch lắp đặt</strong> tận nơi, khảo sát vị trí đặt máy, nguồn điện và mạng Internet.</li>
<li><strong>Lắp máy & kết nối Internet (ADMS)</strong>: máy tự gửi dữ liệu lên phần mềm, không cần IP tĩnh, không cần máy tính cài sẵn.</li>
<li><strong>Đăng ký vân tay, khuôn mặt</strong> cho nhân viên, ghép với hồ sơ trên phần mềm SBOX HRM.</li>
<li><strong>Cài ca làm việc, chính sách lương</strong> và hướng dẫn quản lý xem công, xuất bảng lương.</li>
</ol>
""";

    static string WhySection() => """
<h2 id="vi-sao">Vì sao chọn SBOX?</h2>
<ul>
<li><strong>Giá tốt</strong>: báo giá máy chấm công ZKTeco theo đúng nhu cầu, không bán thừa thiết bị.</li>
<li><strong>Miễn phí lắp đặt</strong> khi mua máy, lắp tận nơi trên toàn quốc.</li>
<li><strong>Tặng phần mềm chấm công SBOX HRM</strong>: tự tính công, đi trễ, về sớm, tăng ca và bảng lương — xem trên web và điện thoại.</li>
<li><strong>Chấm công qua điện thoại</strong> cho nhân viên không ngồi một chỗ: khuôn mặt + GPS + WiFi, chống chấm hộ.</li>
<li><strong>Kết nối máy cũ</strong>: máy ZKTeco có ADMS doanh nghiệp đang dùng vẫn kết nối được phần mềm.</li>
<li><strong>Hỗ trợ nhanh</strong> qua hotline / Zalo 0973 024 042, điều khiển từ xa khi cần.</li>
</ul>
""";

    public static string LocalHubPage(IReadOnlyList<DeviceOffer>? devices = null)
    {
        var s = Hrm;
        var url = s.Origin + LocalBase;
        var title = "Lắp đặt máy chấm công vân tay, khuôn mặt toàn quốc | SBOX";
        var desc = "Lắp đặt máy chấm công vân tay, khuôn mặt ZKTeco tại 34 tỉnh thành: giá tốt, miễn phí lắp đặt, tặng phần mềm chấm công, chấm công qua điện thoại. Gọi 0973 024 042.";
        devices ??= [];
        var faq = LocalFaq(null, devices);
        var ld = new List<object>
        {
            LocalService(null),
            Crumbs(s, ("Trang chủ", s.Origin + "/"), ("Lắp đặt máy chấm công", url)),
        };
        if (FaqLd(faq) is { } f) ld.Add(f);
        var kw = "lắp đặt máy chấm công, máy chấm công vân tay, máy chấm công khuôn mặt, máy chấm công zkteco, phần mềm chấm công, chấm công qua điện thoại, phần mềm chấm công online, phần mềm chấm công trên macbook, chấm công trên trình duyệt web, máy chấm công giá tốt, miễn phí lắp đặt máy chấm công";
        var hero = InstallPhotos[0];
        var sb = new StringBuilder(Head(s, title, desc, url, s.Origin + hero.Src, "website", kw, ld));
        sb.Append("<section class=\"lp-hero\"><div class=\"wrap\"><div>");
        sb.Append("<div class=\"crumb\" style=\"margin-top:0\"><a href=\"/\">Trang chủ</a> › Lắp đặt máy chấm công</div>");
        sb.Append("<h1>Lắp đặt máy chấm công vân tay, khuôn mặt ZKTeco toàn quốc</h1>");
        sb.Append("<p class=\"lead\">Cung cấp và lắp đặt máy chấm công vân tay, khuôn mặt ZKTeco giá tốt tại 34 tỉnh thành — <strong>miễn phí lắp đặt</strong>, <strong>tặng phần mềm chấm công</strong> SBOX HRM, kết nối Internet xem công mọi nơi, thêm chấm công qua điện thoại cho nhân viên lưu động.</p>");
        sb.Append("<div class=\"lp-actions\"><a class=\"btn\" href=\"#bao-gia\">Nhận báo giá</a><a class=\"btn ghost\" href=\"tel:+84973024042\">Gọi 0973 024 042</a></div>");
        sb.Append("<p class=\"lp-note\">Lắp tận nơi toàn quốc · Tặng phần mềm khi mua máy · Hỗ trợ qua Zalo</p></div>");
        sb.Append(HeroImage(hero));
        sb.Append("<main class=\"wrap\"><div class=\"content\" style=\"max-width:860px\">\n");
        sb.Append("<h2 id=\"chon-tinh\">Chọn tỉnh, thành phố của bạn</h2>\n");
        foreach (var g in Provinces.GroupBy(p => p.Region))
        {
            sb.Append($"<h3>{E(g.Key)}</h3><p>");
            sb.Append(string.Join(" · ", g.Select(p => $"<a href=\"{LocalBase}/{p.Slug}\">Máy chấm công {E(p.Name)}</a>{(p.Old.Length == 0 ? "" : $" <span style=\"color:var(--m);font-size:14px\">({E(string.Join(", ", p.Old))})</span>")}")));
            sb.Append("</p>\n");
        }
        sb.Append("""
<h2 id="dich-vu">Dịch vụ máy chấm công của SBOX</h2>
<ul>
<li>Cung cấp <strong>máy chấm công vân tay, khuôn mặt, thẻ từ ZKTeco</strong> cho văn phòng, nhà xưởng, cửa hàng, khách sạn.</li>
<li><strong>Lắp đặt tận nơi</strong>, kết nối Internet qua ADMS — dữ liệu về phần mềm vài giây sau khi nhân viên chấm.</li>
<li><strong>Tặng phần mềm chấm công SBOX HRM</strong> khi mua máy: bảng công, đi trễ – về sớm, tăng ca, bảng lương.</li>
<li><strong>Chấm công qua điện thoại</strong> bằng khuôn mặt và GPS cho nhân viên thị trường, cửa hàng nhỏ — không cần mua máy.</li>
<li><strong>Kết nối máy ZKTeco đang có</strong> (dòng hỗ trợ ADMS) vào phần mềm.</li>
</ul>
""");
        sb.Append(DeviceSection(devices, ""));
        sb.Append(GallerySection(PhotosFor(null), " trên toàn quốc"));
        sb.Append(CloudSection("", null));
        sb.Append(ProcessSection(""));
        sb.Append(WhySection());
        sb.Append("<p>Tìm hiểu thêm: <a href=\"/tinh-nang/phan-mem-cham-cong-zkteco\">phần mềm chấm công ZKTeco</a>, <a href=\"/tinh-nang/cham-cong-khuon-mat-dien-thoai\">chấm công khuôn mặt qua điện thoại</a>, <a href=\"/bai-viet/cham-cong-khuon-mat-hay-van-tay\">nên chọn máy khuôn mặt hay vân tay</a>.</p>\n");
        sb.Append("</div>\n");
        sb.Append(LocalLeadSection("Lắp máy chấm công"));
        sb.Append("<section class=\"lp-sec faq\"><h2 class=\"t\">Câu hỏi thường gặp</h2>");
        foreach (var q in faq) sb.Append($"<details><summary>{E(q.Question)}</summary><p>{E(q.Answer)}</p></details>");
        sb.Append("</section>\n").Append(Cta(s)).Append("</main>\n").Append(LeadScript).Append(Footer(s));
        return sb.ToString();
    }

    public static string LocalPage(Province p, IReadOnlyList<DeviceOffer>? devices = null)
    {
        var s = Hrm;
        var url = $"{s.Origin}{LocalBase}/{p.Slug}";
        var title = $"Lắp đặt máy chấm công {p.Name} – giá tốt, miễn phí lắp";
        if (title.Length + 7 <= 66) title += " | SBOX";
        var olds = p.Old.Length == 0 ? "" : $", {string.Join(", ", p.Old)}";
        var desc = $"Lắp đặt máy chấm công vân tay, khuôn mặt ZKTeco tại {p.Name}{olds}: giá tốt, miễn phí lắp đặt, tặng phần mềm chấm công, chấm công qua điện thoại.";
        if (desc.Length > 165) desc = $"Lắp máy chấm công vân tay, khuôn mặt ZKTeco tại {p.Name}{olds}: giá tốt, miễn phí lắp, tặng phần mềm chấm công.";
        devices ??= [];
        var office = p.Slug == OfficeSlug;
        var faq = LocalFaq(p, devices);
        var kwParts = new List<string>
        {
            $"lắp đặt máy chấm công {p.Name}", $"máy chấm công {p.Name}", $"máy chấm công vân tay {p.Name}",
            $"máy chấm công khuôn mặt {p.Name}", $"máy chấm công zkteco {p.Name}", $"phần mềm chấm công {p.Name}",
            $"chấm công qua điện thoại {p.Name}", $"phần mềm chấm công online {p.Name}",
            "quản lý chấm công trên điện thoại", "phần mềm chấm công trên macbook", "chấm công trên trình duyệt web",
            "thay phần mềm chấm công cài máy tính",
        };
        kwParts.AddRange(p.Old.Select(o => $"máy chấm công {o}"));
        var ld = new List<object>
        {
            LocalService(p),
            Crumbs(s, ("Trang chủ", s.Origin + "/"), ("Lắp đặt máy chấm công", s.Origin + LocalBase), (p.Name, url)),
        };
        if (office) ld.Add(OfficeBusiness(s, url));
        if (FaqLd(faq) is { } f) ld.Add(f);

        var photos = PhotosFor(p);
        var hero = photos[0];
        var sb = new StringBuilder(Head(s, title, desc, url, s.Origin + hero.Src, "website", string.Join(", ", kwParts), ld));
        sb.Append("<section class=\"lp-hero\"><div class=\"wrap\"><div>");
        sb.Append($"<div class=\"crumb\" style=\"margin-top:0\"><a href=\"/\">Trang chủ</a> › <a href=\"{LocalBase}\">Lắp đặt máy chấm công</a> › {E(p.Name)}</div>");
        sb.Append($"<span class=\"tag\">{E(p.Region)}</span>");
        sb.Append($"<h1>Lắp đặt máy chấm công vân tay, khuôn mặt tại {E(p.Name)}</h1>");
        sb.Append($"<p class=\"lead\">SBOX cung cấp và lắp đặt máy chấm công ZKTeco giá tốt tại {E(p.Name)}{E(OldText(p))}: <strong>miễn phí lắp đặt</strong> khi mua máy, <strong>tặng phần mềm chấm công</strong> SBOX HRM, xem công và bảng lương trên điện thoại.</p>");
        sb.Append("<div class=\"lp-actions\"><a class=\"btn\" href=\"#bao-gia\">Nhận báo giá</a><a class=\"btn ghost\" href=\"tel:+84973024042\">Gọi 0973 024 042</a></div>");
        sb.Append(office
            ? $"<p class=\"lp-note\">Văn phòng tại {E(OfficeAddress)} · Lắp tận nơi · Kết nối Internet (ADMS)</p></div>"
            : "<p class=\"lp-note\">Lắp tận nơi · Kết nối Internet (ADMS) · Chấm công qua điện thoại cho nhân viên lưu động</p></div>");
        sb.Append(HeroImage(hero));

        sb.Append("<main class=\"wrap\"><div class=\"layout\" style=\"margin-top:26px\"><article><div class=\"content\">\n");
        sb.Append($"<h2 id=\"doanh-nghiep\">Doanh nghiệp tại {E(p.Name)} cần chấm công thế nào?</h2>\n<p>{E(p.Profile)}</p>\n");
        if (p.Old.Length > 0)
            sb.Append($"<p>Từ năm 2025, {E(p.Name)} được sắp xếp lại gồm địa bàn {E(p.Name)} và {E(string.Join(", ", p.Old))} trước đây. SBOX phục vụ toàn bộ khu vực mới — doanh nghiệp có chi nhánh ở nhiều địa bàn cũ vẫn xem công tập trung trên một phần mềm.</p>\n");
        var adv = Advice(p);
        if (adv.Count > 0)
        {
            sb.Append($"<h2 id=\"goi-y\">Gợi ý cấu hình máy chấm công tại {E(p.Name)}</h2>\n<div class=\"table-wrap\"><table><thead><tr><th>Loại hình</th><th>Gợi ý</th></tr></thead><tbody>");
            foreach (var (need, fit) in adv) sb.Append($"<tr><td><strong>{E(need)}</strong></td><td>{E(fit)}</td></tr>");
            sb.Append("</tbody></table></div>\n");
        }
        if (office) sb.Append(OfficeSection());
        sb.Append(DeviceSection(devices, $" tại {E(p.Name)}"));
        sb.Append(GallerySection(photos, $" tại {E(p.Name)}"));
        sb.Append($"<h2 id=\"khu-vuc\">Khu vực lắp đặt tại {E(p.Name)}</h2>\n<p>Lắp đặt tận nơi tại các địa bàn: {E(string.Join(", ", p.Places))} và các xã, phường khác{E(OldText(p))}.</p>\n");
        sb.Append($"""
<h2 id="dich-vu">Dịch vụ tại {E(p.Name)}</h2>
<ul>
<li><strong>Máy chấm công vân tay ZKTeco</strong> giá tốt cho văn phòng, cửa hàng.</li>
<li><strong>Máy chấm công khuôn mặt</strong> không chạm cho nhà xưởng, khách sạn, nơi đông nhân viên.</li>
<li><strong>Phần mềm chấm công SBOX HRM</strong> tặng kèm khi mua máy: tự tính công, đi trễ, tăng ca, bảng lương.</li>
<li><strong>Chấm công qua điện thoại</strong> bằng khuôn mặt + GPS cho nhân viên đi thị trường, điểm bán phân tán.</li>
<li><strong>Kết nối máy cũ</strong>: máy ZKTeco hỗ trợ ADMS doanh nghiệp đang dùng vẫn đưa vào phần mềm được.</li>
</ul>
""");
        sb.Append(CloudSection($" tại {E(p.Name)}", p.Name));
        sb.Append(ProcessSection($" tại {E(p.Name)}"));
        sb.Append(WhySection());
        sb.Append("<p>Xem thêm: <a href=\"/tinh-nang/phan-mem-cham-cong-zkteco\">phần mềm chấm công ZKTeco qua Internet</a>, <a href=\"/tinh-nang/cham-cong-khuon-mat-dien-thoai\">chấm công khuôn mặt bằng điện thoại</a>, <a href=\"/bai-viet/cham-cong-khuon-mat-hay-van-tay\">so sánh máy vân tay và khuôn mặt</a>.</p>\n");
        sb.Append("</div>\n");
        sb.Append(LocalLeadSection($"Lắp máy chấm công - {p.Name}"));
        sb.Append("<section class=\"lp-sec faq\"><h2 class=\"t\">Câu hỏi thường gặp</h2>");
        foreach (var q in faq) sb.Append($"<details><summary>{E(q.Question)}</summary><p>{E(q.Answer)}</p></details>");
        sb.Append("</section>\n</article>\n<aside>\n");
        var near = Provinces.Where(x => x.Region == p.Region && x.Slug != p.Slug).ToList();
        sb.Append($"<div class=\"box\"><h2>Lắp máy chấm công {E(p.Region.ToLowerInvariant())}</h2><ul class=\"related\">");
        foreach (var x in near) sb.Append($"<li><a href=\"{LocalBase}/{x.Slug}\">Máy chấm công {E(x.Name)}</a></li>");
        sb.Append($"<li><a href=\"{LocalBase}\">Tất cả 34 tỉnh thành →</a></li></ul></div>\n");
        sb.Append("<div class=\"box\"><h2>Ưu đãi khi mua máy</h2><ul style=\"margin:0 0 12px;padding-left:18px;font-size:15px\"><li>Miễn phí lắp đặt tận nơi</li><li>Tặng phần mềm chấm công SBOX HRM</li><li>Giá tốt theo số lượng</li></ul><a class=\"btn\" href=\"#bao-gia\">Nhận báo giá</a></div>\n");
        sb.Append("</aside></div>\n").Append(Cta(s)).Append("</main>\n").Append(LeadScript).Append(Footer(s));
        return sb.ToString();
    }
}
