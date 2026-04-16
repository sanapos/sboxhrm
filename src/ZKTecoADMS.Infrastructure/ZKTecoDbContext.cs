using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Application.Interfaces;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using System.Linq.Expressions;
using System.Reflection;

namespace ZKTecoADMS.Infrastructure;

public class ZKTecoDbContext : IdentityDbContext<ApplicationUser, IdentityRole<Guid>, Guid>
{
    // Tenant context — EF Core re-reads these fields per query via global filters
    private readonly Guid? _tenantId;
    private readonly bool _isSuperAccess;

    public ZKTecoDbContext(DbContextOptions<ZKTecoDbContext> options, ITenantProvider? tenantProvider = null) 
        : base(options)
    {
        _tenantId = tenantProvider?.StoreId;
        _isSuperAccess = tenantProvider?.IsSuperAccess ?? true;
    }
    // Authentication & Identity
    public DbSet<UserRefreshToken> UserRefreshTokens => Set<UserRefreshToken>();
    
    // Devices & Biometrics
    public DbSet<DeviceUser> DeviceUsers => Set<DeviceUser>();
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<FingerprintTemplate> FingerprintTemplates => Set<FingerprintTemplate>();
    public DbSet<FaceTemplate> FaceTemplates => Set<FaceTemplate>();
    public DbSet<DeviceCommand> DeviceCommands => Set<DeviceCommand>();
    public DbSet<SyncLog> SyncLogs => Set<SyncLog>();
    public DbSet<DeviceSetting> DeviceSettings => Set<DeviceSetting>();
    public DbSet<DeviceInfo> DeviceInfos => Set<DeviceInfo>();
    
    // Employees & Organization
    public DbSet<Employee> Employees => Set<Employee>();
    public DbSet<Store> Stores => Set<Store>();
    
    // Attendance & Time Management
    public DbSet<Attendance> AttendanceLogs => Set<Attendance>();
    public DbSet<Shift> Shifts => Set<Shift>();
    public DbSet<ShiftTemplate> ShiftTemplates => Set<ShiftTemplate>();
    public DbSet<WorkSchedule> WorkSchedules => Set<WorkSchedule>();
    public DbSet<ScheduleRegistration> ScheduleRegistrations => Set<ScheduleRegistration>();
    public DbSet<ShiftStaffingQuota> ShiftStaffingQuotas => Set<ShiftStaffingQuota>();
    public DbSet<AttendanceCorrectionRequest> AttendanceCorrectionRequests => Set<AttendanceCorrectionRequest>();
    
    // Leave Management
    public DbSet<Leave> Leaves => Set<Leave>();
    public DbSet<LeaveApprovalRecord> LeaveApprovalRecords => Set<LeaveApprovalRecord>();
    
    // Compensation & Benefits
    public DbSet<Benefit> Benefits => Set<Benefit>();
    public DbSet<EmployeeBenefit> EmployeeBenefits => Set<EmployeeBenefit>();
    public DbSet<Allowance> Allowances => Set<Allowance>();
    
    // Payroll & Finance
    public DbSet<Payslip> Payslips => Set<Payslip>();
    public DbSet<AdvanceRequest> AdvanceRequests => Set<AdvanceRequest>();
    public DbSet<AdvanceApprovalRecord> AdvanceApprovalRecords => Set<AdvanceApprovalRecord>();
    public DbSet<PaymentTransaction> PaymentTransactions => Set<PaymentTransaction>();
    
    // Settings & Configuration
    public DbSet<SystemConfiguration> SystemConfigurations => Set<SystemConfiguration>();
    public DbSet<Holiday> Holidays => Set<Holiday>();
    public DbSet<PenaltySetting> PenaltySettings => Set<PenaltySetting>();
    public DbSet<PenaltyTicket> PenaltyTickets => Set<PenaltyTicket>();
    public DbSet<InsuranceSetting> InsuranceSettings => Set<InsuranceSetting>();
    public DbSet<TaxSetting> TaxSettings => Set<TaxSetting>();
    public DbSet<EmployeeTaxDeduction> EmployeeTaxDeductions => Set<EmployeeTaxDeduction>();
    
    // Notifications
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<NotificationCategory> NotificationCategories => Set<NotificationCategory>();
    public DbSet<NotificationPreference> NotificationPreferences => Set<NotificationPreference>();
    
    // Permissions & Roles
    public DbSet<Permission> Permissions => Set<Permission>();
    public DbSet<RolePermission> RolePermissions => Set<RolePermission>();
    public DbSet<DepartmentPermission> DepartmentPermissions => Set<DepartmentPermission>();
    
