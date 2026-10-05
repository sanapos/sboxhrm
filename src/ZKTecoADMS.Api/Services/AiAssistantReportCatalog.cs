using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Báo cáo trợ lý ảo được gọi — mỗi mục trỏ đúng API báo cáo của app (cùng số liệu với màn hình báo cáo;
/// quyền + gói kiểm lại ở API). Tham số chung của công cụ → tên tham số của từng API.
/// </summary>
public static class AiAssistantReportCatalog
{
    /// <summary>
    /// <paramref name="Params"/>: tham số chung (from, to, date, year, month, limit, group_by, mode, search, department)
    /// → tên query của API. <paramref name="Fixed"/>: query luôn gửi kèm.
    /// </summary>
    public sealed record Report(
        string Id,
        string Line,
        string Path,
        string[] Modules,
        string Description,
        IReadOnlyDictionary<string, string> Params,
        IReadOnlyDictionary<string, string>? Fixed = null);

    static Dictionary<string, string> P(params string[] pairs)
    {
        var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in pairs)
        {
            var i = p.IndexOf('=');
            if (i < 0) d[p] = p;
            else d[p[..i]] = p[(i + 1)..];
        }
        return d;
    }

    static readonly string[] Attendance = ["AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance"];

    public static readonly IReadOnlyList<Report> All =
    [
        // ── Bán hàng (POS) ──
        new("pos_overview", "pos", "/api/pos/reports/analysis/overview", ["PosSalesReport"],
            "Phân tích kinh doanh của kỳ: doanh thu, số đơn, giá trị TB/đơn, giảm giá, hoàn trả, giá vốn, lãi gộp, biên lãi — kèm SO SÁNH kỳ trước và cùng kỳ năm trước. Dùng đầu tiên cho câu hỏi tổng quan / tăng giảm.",
            P("from", "to")),
        new("pos_sales", "pos", "/api/pos/reports/sales/summary", ["PosSalesReport", "PosReportRevenue"],
            "Doanh thu chi tiết: theo NGÀY (byDay, profitByDay), theo phương thức thanh toán (byPayment), top hàng, top nhân viên bán, giảm giá, hoàn trả, đặt cọc.",
            P("from", "to")),
        new("pos_goods", "pos", "/api/pos/reports/goods/summary", ["PosReportSoldGoods"],
            "Hàng bán chạy / bán chậm: số lượng và doanh thu theo từng mặt hàng.",
            P("from", "to", "limit")),
        new("pos_profit_products", "pos", "/api/pos/reports/profit/by-product", ["PosReportProfit"],
            "Lợi nhuận theo mặt hàng: doanh thu, giá vốn, lãi, biên lãi % (xếp theo lãi giảm dần).",
            P("from", "to", "limit")),
        new("pos_profit_by", "pos", "/api/pos/reports/profit/by-dimension", ["PosReportProfit"],
            "Lợi nhuận theo nhóm: group_by = category (nhóm hàng, mặc định) | channel (kênh bán) | staff (nhân viên).",
            P("from", "to", "group_by=groupBy")),
        new("pos_pnl", "pos", "/api/pos/reports/pnl/summary", ["PosReportPnl"],
            "Kết quả kinh doanh (lãi lỗ): doanh thu, giá vốn, chi phí, lãi ròng.",
            P("from", "to")),
        new("pos_cashbook", "pos", "/api/pos/reports/cashbook/summary", ["PosReportCashbook"],
            "Sổ quỹ bán hàng: thu, chi, tồn quỹ theo kỳ.",
            P("from", "to")),
        new("pos_expenses", "pos", "/api/pos/reports/expenses/summary", ["PosReportExpense"],
            "Chi phí theo nhóm chi trong kỳ.",
            P("from", "to")),
        new("pos_staff_sales", "pos", "/api/pos/reports/end-of-day/staff", ["PosReportEndOfDay"],
            "Doanh thu, số đơn theo từng nhân viên bán hàng.",
            P("from", "to")),
        new("pos_commission", "pos", "/api/pos/reports/staff-commission", ["PosReportStaffCommission"],
            "Hoa hồng nhân viên theo hàng / dịch vụ.",
            P("from", "to")),
        new("pos_customers", "pos", "/api/pos/reports/customers/sales", ["PosSalesReport"],
            "Khách hàng mua nhiều: doanh số, số đơn theo khách (search = tên / SĐT).",
            P("from", "to", "search", "limit")),
        new("pos_customer_debt", "pos", "/api/pos/reports/customer-debt", ["PosReportDebt"],
            "Công nợ khách hàng hiện tại (search = tên / SĐT).",
            P("search")),
        new("pos_supplier_debt", "pos", "/api/pos/reports/supplier-debt", ["PosReportDebt"],
            "Công nợ nhà cung cấp hiện tại.",
            P("search")),
        new("pos_purchases", "pos", "/api/pos/reports/purchases/summary", ["PosReportPurchases"],
            "Nhập hàng / trả hàng nhà cung cấp trong kỳ.",
            P("from", "to")),
        new("pos_stock", "pos", "/api/pos/reports/stock/summary", ["PosReportStock"],
            "Tổng quan tồn kho hiện tại: số mặt hàng, giá trị tồn, hàng dưới định mức, hết hàng.",
            P()),
        new("pos_stock_products", "pos", "/api/pos/reports/stock/products", ["PosReportStock"],
            "Danh sách tồn kho từng mặt hàng; mode = All | BelowMin (dưới định mức) | OutOfStock (hết hàng) | AboveMax (vượt tối đa).",
            P("mode=filter", "search"), new Dictionary<string, string> { ["pageSize"] = "50" }),
        new("pos_stock_health", "pos", "/api/pos/reports/stock/health", ["PosProducts"],
            "Sức khỏe tồn kho theo tốc độ bán: mode = hot (bán nhanh sắp hết) | slow (bán chậm) | dead (tồn lâu không bán) | all.",
            P("from", "to", "mode", "limit")),
        new("pos_reorder", "pos", "/api/pos/reports/stock/reorder-suggestions", ["PosReportStock"],
            "Gợi ý hàng cần nhập thêm (theo tốc độ bán và tồn).",
            P()),
        new("pos_expiry", "pos", "/api/pos/reports/stock/lots/summary", ["PosReportExpiry"],
            "Hàng theo lô sắp hết hạn / đã hết hạn.",
            P()),
        new("pos_vouchers", "pos", "/api/pos/reports/vouchers/summary", ["PosReportVoucher"],
            "Mã giảm giá đã dùng, số tiền giảm trong kỳ.",
            P("from", "to")),

        // ── Nhân sự (HRM) ──
        new("hr_attendance_daily", "hrm", "/api/reports/attendance/daily", Attendance,
            "Chấm công MỘT ngày (date): ai có mặt, đi trễ, về sớm, vắng.",
            P("date", "department")),
        new("hr_attendance_monthly", "hrm", "/api/reports/attendance/monthly", Attendance,
            "Bảng công THÁNG (year, month): ngày công, đi trễ, về sớm, vắng theo từng nhân viên.",
            P("year", "month", "department")),
        new("hr_late_early", "hrm", "/api/reports/late-early", Attendance,
            "Đi trễ / về sớm trong khoảng ngày: số lần, số phút theo nhân viên.",
            P("from=startDate", "to=endDate", "department")),
        new("hr_department_summary", "hrm", "/api/reports/department-summary", Attendance,
            "Tổng hợp chấm công theo phòng ban trong tháng (year, month).",
            P("year", "month")),
        new("hr_overtime", "hrm", "/api/reports/overtime", Attendance,
            "Tăng ca theo nhân viên trong khoảng ngày.",
            P("from=startDate", "to=endDate", "department")),
        new("hr_absence", "hrm", "/api/reports/attendance-analytics/absence", Attendance,
            "Phân tích vắng mặt (có phép / không phép) trong khoảng ngày.",
            P("from", "to", "department")),
        new("hr_no_show", "hrm", "/api/reports/attendance-analytics/no-show", Attendance,
            "Có ca nhưng không đến làm (no-show) trong khoảng ngày.",
            P("from", "to", "department")),
        new("hr_compliance", "hrm", "/api/reports/attendance-analytics/compliance", Attendance,
            "Mức tuân thủ giờ giấc theo nhân viên trong tháng (year, month).",
            P("year", "month", "department")),
        new("hr_leave_summary", "hrm", "/api/reports/leave-summary", ["LeaveReport"],
            "Tổng hợp nghỉ phép trong khoảng ngày: theo loại phép, nhân viên.",
            P("from=startDate", "to=endDate", "department")),
        new("hr_leave_balance", "hrm", "/api/reports/leave-shift/leave-balance", ["LeaveReport"],
            "Số dư phép năm còn lại theo nhân viên (year).",
            P("year", "department")),
        new("hr_payroll", "hrm", "/api/payslips/store", ["Payslip"],
            "Bảng lương / phiếu lương cả cửa hàng tháng (year, month): lương thực nhận theo nhân viên, phòng ban.",
            P("year", "month", "department")),
        new("hr_executive", "hrm", "/api/reports/executive/monthly-summary", ["Report"],
            "Tổng hợp điều hành tháng (year, month): nhân sự, chấm công, lương, chi phí.",
            P("year", "month")),
        new("fin_cash", "hrm", "/api/cashtransactions/summary", ["CashTransaction"],
            "Thu chi (sổ quỹ chung) trong khoảng ngày: tổng thu, tổng chi, theo danh mục.",
            P("from=fromDate", "to=toDate")),
        new("fin_penalty", "hrm", "/api/reports/finance/penalty-summary", ["PenaltyReport"],
            "Phiếu phạt trong khoảng ngày theo nhân viên / phòng ban.",
            P("from", "to", "department")),
        new("fin_advance", "hrm", "/api/reports/finance/advance-debt", ["AdvanceReport"],
            "Ứng lương và dư nợ ứng theo nhân viên.",
            P("from", "to", "department")),
    ];

    static readonly Dictionary<string, string> Titles = new(StringComparer.OrdinalIgnoreCase)
    {
        ["pos_overview"] = "Phân tích kinh doanh", ["pos_sales"] = "Doanh thu", ["pos_goods"] = "Hàng bán chạy",
        ["pos_profit_products"] = "Lợi nhuận theo hàng", ["pos_profit_by"] = "Lợi nhuận theo nhóm",
        ["pos_pnl"] = "Kết quả kinh doanh", ["pos_cashbook"] = "Sổ quỹ bán hàng", ["pos_expenses"] = "Chi phí",
        ["pos_staff_sales"] = "Doanh thu theo nhân viên", ["pos_commission"] = "Hoa hồng nhân viên",
        ["pos_customers"] = "Khách hàng mua nhiều", ["pos_customer_debt"] = "Công nợ khách hàng",
        ["pos_supplier_debt"] = "Công nợ nhà cung cấp", ["pos_purchases"] = "Nhập hàng", ["pos_stock"] = "Tồn kho",
        ["pos_stock_products"] = "Tồn kho theo hàng", ["pos_stock_health"] = "Sức khỏe tồn kho",
        ["pos_reorder"] = "Hàng cần nhập thêm", ["pos_expiry"] = "Hàng sắp hết hạn", ["pos_vouchers"] = "Mã giảm giá",
        ["hr_attendance_daily"] = "Chấm công theo ngày", ["hr_attendance_monthly"] = "Bảng công tháng",
        ["hr_late_early"] = "Đi trễ / về sớm", ["hr_department_summary"] = "Chấm công theo phòng ban",
        ["hr_overtime"] = "Tăng ca", ["hr_absence"] = "Vắng mặt", ["hr_no_show"] = "Không đến làm",
        ["hr_compliance"] = "Tuân thủ giờ giấc", ["hr_leave_summary"] = "Nghỉ phép", ["hr_leave_balance"] = "Số dư phép",
        ["hr_payroll"] = "Bảng lương", ["hr_executive"] = "Tổng hợp điều hành", ["fin_cash"] = "Thu chi",
        ["fin_penalty"] = "Phiếu phạt", ["fin_advance"] = "Ứng lương",
    };

    /// <summary>Tên báo cáo hiển thị cho người dùng (không lộ mã nội bộ).</summary>
    public static string TitleOf(string id) => Titles.GetValueOrDefault(id, id);

    public static Report? Find(string? id) =>
        All.FirstOrDefault(r => string.Equals(r.Id, id, StringComparison.OrdinalIgnoreCase));

    /// <summary>Báo cáo người hỏi được xem (gói + vai trò). API vẫn kiểm lại khi chạy.</summary>
    public static List<Report> Allowed(
        IReadOnlyDictionary<string, ModulePermissionDto> perms,
        bool isSuperUser,
        IReadOnlyCollection<string>? packageModules)
    {
        bool InPackage(string m) => packageModules == null || packageModules.Count == 0
            || packageModules.Contains(m, StringComparer.OrdinalIgnoreCase);
        bool CanView(string m) => isSuperUser || (perms.TryGetValue(m, out var p) && p.CanView);
        return All.Where(r => r.Modules.Any(m => InPackage(m) && CanView(m))).ToList();
    }

    /// <summary>Query string cho API từ tham số chung của công cụ (chỉ nhận tham số báo cáo khai báo).</summary>
    public static string BuildQuery(Report report, IReadOnlyDictionary<string, string> args)
    {
        var q = new List<string>();
        foreach (var (generic, apiName) in report.Params)
        {
            if (!args.TryGetValue(generic, out var v) || string.IsNullOrWhiteSpace(v)) continue;
            q.Add($"{Uri.EscapeDataString(apiName)}={Uri.EscapeDataString(v.Trim())}");
        }
        if (report.Fixed != null)
            foreach (var (k, v) in report.Fixed)
                q.Add($"{Uri.EscapeDataString(k)}={Uri.EscapeDataString(v)}");
        return q.Count == 0 ? "" : "?" + string.Join("&", q);
    }
}
