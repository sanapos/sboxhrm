using System.Globalization;
using System.Text.RegularExpressions;

namespace ZKTecoADMS.Api.Controllers.Filters;

/// <summary>
/// Việt hóa Lịch sử thao tác lúc đọc (áp dụng cả nhật ký cũ): tên loại dữ liệu, tên trường, vai trò, giá trị trạng thái.
/// Không có trong từ điển → dịch từng từ theo thứ tự tiếng Việt (danh từ chính đứng trước).
/// </summary>
public static partial class ActivityLabels
{
    // ─── Loại dữ liệu ─────────────────────────────────────────────────────
    static readonly Dictionary<string, string> Entities = new(StringComparer.Ordinal)
    {
        ["AdvanceApprovalRecord"] = "Duyệt tạm ứng", ["AdvanceRequest"] = "Tạm ứng", ["Agent"] = "Đại lý",
        ["Allowance"] = "Phụ cấp", ["AnnouncementDelivery"] = "Gửi thông báo", ["AppBugReport"] = "Báo lỗi ứng dụng",
        ["AppPage"] = "Trang nội dung", ["AppSettings"] = "Cài đặt", ["ApplicationUser"] = "Tài khoản",
        ["ApprovalFlow"] = "Quy trình duyệt", ["ApprovalRecord"] = "Lượt duyệt", ["ApprovalStep"] = "Bước duyệt",
        ["Asset"] = "Tài sản", ["AssetCategory"] = "Nhóm tài sản", ["AssetImage"] = "Ảnh tài sản",
        ["AssetInventory"] = "Kiểm kê tài sản", ["AssetInventoryItem"] = "Dòng kiểm kê tài sản", ["AssetTransfer"] = "Điều chuyển tài sản",
        ["Attendance"] = "Chấm công", ["AttendanceCorrectionRequest"] = "Yêu cầu sửa công",
        ["AuthorizedMobileDevice"] = "Thiết bị chấm công di động", ["BankAccount"] = "Tài khoản ngân hàng",
        ["Benefit"] = "Chế độ phúc lợi", ["Branch"] = "Chi nhánh", ["BranchPermission"] = "Phân quyền chi nhánh",
        ["BusinessTripAdvanceApprovalRecord"] = "Duyệt ứng công tác phí", ["BusinessTripAdvanceClaim"] = "Đề nghị ứng công tác phí",
        ["BusinessTripCase"] = "Chuyến công tác", ["BusinessTripExpenseAttachment"] = "Chứng từ công tác phí",
        ["BusinessTripExpenseCategory"] = "Loại công tác phí", ["BusinessTripExpenseLine"] = "Dòng công tác phí",
        ["BusinessTripSettlementApprovalRecord"] = "Duyệt quyết toán công tác", ["BusinessTripSettlementClaim"] = "Quyết toán công tác phí",
        ["CashTransaction"] = "Phiếu thu / chi", ["CommChannel"] = "Kênh truyền thông", ["CommunicationBookmark"] = "Lưu bài viết",
        ["CommunicationComment"] = "Bình luận", ["CommunicationPollVote"] = "Bình chọn", ["CommunicationReaction"] = "Cảm xúc bài viết",
        ["CommunicationRead"] = "Lượt xem bài viết", ["ConsultationRequest"] = "Yêu cầu tư vấn", ["ContentCategory"] = "Chuyên mục",
        ["Department"] = "Phòng ban", ["DepartmentPermission"] = "Phân quyền phòng ban", ["Device"] = "Máy chấm công",
        ["DeviceChangeRequest"] = "Yêu cầu đổi thiết bị", ["DeviceSetting"] = "Cài đặt máy chấm công",
        ["DeviceUser"] = "Người dùng máy chấm công", ["Employee"] = "Nhân viên", ["EmployeeBenefit"] = "Phúc lợi nhân viên",
        ["EmployeeLiveLocation"] = "Vị trí nhân viên", ["EmployeeLocationPoint"] = "Điểm vị trí nhân viên",
        ["EmployeeTaxDeduction"] = "Giảm trừ thuế", ["EmployeeWorkingInfo"] = "Thông tin công việc",
        ["FaceTemplate"] = "Mẫu khuôn mặt", ["Feedback"] = "Kiến nghị", ["FeedbackReply"] = "Phản hồi kiến nghị",
        ["FieldLocation"] = "Điểm công tác", ["FieldLocationAssignment"] = "Giao điểm công tác",
        ["FingerprintTemplate"] = "Mẫu vân tay", ["FundTransfer"] = "Chuyển quỹ", ["Geofence"] = "Vùng chấm công",
        ["Holiday"] = "Ngày lễ", ["HrDocument"] = "Tài liệu nhân sự", ["HrFinanceSettings"] = "Thiết lập tài chính nhân sự",
        ["InsuranceSetting"] = "Thiết lập bảo hiểm", ["InternalCommunication"] = "Bài truyền thông nội bộ",
        ["JourneyTracking"] = "Hành trình", ["KeyActivationPromotion"] = "Khuyến mãi kích hoạt", ["KpiBonusRule"] = "Quy tắc thưởng KPI",
        ["KpiConfig"] = "Cấu hình KPI", ["KpiEmployeeTarget"] = "Chỉ tiêu KPI", ["KpiPeriod"] = "Kỳ KPI", ["KpiResult"] = "Kết quả KPI",
        ["KpiSalary"] = "Lương KPI", ["Leave"] = "Đơn nghỉ phép", ["LeaveApprovalRecord"] = "Duyệt nghỉ phép",
        ["LicenseKey"] = "Mã kích hoạt", ["MaintenanceWindow"] = "Lịch bảo trì", ["MarketingCampaign"] = "Chiến dịch marketing",
        ["MealDebt"] = "Công nợ tiền ăn", ["MealDish"] = "Món ăn", ["MealMenu"] = "Thực đơn", ["MealMenuItem"] = "Món trong thực đơn",
        ["MealRecord"] = "Suất ăn", ["MealRegistration"] = "Đăng ký suất ăn", ["MealSession"] = "Bữa ăn", ["MealSessionShift"] = "Ca của bữa ăn",
        ["MobileAttendanceRecord"] = "Chấm công di động", ["MobileAttendanceSetting"] = "Thiết lập chấm công di động",
        ["MobileFaceRegistration"] = "Đăng ký khuôn mặt", ["MobileLocationEmployee"] = "Nhân viên theo điểm chấm",
        ["MobileWorkLocation"] = "Điểm chấm công", ["Notification"] = "Thông báo", ["NotificationCategory"] = "Nhóm thông báo",
        ["NotificationPreference"] = "Tùy chọn thông báo", ["NotificationTemplate"] = "Mẫu thông báo",
        ["OrgAssignment"] = "Bổ nhiệm", ["OrgPosition"] = "Chức danh", ["Overtime"] = "Tăng ca",
        ["PaymentTransaction"] = "Giao dịch thanh toán", ["Payslip"] = "Phiếu lương", ["PayslipAttendanceSnapshot"] = "Bảng công của phiếu lương",
        ["PenaltySetting"] = "Thiết lập phạt", ["PenaltyTicket"] = "Phiếu phạt", ["Permission"] = "Quyền",
        ["PosBarcodeCatalog"] = "Danh mục mã vạch", ["PosBranchStock"] = "Tồn kho chi nhánh", ["PosCancelReturnAudit"] = "Nhật ký hủy / trả",
        ["PosCashierShift"] = "Ca thu ngân", ["PosCustomer"] = "Khách hàng", ["PosCustomerPayment"] = "Khách trả nợ",
        ["PosCustomerPointTransaction"] = "Điểm tích lũy", ["PosCustomerSessionBalance"] = "Gói buổi / thẻ tập",
        ["PosCustomerSessionTransaction"] = "Lượt dùng gói buổi", ["PosEInvoiceSetting"] = "Thiết lập hóa đơn điện tử",
        ["PosGymMemberDevice"] = "Thiết bị hội viên", ["PosGymVisit"] = "Lượt tập", ["PosKitchenVoidSlip"] = "Phiếu hủy món",
        ["PosNotificationCreditLedger"] = "Sổ tin nhắn", ["PosNotificationCreditPackage"] = "Gói tin nhắn",
        ["PosNotificationCreditPurchase"] = "Mua gói tin nhắn", ["PosPaymentGatewaySetting"] = "Thiết lập cổng thanh toán",
        ["PosPaymentWebhookEvent"] = "Sự kiện thanh toán", ["PosPriceList"] = "Bảng giá", ["PosPriceListItem"] = "Dòng bảng giá",
        ["PosPrintAgent"] = "Máy in trung gian", ["PosPrintTemplate"] = "Mẫu in", ["PosPrintTemplateCatalog"] = "Kho mẫu in",
        ["PosPrinterDocumentRoute"] = "Định tuyến máy in", ["PosProduct"] = "Hàng hóa", ["PosProductAttribute"] = "Thuộc tính hàng",
        ["PosProductAttributeValue"] = "Giá trị thuộc tính", ["PosProductBrand"] = "Thương hiệu", ["PosProductCategory"] = "Nhóm hàng",
        ["PosProductComboLine"] = "Thành phần combo", ["PosProductRecipeLine"] = "Định lượng nguyên liệu",
        ["PosProductSampleCatalog"] = "Hàng mẫu", ["PosProductSampleCategory"] = "Nhóm hàng mẫu",
        ["PosProductToppingGroupLink"] = "Gắn nhóm topping", ["PosProductToppingOption"] = "Tùy chọn topping",
        ["PosProductUnit"] = "Đơn vị tính", ["PosProductVariant"] = "Biến thể hàng hóa",
        ["PosProductWarrantyRegistration"] = "Đăng ký bảo hành", ["PosPurchaseReturn"] = "Phiếu trả hàng nhập",
        ["PosPurchaseReturnLine"] = "Dòng trả hàng nhập", ["PosQrMenuItem"] = "Món menu QR", ["PosQuote"] = "Báo giá",
        ["PosQuoteActivity"] = "Hoạt động báo giá", ["PosQuoteDocument"] = "Hợp đồng / biên bản", ["PosQuoteLine"] = "Dòng báo giá",
        ["PosResourceReservation"] = "Đặt bàn / phòng", ["PosResourceSession"] = "Phiên bàn / phòng",
        ["PosSaleCommissionLine"] = "Hoa hồng bán hàng", ["PosSaleOrder"] = "Hóa đơn / đơn hàng", ["PosSaleOrderLine"] = "Dòng hàng trên hóa đơn",
        ["PosServiceArea"] = "Khu vực", ["PosServiceAreaAssignment"] = "Phân khu vực", ["PosServiceResource"] = "Bàn / phòng",
        ["PosShipmentEvent"] = "Trạng thái vận chuyển", ["PosShippingCarrierSetting"] = "Thiết lập hãng vận chuyển",
        ["PosStayGuest"] = "Khách lưu trú", ["PosStockCount"] = "Phiếu kiểm kho", ["PosStockCountLine"] = "Dòng kiểm kho",
        ["PosStockIssue"] = "Phiếu xuất kho", ["PosStockIssueLine"] = "Dòng xuất kho", ["PosStockLot"] = "Lô hàng",
        ["PosStockReceipt"] = "Phiếu nhập hàng", ["PosStockReceiptLine"] = "Dòng nhập hàng", ["PosStockTransaction"] = "Biến động kho",
        ["PosStockTransfer"] = "Phiếu chuyển kho", ["PosStockTransferLine"] = "Dòng chuyển kho", ["PosStorageLocation"] = "Vị trí kho",
        ["PosStoreCommercialProfile"] = "Hồ sơ thương mại", ["PosStoreNotificationCredit"] = "Tin nhắn cửa hàng",
        ["PosStorePrinter"] = "Máy in", ["PosStoreSellSettings"] = "Thiết lập bán hàng", ["PosSupplier"] = "Nhà cung cấp",
        ["PosSupplierGroup"] = "Nhóm nhà cung cấp", ["PosSupplierPayment"] = "Trả nợ nhà cung cấp", ["PosToppingGroup"] = "Nhóm topping",
        ["PosToppingGroupItem"] = "Topping", ["PosTransferPaymentIntent"] = "Yêu cầu chuyển khoản", ["PosVoucher"] = "Khuyến mãi",
        ["ProductGroup"] = "Nhóm sản phẩm", ["ProductItem"] = "Sản phẩm", ["ProductPriceTier"] = "Bậc giá", ["ProductionEntry"] = "Sản lượng",
        ["RolePermission"] = "Phân quyền vai trò", ["ScheduleApprovalRecord"] = "Duyệt lịch làm việc",
        ["ScheduleRegistration"] = "Đăng ký lịch làm việc", ["ServicePackage"] = "Gói dịch vụ", ["Shift"] = "Ca làm việc",
        ["ShiftSalaryLevel"] = "Mức lương theo ca", ["ShiftStaffingQuota"] = "Định biên ca", ["ShiftSwapRequest"] = "Đổi ca",
        ["StockTransaction"] = "Biến động kho", ["Store"] = "Cửa hàng", ["StoreAccessDevice"] = "Thiết bị đăng nhập",
        ["StoreNotificationTemplate"] = "Mẫu thông báo cửa hàng", ["SystemAnnouncement"] = "Thông báo hệ thống",
        ["SystemConfiguration"] = "Cấu hình hệ thống", ["TaskAssignee"] = "Người thực hiện", ["TaskAttachment"] = "Tệp công việc",
        ["TaskComment"] = "Bình luận công việc", ["TaskDependency"] = "Liên kết công việc", ["TaskEvaluation"] = "Đánh giá công việc",
        ["TaskHistory"] = "Lịch sử công việc", ["TaskProject"] = "Dự án", ["TaskReminder"] = "Nhắc việc", ["TaskTemplate"] = "Mẫu công việc",
        ["TaxSetting"] = "Thiết lập thuế", ["TransactionCategory"] = "Danh mục thu chi", ["UserNotificationSetting"] = "Cài đặt thông báo",
        ["VisitReport"] = "Báo cáo viếng thăm", ["WorkSchedule"] = "Lịch làm việc", ["WorkTask"] = "Công việc",
        ["IdentityUserRole`1"] = "Vai trò tài khoản", ["IdentityRole`1"] = "Vai trò", ["Role"] = "Vai trò",
        ["IdentityUserClaim`1"] = "Quyền tài khoản", ["IdentityRoleClaim`1"] = "Quyền vai trò",
        // Tên cũ / bí danh còn trong nhật ký
        ["PosSalePayment"] = "Thanh toán", ["PosPayment"] = "Thanh toán", ["PosSaleReturn"] = "Phiếu trả hàng",
        ["PosCategory"] = "Nhóm hàng", ["PosPurchaseReceipt"] = "Phiếu nhập hàng", ["PosInventoryTransaction"] = "Biến động kho",
        ["PosStockMovement"] = "Biến động kho", ["PosPromotion"] = "Khuyến mãi", ["ShiftTemplate"] = "Ca làm việc",
        ["Payroll"] = "Bảng lương", ["SalaryRecord"] = "Bảng lương", ["BonusPenalty"] = "Thưởng / phạt", ["TaskItem"] = "Công việc",
        ["MobileAttendance"] = "Chấm công di động",
    };

