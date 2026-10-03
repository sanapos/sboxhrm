using System.Text;

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
        new("da-nang", "Đà Nẵng", "Miền Trung", ["Quảng Nam"], ["Hải Châu", "Thanh Khê", "Sơn Trà", "Liên Chiểu", "Hội An", "Tam Kỳ", "Điện Bàn", "Chu Lai"], ["dulich", "kcn", "thuongmai"],
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

    static List<FaqItem> LocalFaq(Province? p)
    {
        var at = p == null ? "" : $" tại {p.Name}";
        return
        [
            new($"Lắp đặt máy chấm công{at} có mất phí không",
                $"Khi mua máy chấm công tại SBOX, khách hàng{at} được miễn phí lắp đặt, cài đặt kết nối Internet và tặng phần mềm chấm công SBOX HRM theo chương trình ưu đãi hiện hành. Gọi hoặc nhắn Zalo 0973 024 042 để nhận báo giá máy."),
            new($"SBOX có lắp đặt tận nơi{at} không",
                $"Có. SBOX nhận lắp đặt tận nơi trên toàn quốc{(p == null ? "" : $", bao gồm các địa bàn của {p.Name}{OldText(p)}")}. Kỹ thuật hẹn lịch, lắp máy, đăng ký vân tay – khuôn mặt cho nhân viên và hướng dẫn sử dụng phần mềm."),
            new("SBOX có phải nhà phân phối máy chấm công ZKTeco không",
                "SBOX là đơn vị cung cấp, lắp đặt máy chấm công ZKTeco và phát triển phần mềm chấm công – tính lương SBOX HRM; SBOX không phải nhà phân phối độc quyền hay đại lý chính thức của hãng ZKTeco. Phần mềm SBOX HRM kết nối các máy ZKTeco có hỗ trợ ADMS, kể cả máy doanh nghiệp đã mua ở nơi khác."),
            new("Không lắp máy thì có chấm công bằng điện thoại được không",
                "Được. Nhân viên chấm công bằng app SBOX HRM trên điện thoại với nhận diện khuôn mặt, kiểm tra vị trí GPS hoặc WiFi nơi làm việc và khóa thiết bị đã đăng ký — phù hợp cửa hàng nhỏ, nhân viên đi thị trường hoặc làm việc phân tán."),
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

    public static string LocalHubPage()
    {
        var s = Hrm;
        var url = s.Origin + LocalBase;
        var title = "Lắp đặt máy chấm công vân tay, khuôn mặt toàn quốc | SBOX";
        var desc = "Lắp đặt máy chấm công vân tay, khuôn mặt ZKTeco tại 34 tỉnh thành: giá tốt, miễn phí lắp đặt, tặng phần mềm chấm công, chấm công qua điện thoại. Gọi 0973 024 042.";
        var faq = LocalFaq(null);
        var ld = new List<object>
        {
            LocalService(null),
            Crumbs(s, ("Trang chủ", s.Origin + "/"), ("Lắp đặt máy chấm công", url)),
        };
        if (FaqLd(faq) is { } f) ld.Add(f);
        var kw = "lắp đặt máy chấm công, máy chấm công vân tay, máy chấm công khuôn mặt, máy chấm công zkteco, phần mềm chấm công, chấm công qua điện thoại, máy chấm công giá tốt, miễn phí lắp đặt máy chấm công";
        var sb = new StringBuilder(Head(s, title, desc, url, s.Origin + "/images/landing/screenshot-03.jpg", "website", kw, ld));
        sb.Append("<section class=\"lp-hero\"><div class=\"wrap\"><div>");
        sb.Append("<div class=\"crumb\" style=\"margin-top:0\"><a href=\"/\">Trang chủ</a> › Lắp đặt máy chấm công</div>");
        sb.Append("<h1>Lắp đặt máy chấm công vân tay, khuôn mặt ZKTeco toàn quốc</h1>");
        sb.Append("<p class=\"lead\">Cung cấp và lắp đặt máy chấm công vân tay, khuôn mặt ZKTeco giá tốt tại 34 tỉnh thành — <strong>miễn phí lắp đặt</strong>, <strong>tặng phần mềm chấm công</strong> SBOX HRM, kết nối Internet xem công mọi nơi, thêm chấm công qua điện thoại cho nhân viên lưu động.</p>");
        sb.Append("<div class=\"lp-actions\"><a class=\"btn\" href=\"#bao-gia\">Nhận báo giá</a><a class=\"btn ghost\" href=\"tel:+84973024042\">Gọi 0973 024 042</a></div>");
        sb.Append("<p class=\"lp-note\">Lắp tận nơi toàn quốc · Tặng phần mềm khi mua máy · Hỗ trợ qua Zalo</p></div>");
        sb.Append("<div><img src=\"/images/landing/screenshot-03.jpg\" alt=\"Máy chấm công kết nối phần mềm SBOX HRM\" width=\"1200\" height=\"630\"></div></div></section>\n");
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

    public static string LocalPage(Province p)
    {
        var s = Hrm;
        var url = $"{s.Origin}{LocalBase}/{p.Slug}";
        var title = $"Lắp đặt máy chấm công {p.Name} – giá tốt, miễn phí lắp";
        if (title.Length + 7 <= 66) title += " | SBOX";
        var olds = p.Old.Length == 0 ? "" : $", {string.Join(", ", p.Old)}";
        var desc = $"Lắp đặt máy chấm công vân tay, khuôn mặt ZKTeco tại {p.Name}{olds}: giá tốt, miễn phí lắp đặt, tặng phần mềm chấm công, chấm công qua điện thoại.";
        if (desc.Length > 165) desc = $"Lắp máy chấm công vân tay, khuôn mặt ZKTeco tại {p.Name}{olds}: giá tốt, miễn phí lắp, tặng phần mềm chấm công.";
        var faq = LocalFaq(p);
        var kwParts = new List<string>
        {
            $"lắp đặt máy chấm công {p.Name}", $"máy chấm công {p.Name}", $"máy chấm công vân tay {p.Name}",
            $"máy chấm công khuôn mặt {p.Name}", $"máy chấm công zkteco {p.Name}", $"phần mềm chấm công {p.Name}",
            $"chấm công qua điện thoại {p.Name}",
        };
        kwParts.AddRange(p.Old.Select(o => $"máy chấm công {o}"));
        var ld = new List<object>
        {
            LocalService(p),
            Crumbs(s, ("Trang chủ", s.Origin + "/"), ("Lắp đặt máy chấm công", s.Origin + LocalBase), (p.Name, url)),
        };
        if (FaqLd(faq) is { } f) ld.Add(f);

        var sb = new StringBuilder(Head(s, title, desc, url, s.Origin + "/images/landing/screenshot-03.jpg", "website", string.Join(", ", kwParts), ld));
        sb.Append("<section class=\"lp-hero\"><div class=\"wrap\"><div>");
        sb.Append($"<div class=\"crumb\" style=\"margin-top:0\"><a href=\"/\">Trang chủ</a> › <a href=\"{LocalBase}\">Lắp đặt máy chấm công</a> › {E(p.Name)}</div>");
        sb.Append($"<span class=\"tag\">{E(p.Region)}</span>");
        sb.Append($"<h1>Lắp đặt máy chấm công vân tay, khuôn mặt tại {E(p.Name)}</h1>");
        sb.Append($"<p class=\"lead\">SBOX cung cấp và lắp đặt máy chấm công ZKTeco giá tốt tại {E(p.Name)}{E(OldText(p))}: <strong>miễn phí lắp đặt</strong> khi mua máy, <strong>tặng phần mềm chấm công</strong> SBOX HRM, xem công và bảng lương trên điện thoại.</p>");
        sb.Append("<div class=\"lp-actions\"><a class=\"btn\" href=\"#bao-gia\">Nhận báo giá</a><a class=\"btn ghost\" href=\"tel:+84973024042\">Gọi 0973 024 042</a></div>");
        sb.Append("<p class=\"lp-note\">Lắp tận nơi · Kết nối Internet (ADMS) · Chấm công qua điện thoại cho nhân viên lưu động</p></div>");
        sb.Append($"<div><img src=\"/images/landing/screenshot-03.jpg\" alt=\"Máy chấm công tại {E(p.Name)} kết nối phần mềm SBOX HRM\" width=\"1200\" height=\"630\"></div></div></section>\n");

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
