using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Services;

public record StoreSetupSeedResult(
    string Message,
    bool DepartmentsSeeded,
    bool ShiftsSeeded,
    bool HolidaysSeeded,
    bool PenaltySeeded,
    bool AllowancesSeeded);

public record StoreSetupDeleteResult(
    string Message,
    int DepartmentsDeleted,
    int ShiftTemplatesDeleted,
    int HolidaysDeleted,
    int AllowancesDeleted,
    int PenaltySettingsDeleted);

/// <summary>
/// Mẫu thiết lập (phòng ban, ca, phạt, thưởng/phụ cấp, ngày lễ) khi tạo cửa hàng hoặc từ Cài đặt.
/// </summary>
public static class StoreDefaultSetupSeeder
{
    public static readonly string[] SetupCreatedByMarkers = ["Register", "StoreSetup"];
    private static readonly (string Code, string Name, string Description, int SortOrder)[] DepartmentTemplates =
    [
        ("GD", "Giám đốc", "Ban lãnh đạo / điều hành", 1),
        ("KT", "Kế toán", "Tài chính, kế toán", 2),
        ("NS", "Nhân sự", "Quản lý nhân sự, tuyển dụng", 3),
        ("MKT", "Marketing", "Truyền thông, marketing", 4),
        ("KY", "Kỹ thuật", "Kỹ thuật, IT, bảo trì", 5),
        ("SX", "Sản xuất", "Sản xuất, vận hành", 6),
    ];

    private static readonly (string Name, string Code, TimeSpan Start, TimeSpan End, int BreakMin, string ShiftType)[] ShiftTemplates =
    [
        ("Ca hành chính", "HC", new TimeSpan(8, 0, 0), new TimeSpan(17, 0, 0), 60, "HanhChinh"),
        ("Ca sáng", "CS", new TimeSpan(6, 0, 0), new TimeSpan(14, 0, 0), 30, "HanhChinh"),
        ("Ca chiều", "CC", new TimeSpan(14, 0, 0), new TimeSpan(22, 0, 0), 30, "HanhChinh"),
        ("Ca đêm", "CD", new TimeSpan(22, 0, 0), new TimeSpan(6, 0, 0), 30, "QuaDem"),
    ];

    private static readonly (string Name, string? Code, AllowanceType Type, decimal Amount, int Order)[] AllowanceTemplates =
    [
        ("Phụ cấp ăn ca", "PC_AN", AllowanceType.Daily, 35_000, 1),
        ("Phụ cấp đi lại", "PC_XE", AllowanceType.Fixed, 300_000, 2),
        ("Thưởng chuyên cần", "TH_CC", AllowanceType.Fixed, 500_000, 3),
        ("Thưởng hiệu suất", "TH_HS", AllowanceType.PerEvent, 1_000_000, 4),
    ];

    public static async Task SeedDepartmentsIfEmptyAsync(
        IRepository<Department> departmentRepository,
        Guid storeId,
        string createdBy = "StoreSetup",
        CancellationToken cancellationToken = default)
    {
        var existing = await departmentRepository.GetSingleAsync(
            d => d.StoreId == storeId,
            cancellationToken: cancellationToken);
        if (existing != null)
            return;

        var now = DateTime.UtcNow;
        var departments = DepartmentTemplates.Select(t => new Department
        {
            Id = Guid.NewGuid(),
            Code = t.Code,
            Name = t.Name,
            Description = t.Description,
            Level = 0,
            SortOrder = t.SortOrder,
            StoreId = storeId,
            HierarchyPath = "/",
            IsActive = true,
            DirectEmployeeCount = 0,
            TotalEmployeeCount = 0,
            CreatedAt = now,
            CreatedBy = createdBy,
        }).ToList();

        await departmentRepository.AddRangeAsync(departments, cancellationToken);
    }

