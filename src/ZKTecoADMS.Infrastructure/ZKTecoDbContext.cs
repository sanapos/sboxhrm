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
    // Tenant context — EF Core đọc lại hai giá trị này mỗi lần chạy truy vấn (qua bộ lọc chung).
    // Hỏi tenant provider lúc truy vấn, KHÔNG chốt trong constructor: DbContext của request được tạo ngay lúc
    // xác thực JWT (chưa có User) — chốt lúc đó là «thấy mọi cửa hàng» cho cả request, bộ lọc cửa hàng tắt.
    private readonly ITenantProvider? _tenantProvider;
    private Guid? TenantId => _tenantProvider?.StoreId;
    private bool IsSuperAccess => _tenantProvider?.IsSuperAccess ?? true;

    public ZKTecoDbContext(DbContextOptions<ZKTecoDbContext> options, ITenantProvider? tenantProvider = null)
        : base(options)
    {
        _tenantProvider = tenantProvider;
    }
    // Authentication & Identity
    public DbSet<UserRefreshToken> UserRefreshTokens => Set<UserRefreshToken>();
    public DbSet<UserDeviceToken> UserDeviceTokens => Set<UserDeviceToken>();
    
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
    public DbSet<ScheduleApprovalRecord> ScheduleApprovalRecords => Set<ScheduleApprovalRecord>();
    public DbSet<ShiftStaffingQuota> ShiftStaffingQuotas => Set<ShiftStaffingQuota>();
    public DbSet<AttendanceCorrectionRequest> AttendanceCorrectionRequests => Set<AttendanceCorrectionRequest>();
    
    // Leave Management
    public DbSet<Leave> Leaves => Set<Leave>();
    public DbSet<LeaveApprovalRecord> LeaveApprovalRecords => Set<LeaveApprovalRecord>();
    
    // Compensation & Benefits
    public DbSet<Benefit> Benefits => Set<Benefit>();
    public DbSet<EmployeeBenefit> EmployeeBenefits => Set<EmployeeBenefit>();
    public DbSet<SalaryProfileRevision> SalaryProfileRevisions => Set<SalaryProfileRevision>();
    public DbSet<Allowance> Allowances => Set<Allowance>();
    
    // Payroll & Finance
    public DbSet<Payslip> Payslips => Set<Payslip>();
    public DbSet<PayslipAttendanceSnapshot> PayslipAttendanceSnapshots => Set<PayslipAttendanceSnapshot>();
    public DbSet<AdvanceRequest> AdvanceRequests => Set<AdvanceRequest>();
    public DbSet<AdvanceApprovalRecord> AdvanceApprovalRecords => Set<AdvanceApprovalRecord>();
    public DbSet<PaymentTransaction> PaymentTransactions => Set<PaymentTransaction>();
    
    // Business trip expense / Công tác phí
    public DbSet<BusinessTripCase> BusinessTripCases => Set<BusinessTripCase>();
    public DbSet<BusinessTripAdvanceClaim> BusinessTripAdvanceClaims => Set<BusinessTripAdvanceClaim>();
    public DbSet<BusinessTripAdvanceApprovalRecord> BusinessTripAdvanceApprovalRecords => Set<BusinessTripAdvanceApprovalRecord>();
    public DbSet<BusinessTripSettlementClaim> BusinessTripSettlementClaims => Set<BusinessTripSettlementClaim>();
    public DbSet<BusinessTripSettlementApprovalRecord> BusinessTripSettlementApprovalRecords => Set<BusinessTripSettlementApprovalRecord>();
    public DbSet<BusinessTripExpenseCategory> BusinessTripExpenseCategories => Set<BusinessTripExpenseCategory>();
    public DbSet<BusinessTripExpenseLine> BusinessTripExpenseLines => Set<BusinessTripExpenseLine>();
    public DbSet<BusinessTripExpenseAttachment> BusinessTripExpenseAttachments => Set<BusinessTripExpenseAttachment>();
    
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

    // SuperAdmin Announcements / Maintenance / Marketing campaigns
    public DbSet<SystemAnnouncement> SystemAnnouncements => Set<SystemAnnouncement>();
    public DbSet<AnnouncementDelivery> AnnouncementDeliveries => Set<AnnouncementDelivery>();
    public DbSet<MaintenanceWindow> MaintenanceWindows => Set<MaintenanceWindow>();
    public DbSet<NotificationTemplate> NotificationTemplates => Set<NotificationTemplate>();
    public DbSet<MarketingCampaign> MarketingCampaigns => Set<MarketingCampaign>();
    
    // Permissions & Roles
    public DbSet<Permission> Permissions => Set<Permission>();
    public DbSet<RolePermission> RolePermissions => Set<RolePermission>();
    public DbSet<DepartmentPermission> DepartmentPermissions => Set<DepartmentPermission>();
    public DbSet<BranchPermission> BranchPermissions => Set<BranchPermission>();
    
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
    public DbSet<TaskTimeLog> TaskTimeLogs => Set<TaskTimeLog>();
    public DbSet<TaskWorkspaceSetting> TaskWorkspaceSettings => Set<TaskWorkspaceSetting>();
    public DbSet<TaskAssignee> TaskAssignees => Set<TaskAssignee>();
    public DbSet<TaskReminder> TaskReminders => Set<TaskReminder>();
    public DbSet<TaskEvaluation> TaskEvaluations => Set<TaskEvaluation>();
    public DbSet<TaskTemplate> TaskTemplates => Set<TaskTemplate>();
    public DbSet<TaskDependency> TaskDependencies => Set<TaskDependency>();
    public DbSet<TaskProject> TaskProjects => Set<TaskProject>();
    
    // Assets & Inventory
    public DbSet<Asset> Assets => Set<Asset>();
    public DbSet<AssetCategory> AssetCategories => Set<AssetCategory>();
    public DbSet<AssetImage> AssetImages => Set<AssetImage>();
    public DbSet<AssetInventory> AssetInventories => Set<AssetInventory>();
    public DbSet<AssetInventoryItem> AssetInventoryItems => Set<AssetInventoryItem>();
    public DbSet<AssetTransfer> AssetTransfers => Set<AssetTransfer>();
    public DbSet<StockTransaction> StockTransactions => Set<StockTransaction>();
    
    // Organization & HR
    public DbSet<Branch> Branches => Set<Branch>();
    public DbSet<PosBranchStock> PosBranchStocks => Set<PosBranchStock>();
    public DbSet<PosStockTransfer> PosStockTransfers => Set<PosStockTransfer>();
    public DbSet<PosStockTransferLine> PosStockTransferLines => Set<PosStockTransferLine>();
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
    public DbSet<CommChannel> CommChannels => Set<CommChannel>();
    public DbSet<HrFinanceSettings> HrFinanceSettings => Set<HrFinanceSettings>();
    public DbSet<EmployeeCareerRecord> EmployeeCareerRecords => Set<EmployeeCareerRecord>();
    public DbSet<AnnualLeavePolicy> AnnualLeavePolicies => Set<AnnualLeavePolicy>();
    public DbSet<AnnualLeaveEntry> AnnualLeaveEntries => Set<AnnualLeaveEntry>();
    public DbSet<CommunicationRead> CommunicationReads => Set<CommunicationRead>();
    public DbSet<CommunicationPollVote> CommunicationPollVotes => Set<CommunicationPollVote>();
    public DbSet<CommunicationBookmark> CommunicationBookmarks => Set<CommunicationBookmark>();
    public DbSet<CommunicationCommentLike> CommunicationCommentLikes => Set<CommunicationCommentLike>();
    public DbSet<CommunicationReport> CommunicationReports => Set<CommunicationReport>();
    public DbSet<CommunicationUserBlock> CommunicationUserBlocks => Set<CommunicationUserBlock>();
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
    public DbSet<FundTransfer> FundTransfers => Set<FundTransfer>();
    
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
    public DbSet<FeedbackReply> FeedbackReplies => Set<FeedbackReply>();
    public DbSet<ConsultationRequest> ConsultationRequests => Set<ConsultationRequest>();

    // App Pages & Bug Reports
    public DbSet<AppPage> AppPages => Set<AppPage>();
    public DbSet<AppBugReport> AppBugReports => Set<AppBugReport>();

    // Mobile Attendance
    public DbSet<MobileAttendanceSetting> MobileAttendanceSettings => Set<MobileAttendanceSetting>();
    public DbSet<MobileWorkLocation> MobileWorkLocations => Set<MobileWorkLocation>();
    public DbSet<MobileLocationEmployee> MobileLocationEmployees => Set<MobileLocationEmployee>();
    public DbSet<MobileFaceRegistration> MobileFaceRegistrations => Set<MobileFaceRegistration>();
    public DbSet<AuthorizedMobileDevice> AuthorizedMobileDevices => Set<AuthorizedMobileDevice>();
    public DbSet<MobileAttendanceRecord> MobileAttendanceRecords => Set<MobileAttendanceRecord>();
    public DbSet<DeviceChangeRequest> DeviceChangeRequests => Set<DeviceChangeRequest>();

    // Field Check-in / Check-in điểm bán
    public DbSet<FieldLocation> FieldLocations => Set<FieldLocation>();
    public DbSet<FieldLocationAssignment> FieldLocationAssignments => Set<FieldLocationAssignment>();
    public DbSet<VisitReport> VisitReports => Set<VisitReport>();
    public DbSet<JourneyTracking> JourneyTrackings => Set<JourneyTracking>();
    public DbSet<EmployeeLiveLocation> EmployeeLiveLocations => Set<EmployeeLiveLocation>();

    // Meal Tracking / Chấm cơm
    public DbSet<MealSession> MealSessions => Set<MealSession>();
    public DbSet<MealSessionShift> MealSessionShifts => Set<MealSessionShift>();
    public DbSet<MealMenu> MealMenus => Set<MealMenu>();
    public DbSet<MealMenuItem> MealMenuItems => Set<MealMenuItem>();
    public DbSet<MealRecord> MealRecords => Set<MealRecord>();
    public DbSet<EmployeeLocationPoint> EmployeeLocationPoints => Set<EmployeeLocationPoint>();
    public DbSet<UserNotificationSetting> UserNotificationSettings => Set<UserNotificationSetting>();
    public DbSet<StoreNotificationTemplate> StoreNotificationTemplates => Set<StoreNotificationTemplate>();
    public DbSet<MealRegistration> MealRegistrations => Set<MealRegistration>();
    public DbSet<MealDebt> MealDebts => Set<MealDebt>();
    public DbSet<MealDish> MealDishes => Set<MealDish>();

    // POS / Bán hàng
    public DbSet<PosProductCategory> PosProductCategories => Set<PosProductCategory>();
    public DbSet<PosProductBrand> PosProductBrands => Set<PosProductBrand>();
    public DbSet<PosStorageLocation> PosStorageLocations => Set<PosStorageLocation>();
    public DbSet<PosProduct> PosProducts => Set<PosProduct>();
    public DbSet<PosBarcodeCatalog> PosBarcodeCatalog => Set<PosBarcodeCatalog>();
    public DbSet<PosProductSampleCatalog> PosProductSampleCatalog => Set<PosProductSampleCatalog>();
    public DbSet<PosProductSampleCategory> PosProductSampleCategory => Set<PosProductSampleCategory>();
    public DbSet<StoreAccessDevice> StoreAccessDevices => Set<StoreAccessDevice>();
    public DbSet<ServerMetricSample> ServerMetricSamples => Set<ServerMetricSample>();
    public DbSet<PosProductToppingOption> PosProductToppingOptions => Set<PosProductToppingOption>();
    public DbSet<PosToppingGroup> PosToppingGroups => Set<PosToppingGroup>();
    public DbSet<PosToppingGroupItem> PosToppingGroupItems => Set<PosToppingGroupItem>();
    public DbSet<PosProductToppingGroupLink> PosProductToppingGroupLinks => Set<PosProductToppingGroupLink>();
    public DbSet<PosQuickSellNote> PosQuickSellNotes => Set<PosQuickSellNote>();
    public DbSet<PosQuickSellNoteItem> PosQuickSellNoteItems => Set<PosQuickSellNoteItem>();
    public DbSet<PosProductUnit> PosProductUnits => Set<PosProductUnit>();
    public DbSet<PosSupplier> PosSuppliers => Set<PosSupplier>();
    public DbSet<PosCustomer> PosCustomers => Set<PosCustomer>();
    public DbSet<PosDebtLedgerEntry> PosDebtLedgerEntries => Set<PosDebtLedgerEntry>();
    public DbSet<PosProductAttribute> PosProductAttributes => Set<PosProductAttribute>();
    public DbSet<PosProductAttributeValue> PosProductAttributeValues => Set<PosProductAttributeValue>();
    public DbSet<PosStockTransaction> PosStockTransactions => Set<PosStockTransaction>();
    public DbSet<PosSaleOrder> PosSaleOrders => Set<PosSaleOrder>();
    public DbSet<PosSaleOrderLine> PosSaleOrderLines => Set<PosSaleOrderLine>();
    public DbSet<PosQuote> PosQuotes => Set<PosQuote>();
    public DbSet<PosQuoteLine> PosQuoteLines => Set<PosQuoteLine>();
    public DbSet<PosQuoteDocument> PosQuoteDocuments => Set<PosQuoteDocument>();
    public DbSet<PosQuoteDocumentRevision> PosQuoteDocumentRevisions => Set<PosQuoteDocumentRevision>();
    public DbSet<PosCustomerDocTemplate> PosCustomerDocTemplates => Set<PosCustomerDocTemplate>();
    public DbSet<PosQuoteActivity> PosQuoteActivities => Set<PosQuoteActivity>();
    public DbSet<PosSaleCommissionLine> PosSaleCommissionLines => Set<PosSaleCommissionLine>();
    public DbSet<PosEInvoiceSetting> PosEInvoiceSettings => Set<PosEInvoiceSetting>();
    public DbSet<PosProductComboLine> PosProductComboLines => Set<PosProductComboLine>();
    public DbSet<PosProductRecipeLine> PosProductRecipeLines => Set<PosProductRecipeLine>();
    public DbSet<PosProductVariant> PosProductVariants => Set<PosProductVariant>();
    public DbSet<PosStockReceipt> PosStockReceipts => Set<PosStockReceipt>();
    public DbSet<PosStockReceiptLine> PosStockReceiptLines => Set<PosStockReceiptLine>();
    public DbSet<PosStockLot> PosStockLots => Set<PosStockLot>();
    public DbSet<PosStockIssue> PosStockIssues => Set<PosStockIssue>();
    public DbSet<PosStockIssueLine> PosStockIssueLines => Set<PosStockIssueLine>();
    public DbSet<PosStockCount> PosStockCounts => Set<PosStockCount>();
    public DbSet<PosStockCountLine> PosStockCountLines => Set<PosStockCountLine>();
    public DbSet<PosSupplierGroup> PosSupplierGroups => Set<PosSupplierGroup>();
    public DbSet<PosPurchaseReturn> PosPurchaseReturns => Set<PosPurchaseReturn>();
    public DbSet<PosPurchaseReturnLine> PosPurchaseReturnLines => Set<PosPurchaseReturnLine>();
    public DbSet<PosSupplierPayment> PosSupplierPayments => Set<PosSupplierPayment>();
    public DbSet<PosPrintTemplate> PosPrintTemplates => Set<PosPrintTemplate>();
    public DbSet<PosPrintTemplateCatalog> PosPrintTemplateCatalogs => Set<PosPrintTemplateCatalog>();
    public DbSet<PosStorePrinter> PosStorePrinters => Set<PosStorePrinter>();
    public DbSet<PosPrinterDocumentRoute> PosPrinterDocumentRoutes => Set<PosPrinterDocumentRoute>();
    public DbSet<PosPrintAgent> PosPrintAgents => Set<PosPrintAgent>();
    public DbSet<PosNetworkSample> PosNetworkSamples => Set<PosNetworkSample>();
    public DbSet<PosDeviceInstall> PosDeviceInstalls => Set<PosDeviceInstall>();
    public DbSet<PosOfflineSerialBlock> PosOfflineSerialBlocks => Set<PosOfflineSerialBlock>();
    public DbSet<PosPrintJob> PosPrintJobs => Set<PosPrintJob>();
    public DbSet<PosPriceList> PosPriceLists => Set<PosPriceList>();
    public DbSet<PosPriceListItem> PosPriceListItems => Set<PosPriceListItem>();
    public DbSet<PosProductWarrantyRegistration> PosProductWarrantyRegistrations => Set<PosProductWarrantyRegistration>();
    public DbSet<PosWarrantyClaim> PosWarrantyClaims => Set<PosWarrantyClaim>();
    public DbSet<PosProductSerial> PosProductSerials => Set<PosProductSerial>();
    public DbSet<PosQrRequestLog> PosQrRequestLogs => Set<PosQrRequestLog>();
    public DbSet<StoreScheduledNotification> StoreScheduledNotifications => Set<StoreScheduledNotification>();
    public DbSet<PosSerialCount> PosSerialCounts => Set<PosSerialCount>();
    public DbSet<PosSerialCountItem> PosSerialCountItems => Set<PosSerialCountItem>();
    public DbSet<PosCustomerPayment> PosCustomerPayments => Set<PosCustomerPayment>();
    public DbSet<PosCustomerPointTransaction> PosCustomerPointTransactions => Set<PosCustomerPointTransaction>();
    public DbSet<PosVoucher> PosVouchers => Set<PosVoucher>();
    public DbSet<PosPromotion> PosPromotions => Set<PosPromotion>();
    public DbSet<PosQrMenuItem> PosQrMenuItems => Set<PosQrMenuItem>();
    public DbSet<PosStoreSellSettings> PosStoreSellSettings => Set<PosStoreSellSettings>();
    public DbSet<PosStoreCommercialProfile> PosStoreCommercialProfiles => Set<PosStoreCommercialProfile>();
    public DbSet<PosCashierShift> PosCashierShifts => Set<PosCashierShift>();
    public DbSet<PosServiceArea> PosServiceAreas => Set<PosServiceArea>();
    public DbSet<PosServiceResource> PosServiceResources => Set<PosServiceResource>();
    public DbSet<PosServiceAreaAssignment> PosServiceAreaAssignments => Set<PosServiceAreaAssignment>();
    public DbSet<PosResourceSession> PosResourceSessions => Set<PosResourceSession>();
    public DbSet<PosStayGuest> PosStayGuests => Set<PosStayGuest>();
    public DbSet<PosGymMemberDevice> PosGymMemberDevices => Set<PosGymMemberDevice>();
    public DbSet<PosGymVisit> PosGymVisits => Set<PosGymVisit>();
    public DbSet<PosGymAssessment> PosGymAssessments => Set<PosGymAssessment>();
    public DbSet<PosGymWorkoutPlan> PosGymWorkoutPlans => Set<PosGymWorkoutPlan>();
    public DbSet<PosGymPtSession> PosGymPtSessions => Set<PosGymPtSession>();
    public DbSet<PosResourceReservation> PosResourceReservations => Set<PosResourceReservation>();
    public DbSet<PosKitchenVoidSlip> PosKitchenVoidSlips => Set<PosKitchenVoidSlip>();
    public DbSet<PosCancelReturnAudit> PosCancelReturnAudits => Set<PosCancelReturnAudit>();
    public DbSet<PosSaleReturnLine> PosSaleReturnLines => Set<PosSaleReturnLine>();
    public DbSet<PosCustomerSessionBalance> PosCustomerSessionBalances => Set<PosCustomerSessionBalance>();
    public DbSet<PosCustomerSessionTransaction> PosCustomerSessionTransactions => Set<PosCustomerSessionTransaction>();
    public DbSet<PosPaymentGatewaySetting> PosPaymentGatewaySettings => Set<PosPaymentGatewaySetting>();
    public DbSet<PosShippingCarrierSetting> PosShippingCarrierSettings => Set<PosShippingCarrierSetting>();
    public DbSet<PosShipmentEvent> PosShipmentEvents => Set<PosShipmentEvent>();
    public DbSet<PosStoreNotificationCredit> PosStoreNotificationCredits => Set<PosStoreNotificationCredit>();
    public DbSet<PosNotificationCreditPackage> PosNotificationCreditPackages => Set<PosNotificationCreditPackage>();
    public DbSet<PosNotificationCreditPurchase> PosNotificationCreditPurchases => Set<PosNotificationCreditPurchase>();
    public DbSet<PosNotificationCreditLedger> PosNotificationCreditLedgers => Set<PosNotificationCreditLedger>();
    public DbSet<PosTransferPaymentIntent> PosTransferPaymentIntents => Set<PosTransferPaymentIntent>();
    public DbSet<PosPaymentWebhookEvent> PosPaymentWebhookEvents => Set<PosPaymentWebhookEvent>();
    public DbSet<PosPlatformNotificationCredit> PosPlatformNotificationCredits => Set<PosPlatformNotificationCredit>();
    public DbSet<PosPlatformNotificationCreditLedger> PosPlatformNotificationCreditLedgers => Set<PosPlatformNotificationCreditLedger>();
    public DbSet<PosPlatformTingeeSetting> PosPlatformTingeeSettings => Set<PosPlatformTingeeSetting>();
    public DbSet<AiActionLog> AiActionLogs => Set<AiActionLog>();
    public DbSet<AiStoreProfile> AiStoreProfiles => Set<AiStoreProfile>();
    public DbSet<AiMorningBriefSetting> AiMorningBriefSettings => Set<AiMorningBriefSetting>();
    public DbSet<AiMorningBriefLog> AiMorningBriefLogs => Set<AiMorningBriefLog>();
    public DbSet<GeminiUsageLog> GeminiUsageLogs => Set<GeminiUsageLog>();
    public DbSet<ZaloBotSetting> ZaloBotSettings => Set<ZaloBotSetting>();
    public DbSet<ZaloBotLink> ZaloBotLinks => Set<ZaloBotLink>();
    public DbSet<ZaloBotMessage> ZaloBotMessages => Set<ZaloBotMessage>();
    public DbSet<PosAiInvoiceMapping> PosAiInvoiceMappings => Set<PosAiInvoiceMapping>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        VnSearchEf.Register(modelBuilder);
        
        // Apply entity-specific configurations first
        modelBuilder.ApplyConfigurationsFromAssembly(Assembly.GetExecutingAssembly());

        // SitePhotoUrl: cột có trong DB (initializer) nhưng từng thiếu trong snapshot — map tường minh.
        modelBuilder.Entity<MobileAttendanceRecord>(b =>
        {
            b.Property(x => x.SitePhotoUrl).HasMaxLength(500);
        });

        // Mật khẩu plain text để Super Admin tra cứu (cột add_plain_text_password.sql).
        modelBuilder.Entity<ApplicationUser>(b =>
        {
            b.Property(u => u.PlainTextPassword).HasColumnType("text");
        });

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
    /// EF Core re-evaluates TenantId and IsSuperAccess from the current DbContext instance per query.
    /// Dòng chưa gắn cửa hàng (StoreId null: dữ liệu dùng chung, thiết bị chưa nhận…) vẫn hiện với mọi cửa hàng
    /// như trước nay; bộ lọc chỉ chặn dòng của CỬA HÀNG KHÁC.
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

        // Tenant filter: IsSuperAccess || e.StoreId == TenantId || e.StoreId == null
        if (hasStoreId)
        {
            const BindingFlags own = BindingFlags.Instance | BindingFlags.NonPublic;
            var entityStoreId = Expression.Property(param, storeIdProp!);
            var contextRef = Expression.Constant(this);
            var tenantIdExpr = Expression.Property(contextRef, typeof(ZKTecoDbContext).GetProperty(nameof(TenantId), own)!);
            var superAccessExpr = Expression.Property(contextRef, typeof(ZKTecoDbContext).GetProperty(nameof(IsSuperAccess), own)!);

            // Handle non-nullable Guid StoreId by converting to Guid?
            var nullableStoreId = storeIdProp!.PropertyType == typeof(Guid?);
            Expression storeIdForComparison = nullableStoreId
                ? entityStoreId
                : Expression.Convert(entityStoreId, typeof(Guid?));

            Expression equalsExpr = Expression.Equal(storeIdForComparison, tenantIdExpr);
            if (nullableStoreId)
                equalsExpr = Expression.OrElse(equalsExpr,
                    Expression.Equal(entityStoreId, Expression.Constant(null, typeof(Guid?))));
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