    // License & Agents
    public DbSet<LicenseKey> LicenseKeys => Set<LicenseKey>();
    public DbSet<Agent> Agents => Set<Agent>();
    public DbSet<ServicePackage> ServicePackages => Set<ServicePackage>();
    public DbSet<KeyActivationPromotion> KeyActivationPromotions => Set<KeyActivationPromotion>();
    
    // System
    public DbSet<AppSettings> AppSettings => Set<AppSettings>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    
    // Task Management
    public DbSet<WorkTask> WorkTasks => Set<WorkTask>();
    public DbSet<TaskComment> TaskComments => Set<TaskComment>();
    public DbSet<TaskHistory> TaskHistories => Set<TaskHistory>();
    public DbSet<TaskAttachment> TaskAttachments => Set<TaskAttachment>();
    public DbSet<TaskAssignee> TaskAssignees => Set<TaskAssignee>();
    public DbSet<TaskReminder> TaskReminders => Set<TaskReminder>();
    public DbSet<TaskEvaluation> TaskEvaluations => Set<TaskEvaluation>();
    
    // Assets & Inventory
    public DbSet<Asset> Assets => Set<Asset>();
    public DbSet<AssetCategory> AssetCategories => Set<AssetCategory>();
    public DbSet<AssetImage> AssetImages => Set<AssetImage>();
    public DbSet<AssetInventory> AssetInventories => Set<AssetInventory>();
    public DbSet<AssetInventoryItem> AssetInventoryItems => Set<AssetInventoryItem>();
    public DbSet<AssetTransfer> AssetTransfers => Set<AssetTransfer>();
    
    // Organization & HR
    public DbSet<Branch> Branches => Set<Branch>();
    public DbSet<Department> Departments => Set<Department>();
    public DbSet<ApprovalFlow> ApprovalFlows => Set<ApprovalFlow>();
    public DbSet<ApprovalStep> ApprovalSteps => Set<ApprovalStep>();
    public DbSet<ApprovalRecord> ApprovalRecords => Set<ApprovalRecord>();
    public DbSet<OrgPosition> OrgPositions => Set<OrgPosition>();
    public DbSet<OrgAssignment> OrgAssignments => Set<OrgAssignment>();
    public DbSet<Overtime> Overtimes => Set<Overtime>();
    
    // Communications & Content
    public DbSet<InternalCommunication> InternalCommunications => Set<InternalCommunication>();
    public DbSet<CommunicationComment> CommunicationComments => Set<CommunicationComment>();
    public DbSet<CommunicationReaction> CommunicationReactions => Set<CommunicationReaction>();
    public DbSet<ContentCategory> ContentCategories => Set<ContentCategory>();
    
    // KPI Management
    public DbSet<KpiSalary> KpiSalaries => Set<KpiSalary>();
    public DbSet<KpiResult> KpiResults => Set<KpiResult>();
    public DbSet<KpiPeriod> KpiPeriods => Set<KpiPeriod>();
    public DbSet<KpiEmployeeTarget> KpiEmployeeTargets => Set<KpiEmployeeTarget>();
    public DbSet<KpiConfig> KpiConfigs => Set<KpiConfig>();
    public DbSet<KpiBonusRule> KpiBonusRules => Set<KpiBonusRule>();
    
    // Finance
    public DbSet<BankAccount> BankAccounts => Set<BankAccount>();
    public DbSet<TransactionCategory> TransactionCategories => Set<TransactionCategory>();
    public DbSet<CashTransaction> CashTransactions => Set<CashTransaction>();
    
    // Additional
    public DbSet<ShiftSalaryLevel> ShiftSalaryLevels => Set<ShiftSalaryLevel>();
    public DbSet<ShiftSwapRequest> ShiftSwapRequests => Set<ShiftSwapRequest>();
    public DbSet<HrDocument> HrDocuments => Set<HrDocument>();
    public DbSet<Geofence> Geofences => Set<Geofence>();
    public DbSet<EmployeeWorkingInfo> EmployeeWorkingInfos => Set<EmployeeWorkingInfo>();

    // Production / Piece-rate salary
    public DbSet<ProductGroup> ProductGroups => Set<ProductGroup>();
    public DbSet<ProductItem> ProductItems => Set<ProductItem>();
    public DbSet<ProductPriceTier> ProductPriceTiers => Set<ProductPriceTier>();
    public DbSet<ProductionEntry> ProductionEntries => Set<ProductionEntry>();

    // Feedback / Ý kiến
    public DbSet<Feedback> Feedbacks => Set<Feedback>();

    // Mobile Attendance
    public DbSet<MobileAttendanceSetting> MobileAttendanceSettings => Set<MobileAttendanceSetting>();
    public DbSet<MobileWorkLocation> MobileWorkLocations => Set<MobileWorkLocation>();
    public DbSet<MobileFaceRegistration> MobileFaceRegistrations => Set<MobileFaceRegistration>();
    public DbSet<AuthorizedMobileDevice> AuthorizedMobileDevices => Set<AuthorizedMobileDevice>();
    public DbSet<MobileAttendanceRecord> MobileAttendanceRecords => Set<MobileAttendanceRecord>();