    public static string Entity(string? type)
    {
        if (string.IsNullOrWhiteSpace(type)) return "Khác";
        if (Entities.TryGetValue(type, out var v)) return v;
        if (!IsTechnical(type)) return type; // đã là tiếng Việt (nhật ký cũ)
        return Capitalize(Words(type.Replace("`1", "")));
    }

    // ─── Tên trường ───────────────────────────────────────────────────────
    static readonly Dictionary<string, string> Fields = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Name"] = "Tên", ["FullName"] = "Họ tên", ["FirstName"] = "Tên", ["LastName"] = "Họ", ["Code"] = "Mã",
        ["Barcode"] = "Mã vạch", ["Sku"] = "Mã SKU", ["Price"] = "Giá", ["BasePrice"] = "Giá bán", ["SalePrice"] = "Giá bán",
        ["CostPrice"] = "Giá vốn", ["UnitPrice"] = "Đơn giá", ["Qty"] = "Số lượng", ["Quantity"] = "Số lượng",
        ["OnHandQty"] = "Tồn kho", ["OnHand"] = "Tồn kho", ["StockQuantity"] = "Tồn kho", ["MinStockQty"] = "Tồn tối thiểu",
        ["Total"] = "Tổng tiền", ["SubTotal"] = "Tiền hàng", ["Discount"] = "Giảm giá", ["DiscountAmount"] = "Giảm giá",
        ["DiscountPercent"] = "Giảm giá (%)", ["PaidAmount"] = "Đã trả", ["Amount"] = "Số tiền", ["BalanceDue"] = "Còn nợ",
        ["VatAmount"] = "Tiền VAT", ["VatPercent"] = "Thuế suất VAT", ["VatRate"] = "Thuế suất VAT", ["LineTotal"] = "Thành tiền",
        ["Status"] = "Trạng thái", ["Note"] = "Ghi chú", ["Notes"] = "Ghi chú", ["InternalNote"] = "Ghi chú nội bộ",
        ["LineNote"] = "Ghi chú dòng", ["Reason"] = "Lý do", ["RejectReason"] = "Lý do từ chối", ["Phone"] = "Điện thoại",
        ["PhoneNumber"] = "Điện thoại", ["Email"] = "Email", ["Address"] = "Địa chỉ", ["CustomerId"] = "Khách hàng",
        ["CustomerName"] = "Tên khách", ["ProductId"] = "Hàng hóa", ["ProductName"] = "Tên hàng", ["VariantId"] = "Biến thể",
        ["CategoryId"] = "Nhóm hàng", ["UnitName"] = "Đơn vị tính", ["BaseUnitName"] = "Đơn vị tính", ["IsActive"] = "Đang dùng",
        ["IsDefault"] = "Mặc định", ["IsEnabled"] = "Bật", ["Enabled"] = "Bật", ["PaymentMethod"] = "Hình thức thanh toán",
        ["SaleDate"] = "Ngày bán", ["OrderNo"] = "Số hóa đơn", ["QuoteNo"] = "Số báo giá", ["EmployeeId"] = "Nhân viên",
        ["EmployeeCode"] = "Mã nhân viên", ["EmployeeName"] = "Tên nhân viên", ["DepartmentId"] = "Phòng ban",
        ["BranchId"] = "Chi nhánh", ["ShiftId"] = "Ca làm việc", ["StoreId"] = "Cửa hàng", ["UserId"] = "Tài khoản",
        ["RoleId"] = "Vai trò", ["Salary"] = "Lương", ["BaseSalary"] = "Lương cơ bản", ["GrossSalary"] = "Lương gộp",
        ["NetSalary"] = "Lương thực nhận", ["StartDate"] = "Từ ngày", ["EndDate"] = "Đến ngày", ["FromDate"] = "Từ ngày",
        ["ToDate"] = "Đến ngày", ["Date"] = "Ngày", ["WorkDate"] = "Ngày làm việc", ["StartTime"] = "Giờ bắt đầu",
        ["EndTime"] = "Giờ kết thúc", ["AttendanceTime"] = "Giờ chấm", ["CheckInTime"] = "Giờ vào", ["CheckOutTime"] = "Giờ ra",
        ["PunchTime"] = "Giờ chấm", ["Role"] = "Vai trò", ["Value"] = "Giá trị", ["Key"] = "Mã cài đặt", ["Title"] = "Tiêu đề",
        ["Description"] = "Mô tả", ["Content"] = "Nội dung", ["Password"] = "Mật khẩu", ["PlainTextPassword"] = "Mật khẩu",
        ["PasswordHash"] = "Mật khẩu", ["Latitude"] = "Vĩ độ", ["Longitude"] = "Kinh độ", ["Radius"] = "Bán kính",
        ["RadiusMeters"] = "Bán kính (m)", ["Accuracy"] = "Độ chính xác", ["Distance"] = "Khoảng cách", ["DistanceMeters"] = "Khoảng cách (m)",
        ["DeviceId"] = "Thiết bị", ["DeviceName"] = "Tên thiết bị", ["DeviceModel"] = "Dòng máy", ["Platform"] = "Hệ điều hành",
        ["ApprovedBy"] = "Người duyệt", ["ApprovedAt"] = "Lúc duyệt", ["ApprovedByName"] = "Người duyệt", ["ApproverId"] = "Người duyệt",
        ["ApproverName"] = "Người duyệt", ["RejectedBy"] = "Người từ chối", ["RejectedAt"] = "Lúc từ chối",
        ["RequestedAt"] = "Lúc gửi", ["SubmittedAt"] = "Lúc gửi", ["IsApproved"] = "Đã duyệt", ["IsLocked"] = "Đã khóa",
        ["Type"] = "Loại", ["Kind"] = "Loại", ["Category"] = "Nhóm", ["SortOrder"] = "Thứ tự", ["Priority"] = "Ưu tiên",
        ["Module"] = "Chức năng", ["CanView"] = "Được xem", ["CanCreate"] = "Được thêm", ["CanEdit"] = "Được sửa",
        ["CanDelete"] = "Được xóa", ["CanApprove"] = "Được duyệt", ["CanExport"] = "Được xuất", ["IncludeChildren"] = "Gồm cấp dưới",
        ["PhotoUrl"] = "Ảnh", ["ImageUrl"] = "Ảnh", ["AvatarUrl"] = "Ảnh đại diện", ["FaceImageUrl"] = "Ảnh khuôn mặt",
        ["IsHeadquarter"] = "Trụ sở", ["ManagerId"] = "Người quản lý", ["ParentId"] = "Cấp trên", ["ParentBranchId"] = "Chi nhánh cha",
        ["Position"] = "Chức vụ", ["JobTitle"] = "Chức danh", ["Gender"] = "Giới tính", ["DateOfBirth"] = "Ngày sinh",
        ["IdCardNumber"] = "Số CCCD", ["TaxCode"] = "Mã số thuế", ["BankAccountNumber"] = "Số tài khoản", ["BankName"] = "Ngân hàng",
        ["HireDate"] = "Ngày vào làm", ["JoinDate"] = "Ngày vào làm", ["ResignDate"] = "Ngày nghỉ việc", ["WorkStatus"] = "Tình trạng làm việc",
        ["Pin"] = "Mã chấm công", ["CardNumber"] = "Số thẻ", ["Privilege"] = "Quyền trên máy", ["SerialNumber"] = "Số serial",
        ["IpAddress"] = "Địa chỉ IP", ["Port"] = "Cổng", ["Month"] = "Tháng", ["Year"] = "Năm", ["Days"] = "Số ngày",
        ["Hours"] = "Số giờ", ["Minutes"] = "Số phút", ["TotalDays"] = "Tổng số ngày", ["TotalHours"] = "Tổng số giờ",
        ["LeaveType"] = "Loại nghỉ", ["IsHalfDay"] = "Nửa ngày", ["ValidFrom"] = "Hiệu lực từ", ["ValidTo"] = "Hiệu lực đến",
        ["ExpiryDate"] = "Ngày hết hạn", ["ExpiresAt"] = "Hết hạn", ["DueDate"] = "Hạn", ["DueAt"] = "Hạn",
        ["CompletedAt"] = "Lúc hoàn tất", ["CancelledAt"] = "Lúc hủy", ["CancelReason"] = "Lý do hủy", ["IsPaid"] = "Đã trả",
        ["TransactionDate"] = "Ngày giao dịch", ["Deleted"] = "Đã xóa", ["DeletedBy"] = "Người xóa", ["Color"] = "Màu",
        ["Icon"] = "Biểu tượng", ["Url"] = "Đường dẫn", ["FileUrl"] = "Tệp", ["FileName"] = "Tên tệp", ["Rating"] = "Đánh giá",
        ["Score"] = "Điểm", ["Points"] = "Điểm", ["Target"] = "Chỉ tiêu", ["Result"] = "Kết quả", ["Rate"] = "Tỷ lệ",
        ["Percent"] = "Phần trăm", ["Percentage"] = "Phần trăm", ["Coefficient"] = "Hệ số", ["Multiplier"] = "Hệ số",
        ["LateMinutes"] = "Số phút đi trễ", ["EarlyMinutes"] = "Số phút về sớm", ["OvertimeHours"] = "Giờ tăng ca",
        ["WorkHours"] = "Giờ công", ["WorkDays"] = "Ngày công", ["StandardWorkDays"] = "Công chuẩn",
        ["RequireFace"] = "Bắt buộc khuôn mặt", ["RequireGps"] = "Bắt buộc GPS", ["RequireLocation"] = "Bắt buộc vị trí",
        ["RequireWifi"] = "Bắt buộc Wi-Fi", ["WifiSsid"] = "Tên Wi-Fi", ["WifiBssid"] = "Mã Wi-Fi (BSSID)",
        ["FaceMatchThreshold"] = "Ngưỡng khớp khuôn mặt", ["MatchScore"] = "Độ khớp khuôn mặt", ["FaceScore"] = "Độ khớp khuôn mặt",
        ["IsVerified"] = "Đã xác minh", ["IsTrusted"] = "Tin cậy", ["IsOutOfRange"] = "Ngoài vùng", ["LocationName"] = "Tên địa điểm",
        ["WorkLocationId"] = "Điểm chấm công", ["AttendanceType"] = "Loại chấm công", ["CheckType"] = "Vào / ra",
        ["PunchType"] = "Vào / ra", ["VerifyMode"] = "Cách xác thực", ["Source"] = "Nguồn", ["Channel"] = "Kênh",
        ["RegistrationDate"] = "Ngày đăng ký", ["ShiftName"] = "Tên ca", ["IsDayOff"] = "Ngày nghỉ", ["IsHoliday"] = "Ngày lễ",
        ["ApprovalStatus"] = "Trạng thái duyệt", ["ApprovalLevel"] = "Cấp duyệt", ["Level"] = "Cấp", ["Step"] = "Bước",
        ["Action"] = "Thao tác", ["Comment"] = "Nhận xét", ["TransferNo"] = "Số phiếu chuyển", ["FromBranchId"] = "Từ chi nhánh",
        ["ToBranchId"] = "Đến chi nhánh", ["ReceivedQty"] = "Số thực nhận", ["SupplierId"] = "Nhà cung cấp",
        ["WarehouseId"] = "Kho", ["LotNo"] = "Số lô", ["ExpiryAt"] = "Hạn dùng", ["TableId"] = "Bàn", ["AreaId"] = "Khu vực",
        ["GuestCount"] = "Số khách", ["ValidUntil"] = "Hiệu lực đến", ["DeliveryDate"] = "Ngày giao", ["Terms"] = "Điều khoản",
        ["PricesIncludeVat"] = "Giá đã gồm VAT", ["ShippingFee"] = "Phí giao hàng", ["Deposit"] = "Đặt cọc",
    };

    static readonly Dictionary<string, string> WordMap = new(StringComparer.OrdinalIgnoreCase)
    {
        ["id"] = "", ["is"] = "", ["has"] = "có", ["can"] = "được", ["allow"] = "cho phép", ["enable"] = "bật", ["enabled"] = "bật",
        ["require"] = "bắt buộc", ["required"] = "bắt buộc", ["auto"] = "tự động", ["max"] = "tối đa", ["min"] = "tối thiểu",
        ["total"] = "tổng", ["count"] = "số lượng", ["qty"] = "số lượng", ["amount"] = "số tiền", ["price"] = "giá",
        ["name"] = "tên", ["code"] = "mã", ["no"] = "số", ["number"] = "số", ["date"] = "ngày", ["time"] = "giờ", ["at"] = "lúc",
        ["day"] = "ngày", ["days"] = "ngày", ["hour"] = "giờ", ["hours"] = "giờ", ["minute"] = "phút", ["minutes"] = "phút",
        ["month"] = "tháng", ["year"] = "năm", ["week"] = "tuần", ["start"] = "bắt đầu", ["end"] = "kết thúc", ["from"] = "từ",
        ["to"] = "đến", ["late"] = "trễ", ["early"] = "sớm", ["overtime"] = "tăng ca", ["break"] = "nghỉ giữa ca", ["shift"] = "ca",
        ["work"] = "làm việc", ["working"] = "làm việc", ["schedule"] = "lịch", ["leave"] = "nghỉ phép", ["attendance"] = "chấm công",
        ["check"] = "chấm", ["in"] = "vào", ["out"] = "ra", ["face"] = "khuôn mặt", ["gps"] = "GPS", ["wifi"] = "Wi-Fi",
        ["location"] = "vị trí", ["radius"] = "bán kính", ["meters"] = "(m)", ["distance"] = "khoảng cách", ["photo"] = "ảnh",
        ["image"] = "ảnh", ["url"] = "đường dẫn", ["employee"] = "nhân viên", ["user"] = "tài khoản", ["customer"] = "khách hàng",
        ["supplier"] = "nhà cung cấp", ["product"] = "hàng hóa", ["variant"] = "biến thể", ["unit"] = "đơn vị", ["stock"] = "tồn kho",
        ["order"] = "đơn", ["sale"] = "bán", ["quote"] = "báo giá", ["line"] = "dòng", ["payment"] = "thanh toán", ["paid"] = "đã trả",
        ["discount"] = "giảm giá", ["vat"] = "VAT", ["tax"] = "thuế", ["fee"] = "phí", ["salary"] = "lương", ["bonus"] = "thưởng",
        ["penalty"] = "phạt", ["allowance"] = "phụ cấp", ["advance"] = "tạm ứng", ["approval"] = "duyệt", ["approved"] = "đã duyệt",
        ["approver"] = "người duyệt", ["reject"] = "từ chối", ["rejected"] = "đã từ chối", ["status"] = "trạng thái", ["type"] = "loại",
        ["note"] = "ghi chú", ["reason"] = "lý do", ["description"] = "mô tả", ["title"] = "tiêu đề", ["content"] = "nội dung",
        ["active"] = "đang dùng", ["default"] = "mặc định", ["visible"] = "hiển thị", ["hidden"] = "ẩn", ["show"] = "hiện",
        ["print"] = "in", ["printer"] = "máy in", ["template"] = "mẫu", ["notification"] = "thông báo", ["notify"] = "thông báo",
        ["branch"] = "chi nhánh", ["department"] = "phòng ban", ["store"] = "cửa hàng", ["device"] = "thiết bị", ["role"] = "vai trò",
        ["permission"] = "quyền", ["manager"] = "quản lý", ["parent"] = "cấp trên", ["level"] = "cấp", ["rate"] = "tỷ lệ",
        ["percent"] = "(%)", ["value"] = "giá trị", ["sort"] = "sắp xếp", ["order2"] = "thứ tự", ["color"] = "màu", ["phone"] = "điện thoại",
        ["address"] = "địa chỉ", ["email"] = "email", ["registration"] = "đăng ký", ["register"] = "đăng ký", ["mobile"] = "di động",
        ["point"] = "điểm", ["points"] = "điểm", ["score"] = "điểm", ["threshold"] = "ngưỡng", ["verified"] = "đã xác minh",
        ["trusted"] = "tin cậy", ["source"] = "nguồn", ["mode"] = "chế độ", ["limit"] = "giới hạn", ["period"] = "kỳ",
        ["standard"] = "chuẩn", ["deadline"] = "hạn", ["due"] = "hạn", ["expiry"] = "hết hạn", ["expires"] = "hết hạn",
        ["last"] = "gần nhất", ["first"] = "đầu tiên", ["next"] = "tiếp theo", ["new"] = "mới", ["old"] = "cũ", ["weekend"] = "cuối tuần",
        ["holiday"] = "ngày lễ", ["off"] = "nghỉ", ["half"] = "nửa", ["full"] = "cả", ["meal"] = "suất ăn", ["menu"] = "thực đơn",
        ["group"] = "nhóm", ["category"] = "nhóm", ["benefit"] = "phúc lợi", ["insurance"] = "bảo hiểm", ["kpi"] = "KPI",
        ["target"] = "chỉ tiêu", ["task"] = "công việc", ["project"] = "dự án", ["asset"] = "tài sản", ["cash"] = "tiền mặt",
        ["bank"] = "ngân hàng", ["account"] = "tài khoản", ["transfer"] = "chuyển", ["receipt"] = "phiếu nhập", ["issue"] = "xuất",
        ["cost"] = "giá vốn", ["profit"] = "lợi nhuận", ["deposit"] = "đặt cọc", ["valid"] = "hiệu lực", ["until"] = "đến",
        ["accuracy"] = "độ chính xác", ["latitude"] = "vĩ độ", ["longitude"] = "kinh độ", ["address2"] = "địa chỉ", ["trip"] = "công tác",
        ["business"] = "công tác", ["expense"] = "chi phí", ["claim"] = "đề nghị", ["settlement"] = "quyết toán", ["swap"] = "đổi",
        ["request"] = "yêu cầu", ["reply"] = "phản hồi", ["comment"] = "bình luận", ["file"] = "tệp", ["size"] = "kích thước",
        ["width"] = "chiều rộng", ["height"] = "chiều cao", ["font"] = "cỡ chữ", ["copies"] = "số liên", ["pos"] = "",
        ["json"] = "", ["by"] = "người", ["with"] = "kèm", ["per"] = "mỗi", ["and"] = "và", ["or"] = "hoặc", ["of"] = "", ["on"] = "khi",
        ["only"] = "chỉ", ["all"] = "tất cả", ["each"] = "mỗi", ["base"] = "cơ bản", ["gross"] = "gộp", ["net"] = "thực", ["daily"] = "theo ngày",
        ["monthly"] = "theo tháng", ["hourly"] = "theo giờ", ["fixed"] = "cố định", ["extra"] = "thêm", ["grace"] = "cho phép trễ",
        ["round"] = "làm tròn", ["rounding"] = "làm tròn", ["lunch"] = "nghỉ trưa", ["night"] = "đêm", ["morning"] = "sáng",
        ["afternoon"] = "chiều", ["evening"] = "tối", ["weekday"] = "ngày trong tuần", ["weekdays"] = "ngày trong tuần",
        ["outside"] = "ngoài", ["inside"] = "trong", ["within"] = "trong", ["after"] = "sau", ["before"] = "trước", ["reminder"] = "nhắc", ["remind"] = "nhắc", ["push"] = "đẩy", ["sms"] = "SMS", ["zalo"] = "Zalo",
    };

    public static string Field(string? field)
    {
        if (string.IsNullOrWhiteSpace(field)) return "";
        if (Fields.TryGetValue(field, out var v)) return v;
        // «XxxId» → tên loại dữ liệu tương ứng
        if (field.Length > 2 && field.EndsWith("Id", StringComparison.Ordinal)
            && Entities.TryGetValue(field[..^2], out var ent)) return ent;
        return Capitalize(Words(field));
    }

    /// <summary>Dịch từng từ theo thứ tự tiếng Việt: «MaxLateMinutes» → «phút trễ tối đa».</summary>
    static string Words(string technical)
    {
        var tokens = TokenRx().Matches(technical).Select(m => m.Value).ToList();
        if (tokens.Count == 0) return technical;
        // Cụm hai từ trước
        var merged = new List<string>();
        for (var i = 0; i < tokens.Count; i++)
        {
            var pair = i + 1 < tokens.Count ? (tokens[i] + tokens[i + 1]).ToLowerInvariant() : null;
            var phrase = pair switch
            {
                "checkin" => "giờ vào", "checkout" => "giờ ra", "dayoff" => "ngày nghỉ", "workday" => "ngày công",
                "sortorder" => "thứ tự", "createdby" => "người tạo", "updatedby" => "người sửa", "phonenumber" => "điện thoại",
                "onhand" => "tồn kho", "timezone" => "múi giờ", "wifibssid" => "mã Wi-Fi", "wifissid" => "tên Wi-Fi",
                _ => null,
            };
            if (phrase != null) { merged.Add(phrase); i++; continue; }
            merged.Add(Words_TryGet(tokens[i]));
        }
        merged.Reverse();
        var s = string.Join(" ", merged.Where(x => x.Length > 0));
        return s.Length == 0 ? technical : s;
    }

    static string Words_TryGet(string token) =>
        WordMap.TryGetValue(token, out var w) ? w : token.ToLowerInvariant();

    [GeneratedRegex("[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+")]
    private static partial Regex TokenRx();

    static bool IsTechnical(string s) => s.All(c => c < 128) && s.Any(char.IsUpper) && !s.Contains(' ');

    static string Capitalize(string s) => s.Length == 0 ? s : char.ToUpper(s[0], CultureInfo.GetCultureInfo("vi-VN")) + s[1..];

    // ─── Vai trò ──────────────────────────────────────────────────────────
    public static string? Role(string? role) => role switch
    {
        null or "" => role,
        "SuperAdmin" => "Quản trị hệ thống",
        "Admin" => "Chủ cửa hàng / Quản trị",
        "Director" => "Giám đốc",
        "Manager" => "Quản lý",
        "DepartmentHead" => "Trưởng phòng",
        "Accountant" => "Kế toán",
        "Agent" => "Đại lý",
        "Employee" => "Nhân viên",
        "Cashier" => "Thu ngân",
        "HR" or "HrManager" => "Nhân sự",
        _ => role,
    };

    // ─── Giá trị ──────────────────────────────────────────────────────────
    static readonly Dictionary<string, string> Values = new(StringComparer.OrdinalIgnoreCase)
    {
        ["True"] = "Có", ["False"] = "Không", ["Pending"] = "Chờ duyệt", ["Approved"] = "Đã duyệt", ["Rejected"] = "Từ chối",
        ["Cancelled"] = "Đã hủy", ["Canceled"] = "Đã hủy", ["Completed"] = "Hoàn tất", ["Done"] = "Xong", ["Draft"] = "Nháp",
        ["Active"] = "Đang hoạt động", ["Inactive"] = "Ngừng", ["Open"] = "Đang mở", ["Closed"] = "Đã đóng", ["Paid"] = "Đã trả",
        ["Unpaid"] = "Chưa trả", ["PartiallyPaid"] = "Trả một phần", ["Sent"] = "Đã gửi", ["Received"] = "Đã nhận",
        ["Processing"] = "Đang xử lý", ["InProgress"] = "Đang làm", ["New"] = "Mới", ["Expired"] = "Hết hạn",
        ["Income"] = "Thu", ["Expense"] = "Chi", ["Cash"] = "Tiền mặt", ["BankTransfer"] = "Chuyển khoản", ["Transfer"] = "Chuyển khoản",
        ["Card"] = "Thẻ", ["CheckIn"] = "Vào", ["CheckOut"] = "Ra", ["Male"] = "Nam", ["Female"] = "Nữ", ["Other"] = "Khác",
        ["Annual"] = "Phép năm", ["Sick"] = "Nghỉ ốm", ["Unpaid Leave"] = "Nghỉ không lương", ["Accepted"] = "Đã chấp nhận",
        ["Delivered"] = "Đã giao", ["Returned"] = "Đã trả hàng", ["Confirmed"] = "Đã xác nhận", ["Failed"] = "Thất bại",
        ["Success"] = "Thành công", ["Waiting"] = "Đang chờ", ["Locked"] = "Đã khóa", ["Working"] = "Đang làm việc",
        ["Resigned"] = "Đã nghỉ việc", ["Probation"] = "Thử việc", ["Official"] = "Chính thức",
    };

    static readonly Regex GuidRx = GuidRegex();
    [GeneratedRegex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")]
    private static partial Regex GuidRegex();

    static readonly Regex DateRx = DateRegex();
    [GeneratedRegex(@"^(\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}))?$")]
    private static partial Regex DateRegex();

    public static bool IsGuid(string? v) => v != null && GuidRx.IsMatch(v);

    /// <summary>Giá trị hiển thị: trạng thái → tiếng Việt, ngày → dd/MM/yyyy, mã nội bộ → rút gọn.</summary>
    public static string? Value(string? v)
    {
        if (v == null) return null;
        if (Values.TryGetValue(v, out var t)) return t;
        if (GuidRx.IsMatch(v)) return "#" + v[..8];
        var m = DateRx.Match(v);
        if (m.Success)
        {
            var d = $"{m.Groups[3].Value}/{m.Groups[2].Value}/{m.Groups[1].Value}";
            return m.Groups[4].Success && !(m.Groups[4].Value == "00" && m.Groups[5].Value == "00")
                ? $"{m.Groups[4].Value}:{m.Groups[5].Value} {d}" : d;
        }
        return v;
    }

    /// <summary>Dòng tóm tắt «Loại «nhãn» (+n bản ghi liên quan)».</summary>
    public static string Summary(string type, string? label, int count)
    {
        var l = string.IsNullOrWhiteSpace(label) || IsGuid(label) ? "" : $" «{(label!.Length > 120 ? label[..120] : label)}»";
        var more = count > 1 ? $" (+{count - 1} bản ghi liên quan)" : "";
        return $"{Entity(type)}{l}{more}";
    }
}