    /// <summary>
    /// Ca làm, phụ cấp/thưởng, phạt, ngày lễ — cần owner (ManagerId cho mẫu ca).
    /// </summary>
    public static async Task SeedSettingsIfEmptyAsync(
        Guid storeId,
        Guid ownerId,
        IRepository<ShiftTemplate> shiftTemplateRepository,
        IRepository<Holiday> holidayRepository,
        IRepository<PenaltySetting> penaltySettingRepository,
        IRepository<Allowance> allowanceRepository,
        string createdBy = "StoreSetup",
        CancellationToken cancellationToken = default)
    {
        var now = DateTime.UtcNow;

        await SeedShiftTemplatesIfEmptyAsync(
            shiftTemplateRepository, storeId, ownerId, now, createdBy, cancellationToken);

        await SeedHolidaysIfEmptyAsync(
            holidayRepository, storeId, now, createdBy, cancellationToken);

        await SeedPenaltySettingIfEmptyAsync(
            penaltySettingRepository, storeId, now, createdBy, cancellationToken);

        await SeedAllowancesIfEmptyAsync(
            allowanceRepository, storeId, now, createdBy, cancellationToken);
    }

    static async Task SeedShiftTemplatesIfEmptyAsync(
        IRepository<ShiftTemplate> repository,
        Guid storeId,
        Guid ownerId,
        DateTime now,
        string createdBy,
        CancellationToken cancellationToken)
    {
        var existing = await repository.GetSingleAsync(
            s => s.StoreId == storeId,
            cancellationToken: cancellationToken);
        if (existing != null)
            return;

        var shifts = ShiftTemplates.Select(t => new ShiftTemplate
        {
            Id = Guid.NewGuid(),
            ManagerId = ownerId,
            StoreId = storeId,
            Name = t.Name,
            Code = t.Code,
            StartTime = t.Start,
            EndTime = t.End,
            MaximumAllowedLateMinutes = 15,
            MaximumAllowedEarlyLeaveMinutes = 15,
            BreakTimeMinutes = t.BreakMin,
            EarlyCheckInMinutes = 30,
            LateGraceMinutes = 5,
            EarlyLeaveGraceMinutes = 5,
            OvertimeMinutesThreshold = 30,
            ShiftType = t.ShiftType,
            Description = "Mẫu mặc định — có thể chỉnh trong Thiết lập ca",
            IsActive = true,
            CreatedAt = now,
            CreatedBy = createdBy,
        }).ToList();

        await repository.AddRangeAsync(shifts, cancellationToken);
    }

    static async Task SeedHolidaysIfEmptyAsync(
        IRepository<Holiday> repository,
        Guid storeId,
        DateTime now,
        string createdBy,
        CancellationToken cancellationToken)
    {
        var existing = await repository.GetSingleAsync(
            h => h.StoreId == storeId,
            cancellationToken: cancellationToken);
        if (existing != null)
            return;

        var year = now.Year;
        var holidays = VietnamHolidays.GetDefaultHolidays(year)
            .Select(h =>
            {
                h.StoreId = storeId;
                h.CreatedAt = now;
                h.CreatedBy = createdBy;
                h.SalaryRate = h.SalaryRate > 0 ? h.SalaryRate : 3.0;
                h.Category = string.IsNullOrWhiteSpace(h.Category)
                    ? "Ngày nghỉ chính thức"
                    : h.Category;
                h.IsActive = true;
                return h;
            })
            .ToList();

        await repository.AddRangeAsync(holidays, cancellationToken);
    }

    static async Task SeedPenaltySettingIfEmptyAsync(
        IRepository<PenaltySetting> repository,
        Guid storeId,
        DateTime now,
        string createdBy,
        CancellationToken cancellationToken)
    {
        var existing = await repository.GetSingleAsync(
            s => s.StoreId == storeId,
            cancellationToken: cancellationToken);
        if (existing != null)
            return;

        var setting = new PenaltySetting
        {
            StoreId = storeId,
            IsActive = true,
            CreatedAt = now,
            CreatedBy = createdBy,
        };

        await repository.AddAsync(setting, cancellationToken);
    }