    // Field Check-in / Check-in điểm bán
    public DbSet<FieldLocation> FieldLocations => Set<FieldLocation>();
    public DbSet<FieldLocationAssignment> FieldLocationAssignments => Set<FieldLocationAssignment>();
    public DbSet<VisitReport> VisitReports => Set<VisitReport>();
    public DbSet<JourneyTracking> JourneyTrackings => Set<JourneyTracking>();

    // Meal Tracking / Chấm cơm
    public DbSet<MealSession> MealSessions => Set<MealSession>();
    public DbSet<MealSessionShift> MealSessionShifts => Set<MealSessionShift>();
    public DbSet<MealMenu> MealMenus => Set<MealMenu>();
    public DbSet<MealMenuItem> MealMenuItems => Set<MealMenuItem>();
    public DbSet<MealRecord> MealRecords => Set<MealRecord>();
    public DbSet<MealRegistration> MealRegistrations => Set<MealRegistration>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        
        // Apply entity-specific configurations first
        modelBuilder.ApplyConfigurationsFromAssembly(Assembly.GetExecutingAssembly());

        // Apply multi-tenant query filters for all entities with StoreId
        // This replaces any HasQueryFilter set in individual configurations
        foreach (var entityType in modelBuilder.Model.GetEntityTypes())
        {
            ApplyTenantAndSoftDeleteFilter(modelBuilder, entityType.ClrType);
        }

        // Configure all DateTime properties to use timestamp without time zone
        // But only set NOW() as default for non-nullable DateTime properties
        foreach (var entityType in modelBuilder.Model.GetEntityTypes())
        {
            foreach (var property in entityType.GetProperties())
            {
                if (property.ClrType == typeof(DateTime) || property.ClrType == typeof(DateTime?))
                {
                    property.SetColumnType("timestamp without time zone");
                    
                    // Only set NOW() as default for non-nullable DateTime
                    // and if no default value has been configured already
                    if (property.ClrType == typeof(DateTime) && property.GetDefaultValue() == null && property.GetDefaultValueSql() == null)
                    {
                        property.SetDefaultValueSql("NOW()");
                    }
                }
            }
        }
    }

    /// <summary>
    /// Applies combined tenant isolation + soft delete query filters using reflection.
    /// EF Core re-evaluates _tenantId and _isSuperAccess from the current DbContext instance per query.
    /// </summary>
    private void ApplyTenantAndSoftDeleteFilter(ModelBuilder builder, Type clrType)
    {
        // Skip Store entity itself — it's the tenant root
        if (clrType == typeof(Store)) return;

        var storeIdProp = clrType.GetProperty("StoreId");
        var deletedProp = clrType.GetProperty("Deleted");

        bool hasStoreId = storeIdProp != null && 
            (storeIdProp.PropertyType == typeof(Guid?) || storeIdProp.PropertyType == typeof(Guid));
        bool hasSoftDelete = deletedProp != null && deletedProp.PropertyType == typeof(DateTime?);

        if (!hasStoreId && !hasSoftDelete) return;

        var param = Expression.Parameter(clrType, "e");
        Expression? filter = null;

        // Soft delete filter: e.Deleted == null
        if (hasSoftDelete)
        {
            var deletedExpr = Expression.Property(param, deletedProp!);
            var nullExpr = Expression.Constant(null, typeof(DateTime?));
            filter = Expression.Equal(deletedExpr, nullExpr);
        }

        // Tenant filter: _isSuperAccess || e.StoreId == _tenantId
        if (hasStoreId)
        {
            var entityStoreId = Expression.Property(param, storeIdProp!);
            var contextRef = Expression.Constant(this);
            var tenantIdExpr = Expression.Field(contextRef, nameof(_tenantId));
            var superAccessExpr = Expression.Field(contextRef, nameof(_isSuperAccess));

            // Handle non-nullable Guid StoreId by converting to Guid?
            Expression storeIdForComparison = storeIdProp!.PropertyType == typeof(Guid)
                ? Expression.Convert(entityStoreId, typeof(Guid?))
                : entityStoreId;

            var equalsExpr = Expression.Equal(storeIdForComparison, tenantIdExpr);
            var tenantFilter = Expression.OrElse(superAccessExpr, equalsExpr);

            filter = filter != null
                ? Expression.AndAlso(filter, tenantFilter)
                : tenantFilter;
        }

        if (filter != null)
        {
            var lambda = Expression.Lambda(filter, param);
            builder.Entity(clrType).HasQueryFilter(lambda);
        }
    }

}