    static async Task SeedAllowancesIfEmptyAsync(
        IRepository<Allowance> repository,
        Guid storeId,
        DateTime now,
        string createdBy,
        CancellationToken cancellationToken)
    {
        var existing = await repository.GetSingleAsync(
            a => a.StoreId == storeId,
            cancellationToken: cancellationToken);
        if (existing != null)
            return;

        var allowances = AllowanceTemplates.Select(t => new Allowance
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = t.Name,
            Code = t.Code,
            Description = "Mẫu mặc định — có thể chỉnh trong Phụ cấp & thưởng",
            Type = t.Type,
            Amount = t.Amount,
            Currency = "VND",
            IsTaxable = true,
            IsInsuranceApplicable = false,
            DisplayOrder = t.Order,
            IsActive = true,
            CreatedAt = now,
            CreatedBy = createdBy,
        }).ToList();

        await repository.AddRangeAsync(allowances, cancellationToken);
    }

    public static async Task<StoreSetupSeedResult> SeedAllIfEmptyAsync(
        Guid storeId,
        Guid ownerId,
        IRepository<Department> departmentRepository,
        IRepository<ShiftTemplate> shiftTemplateRepository,
        IRepository<Holiday> holidayRepository,
        IRepository<PenaltySetting> penaltySettingRepository,
        IRepository<Allowance> allowanceRepository,
        string createdBy = "StoreSetup",
        CancellationToken cancellationToken = default)
    {
        var hadDept = await departmentRepository.GetSingleAsync(
            d => d.StoreId == storeId, cancellationToken: cancellationToken) != null;
        var hadShift = await shiftTemplateRepository.GetSingleAsync(
            s => s.StoreId == storeId, cancellationToken: cancellationToken) != null;
        var hadHoliday = await holidayRepository.GetSingleAsync(
            h => h.StoreId == storeId, cancellationToken: cancellationToken) != null;
        var hadPenalty = await penaltySettingRepository.GetSingleAsync(
            s => s.StoreId == storeId, cancellationToken: cancellationToken) != null;
        var hadAllowance = await allowanceRepository.GetSingleAsync(
            a => a.StoreId == storeId, cancellationToken: cancellationToken) != null;

        await SeedDepartmentsIfEmptyAsync(departmentRepository, storeId, createdBy, cancellationToken);
        await SeedSettingsIfEmptyAsync(
            storeId, ownerId,
            shiftTemplateRepository, holidayRepository,
            penaltySettingRepository, allowanceRepository,
            createdBy, cancellationToken);

        var deptAdded = !hadDept && await departmentRepository.GetSingleAsync(
            d => d.StoreId == storeId, cancellationToken: cancellationToken) != null;
        var shiftAdded = !hadShift && await shiftTemplateRepository.GetSingleAsync(
            s => s.StoreId == storeId, cancellationToken: cancellationToken) != null;
        var holidayAdded = !hadHoliday && await holidayRepository.GetSingleAsync(
            h => h.StoreId == storeId, cancellationToken: cancellationToken) != null;
        var penaltyAdded = !hadPenalty && await penaltySettingRepository.GetSingleAsync(
            s => s.StoreId == storeId, cancellationToken: cancellationToken) != null;
        var allowanceAdded = !hadAllowance && await allowanceRepository.GetSingleAsync(
            a => a.StoreId == storeId, cancellationToken: cancellationToken) != null;

        if (!deptAdded && !shiftAdded && !holidayAdded && !penaltyAdded && !allowanceAdded)
        {
            return new StoreSetupSeedResult(
                "Cửa hàng đã có đủ thiết lập. Chỉ thêm phần còn thiếu — không ghi đè dữ liệu hiện có.",
                false, false, false, false, false);
        }

        var parts = new List<string>();
        if (deptAdded) parts.Add("phòng ban");
        if (shiftAdded) parts.Add("ca làm");
        if (allowanceAdded) parts.Add("phụ cấp/thưởng");
        if (penaltyAdded) parts.Add("phạt");
        if (holidayAdded) parts.Add("ngày lễ");

        return new StoreSetupSeedResult(
            parts.Count > 0
                ? $"Đã tạo mẫu thiết lập: {string.Join(", ", parts)}."
                : "Không có mục mới được thêm.",
            deptAdded, shiftAdded, holidayAdded, penaltyAdded, allowanceAdded);
    }
}
