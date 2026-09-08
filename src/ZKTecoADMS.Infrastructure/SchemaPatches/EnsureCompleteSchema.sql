-- BusinessTripAdvanceApprovalRecord
CREATE TABLE IF NOT EXISTS "BusinessTripAdvanceApprovalRecords" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "AdvanceClaimId" uuid NOT NULL,
    "StepOrder" integer NOT NULL DEFAULT 0,
    "StepName" text NULL,
    "AssignedUserId" uuid NULL,
    "AssignedUserName" text NULL,
    "ActualUserId" uuid NULL,
    "ActualUserName" text NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "Note" text NULL,
    "ActionDate" timestamp without time zone NULL,
    "StoreId" uuid NULL,
    CONSTRAINT "PK_BusinessTripAdvanceApprovalRecords" PRIMARY KEY ("Id")
);

-- BusinessTripAdvanceClaim
CREATE TABLE IF NOT EXISTS "BusinessTripAdvanceClaims" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "CaseId" uuid NOT NULL,
    "StoreId" uuid NULL,
    "Amount" numeric(18,2) NOT NULL DEFAULT 0,
    "Reason" text NULL DEFAULT '',
    "Note" text NULL,
    "RequestDate" timestamp without time zone NOT NULL DEFAULT NOW(),
    "Status" integer NOT NULL DEFAULT 0,
    "ApprovedById" uuid NULL,
    "ApprovedDate" timestamp without time zone NULL,
    "RejectionReason" text NULL,
    "IsPaid" boolean NOT NULL DEFAULT false,
    "PaymentMethod" text NULL,
    "PaidDate" timestamp without time zone NULL,
    "CashTransactionId" uuid NULL,
    "TotalApprovalLevels" integer NOT NULL DEFAULT 1,
    "CurrentApprovalStep" integer NOT NULL DEFAULT 0,
    CONSTRAINT "PK_BusinessTripAdvanceClaims" PRIMARY KEY ("Id")
);

-- BusinessTripCase
CREATE TABLE IF NOT EXISTS "BusinessTripCases" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "CaseCode" text NULL DEFAULT '',
    "EmployeeId" uuid NULL,
    "EmployeeUserId" uuid NULL,
    "StoreId" uuid NULL,
    "Title" text NULL DEFAULT '',
    "Destination" text NULL,
    "TripFromDate" timestamp without time zone NULL,
    "TripToDate" timestamp without time zone NULL,
    "Note" text NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "AdvanceAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "SettledAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "BalanceAmount" numeric(18,2) NOT NULL DEFAULT 0,
    CONSTRAINT "PK_BusinessTripCases" PRIMARY KEY ("Id")
);

-- BusinessTripExpenseAttachment
CREATE TABLE IF NOT EXISTS "BusinessTripExpenseAttachments" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "LineId" uuid NOT NULL,
    "FileName" text NULL DEFAULT '',
    "FileUrl" text NULL DEFAULT '',
    "ContentType" text NULL,
    "FileSize" bigint NULL,
    "AttachmentType" integer NOT NULL DEFAULT 0,
    "StoreId" uuid NULL,
    CONSTRAINT "PK_BusinessTripExpenseAttachments" PRIMARY KEY ("Id")
);

-- BusinessTripExpenseCategory
CREATE TABLE IF NOT EXISTS "BusinessTripExpenseCategories" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NULL,
    "Code" text NULL DEFAULT '',
    "Name" text NULL DEFAULT '',
    "Description" text NULL,
    "MaxAmountPerLine" numeric(18,2) NULL,
    "MaxAmountPerMonth" numeric(18,2) NULL,
    "RequiresInvoice" boolean NOT NULL DEFAULT false,
    "SortOrder" integer NOT NULL DEFAULT 0,
    CONSTRAINT "PK_BusinessTripExpenseCategories" PRIMARY KEY ("Id")
);

-- BusinessTripExpenseLine
CREATE TABLE IF NOT EXISTS "BusinessTripExpenseLines" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "SettlementClaimId" uuid NOT NULL,
    "CategoryId" uuid NULL,
    "ExpenseDate" timestamp without time zone NOT NULL DEFAULT NOW(),
    "Amount" numeric(18,2) NOT NULL DEFAULT 0,
    "Description" text NULL,
    "Note" text NULL,
    "HasInvoice" boolean NOT NULL DEFAULT false,
    "InvoiceNumber" text NULL,
    "InvoiceDate" timestamp without time zone NULL,
    "SortOrder" integer NOT NULL DEFAULT 0,
    CONSTRAINT "PK_BusinessTripExpenseLines" PRIMARY KEY ("Id")
);

-- BusinessTripSettlementApprovalRecord
CREATE TABLE IF NOT EXISTS "BusinessTripSettlementApprovalRecords" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "SettlementClaimId" uuid NOT NULL,
    "StepOrder" integer NOT NULL DEFAULT 0,
    "StepName" text NULL,
    "AssignedUserId" uuid NULL,
    "AssignedUserName" text NULL,
    "ActualUserId" uuid NULL,
    "ActualUserName" text NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "Note" text NULL,
    "ActionDate" timestamp without time zone NULL,
    "StoreId" uuid NULL,
    CONSTRAINT "PK_BusinessTripSettlementApprovalRecords" PRIMARY KEY ("Id")
);

-- BusinessTripSettlementClaim
CREATE TABLE IF NOT EXISTS "BusinessTripSettlementClaims" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "CaseId" uuid NOT NULL,
    "StoreId" uuid NULL,
    "AdvanceAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "TotalAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "TotalWithInvoice" numeric(18,2) NOT NULL DEFAULT 0,
    "TotalWithoutInvoice" numeric(18,2) NOT NULL DEFAULT 0,
    "BalanceAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "SettlementType" integer NOT NULL DEFAULT 0,
    "Note" text NULL,
    "SubmittedAt" timestamp without time zone NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "ApprovedById" uuid NULL,
    "ApprovedDate" timestamp without time zone NULL,
    "RejectionReason" text NULL,
    "IsExtraPaid" boolean NOT NULL DEFAULT false,
    "ExtraPaymentMethod" text NULL,
    "ExtraPaidDate" timestamp without time zone NULL,
    "ExtraCashTransactionId" uuid NULL,
    "SurplusPaymentTransactionId" uuid NULL,
    "SurplusAdvanceRequestId" uuid NULL,
    "TotalApprovalLevels" integer NOT NULL DEFAULT 1,
    "CurrentApprovalStep" integer NOT NULL DEFAULT 0,
    CONSTRAINT "PK_BusinessTripSettlementClaims" PRIMARY KEY ("Id")
);

-- ContentCategory
CREATE TABLE IF NOT EXISTS "ContentCategories" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "Name" text NULL DEFAULT '',
    "Description" text NULL,
    "ContentType" integer NOT NULL DEFAULT 0,
    "IconName" text NULL,
    "Color" text NULL,
    "DisplayOrder" integer NOT NULL DEFAULT 0,
    "ParentCategoryId" uuid NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    CONSTRAINT "PK_ContentCategories" PRIMARY KEY ("Id")
);

-- FundTransfer
CREATE TABLE IF NOT EXISTS "FundTransfers" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "TransferCode" text NULL DEFAULT '',
    "FromBankAccountId" uuid NULL,
    "ToBankAccountId" uuid NULL,
    "Amount" numeric(18,2) NOT NULL DEFAULT 0,
    "TransferDate" timestamp without time zone NOT NULL DEFAULT NOW(),
    "Description" text NULL DEFAULT '',
    "InternalNote" text NULL,
    "StoreId" uuid NULL,
    "CreatedByUserId" uuid NOT NULL,
    CONSTRAINT "PK_FundTransfers" PRIMARY KEY ("Id")
);

-- MobileLocationEmployee
CREATE TABLE IF NOT EXISTS "MobileLocationEmployees" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "WorkLocationId" uuid NOT NULL,
    "EmployeeId" text NULL DEFAULT '',
    "EmployeeName" text NULL,
    CONSTRAINT "PK_MobileLocationEmployees" PRIMARY KEY ("Id")
);

-- PosCustomerPayment
CREATE TABLE IF NOT EXISTS "PosCustomerPayments" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "CustomerId" uuid NOT NULL,
    "SaleOrderId" uuid NULL,
    "PaymentNo" text NULL DEFAULT '',
    "Amount" numeric(18,2) NOT NULL DEFAULT 0,
    "PaymentMethod" text NULL,
    "PaidAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "Note" text NULL,
    CONSTRAINT "PK_PosCustomerPayments" PRIMARY KEY ("Id")
);

-- PosCustomerPointTransaction
CREATE TABLE IF NOT EXISTS "PosCustomerPointTransactions" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "CustomerId" uuid NOT NULL,
    "SaleOrderId" uuid NULL,
    "TransactionType" integer NOT NULL DEFAULT 0,
    "Points" numeric(18,2) NOT NULL DEFAULT 0,
    "BalanceAfter" numeric(18,2) NOT NULL DEFAULT 0,
    "Note" text NULL,
    CONSTRAINT "PK_PosCustomerPointTransactions" PRIMARY KEY ("Id")
);

-- PosCustomerSessionBalance
CREATE TABLE IF NOT EXISTS "PosCustomerSessionBalances" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "CustomerId" uuid NOT NULL,
    "ProductId" uuid NULL,
    "PackageName" text NULL DEFAULT '',
    "TotalSessions" integer NOT NULL DEFAULT 0,
    "RemainingSessions" integer NOT NULL DEFAULT 0,
    "ExpiresAt" timestamp without time zone NULL,
    CONSTRAINT "PK_PosCustomerSessionBalances" PRIMARY KEY ("Id")
);

-- PosCustomerSessionTransaction
CREATE TABLE IF NOT EXISTS "PosCustomerSessionTransactions" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "BalanceId" uuid NOT NULL,
    "CustomerId" uuid NULL,
    "SaleOrderId" uuid NULL,
    "TransactionType" integer NOT NULL DEFAULT 0,
    "SessionDelta" integer NOT NULL DEFAULT 0,
    "RemainingAfter" integer NOT NULL DEFAULT 0,
    "Note" text NULL,
    CONSTRAINT "PK_PosCustomerSessionTransactions" PRIMARY KEY ("Id")
);

-- PosProductWarrantyRegistration
CREATE TABLE IF NOT EXISTS "PosProductWarrantyRegistrations" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "SaleOrderId" uuid NOT NULL,
    "SaleOrderLineId" uuid NOT NULL,
    "ProductId" uuid NOT NULL,
    "VariantId" uuid NULL,
    "CustomerId" uuid NULL,
    "SerialNumber" text NULL DEFAULT '',
    "Imei" text NULL,
    "WarrantyMonths" integer NOT NULL DEFAULT 0,
    "SaleDate" timestamp without time zone NOT NULL DEFAULT NOW(),
    "WarrantyExpiry" timestamp without time zone NOT NULL DEFAULT NOW(),
    "Status" integer NOT NULL DEFAULT 0,
    "Note" text NULL,
    CONSTRAINT "PK_PosProductWarrantyRegistrations" PRIMARY KEY ("Id")
);

-- PosPurchaseReturnLine
CREATE TABLE IF NOT EXISTS "PosPurchaseReturnLines" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "ReturnId" uuid NOT NULL,
    "ProductId" uuid NOT NULL,
    "VariantId" uuid NULL,
    "ProductName" text NULL DEFAULT '',
    "ProductCode" text NULL,
    "UnitName" text NULL,
    "Qty" numeric(18,2) NOT NULL DEFAULT 0,
    "CostPrice" numeric(18,2) NOT NULL DEFAULT 0,
    "DiscountAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "LineTotal" numeric(18,2) NOT NULL DEFAULT 0,
    "LineNote" text NULL,
    CONSTRAINT "PK_PosPurchaseReturnLines" PRIMARY KEY ("Id")
);

-- PosPurchaseReturn
CREATE TABLE IF NOT EXISTS "PosPurchaseReturns" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "ReturnNo" text NULL DEFAULT '',
    "SupplierId" uuid NULL,
    "SourceReceiptId" uuid NULL,
    "Note" text NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "TotalQty" numeric(18,2) NOT NULL DEFAULT 0,
    "TotalAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "DiscountAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "RefundDue" numeric(18,2) NOT NULL DEFAULT 0,
    "RefundReceived" numeric(18,2) NOT NULL DEFAULT 0,
    "ReturnDate" timestamp without time zone NULL,
    "ReturnedBy" text NULL,
    CONSTRAINT "PK_PosPurchaseReturns" PRIMARY KEY ("Id")
);

-- PosStockCountLine
CREATE TABLE IF NOT EXISTS "PosStockCountLines" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "CountId" uuid NOT NULL,
    "ProductId" uuid NOT NULL,
    "VariantId" uuid NULL,
    "ProductName" text NULL DEFAULT '',
    "ProductCode" text NULL,
    "UnitName" text NULL,
    "CostPrice" numeric(18,2) NOT NULL DEFAULT 0,
    "SystemQty" numeric(18,2) NOT NULL DEFAULT 0,
    "CountedQty" numeric(18,2) NULL,
    "IsChecked" boolean NOT NULL DEFAULT false,
    CONSTRAINT "PK_PosStockCountLines" PRIMARY KEY ("Id")
);

-- PosStockCount
CREATE TABLE IF NOT EXISTS "PosStockCounts" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "CountNo" text NULL DEFAULT '',
    "Name" text NULL DEFAULT '',
    "Note" text NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "CompletedAt" timestamp without time zone NULL,
    "BalancedBy" text NULL,
    CONSTRAINT "PK_PosStockCounts" PRIMARY KEY ("Id")
);

-- PosStockIssueLine
CREATE TABLE IF NOT EXISTS "PosStockIssueLines" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "IssueId" uuid NOT NULL,
    "ProductId" uuid NOT NULL,
    "VariantId" uuid NULL,
    "ProductName" text NULL DEFAULT '',
    "ProductCode" text NULL,
    "Qty" numeric(18,2) NOT NULL DEFAULT 0,
    "CostPrice" numeric(18,2) NOT NULL DEFAULT 0,
    "UnitName" text NULL,
    "LineNote" text NULL,
    CONSTRAINT "PK_PosStockIssueLines" PRIMARY KEY ("Id")
);

-- PosStockIssue
CREATE TABLE IF NOT EXISTS "PosStockIssues" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "IssueNo" text NULL DEFAULT '',
    "Reason" text NULL,
    "Note" text NULL,
    "Kind" integer NOT NULL DEFAULT 0,
    "Status" integer NOT NULL DEFAULT 0,
    "IssuedAt" timestamp without time zone NULL,
    "IssuedBy" text NULL,
    "CategoryName" text NULL,
    "RecipientName" text NULL,
    "CompletedAt" timestamp without time zone NULL,
    "TotalQty" numeric(18,2) NOT NULL DEFAULT 0,
    "TotalValue" numeric(18,2) NOT NULL DEFAULT 0,
    CONSTRAINT "PK_PosStockIssues" PRIMARY KEY ("Id")
);

-- PosStockLot
CREATE TABLE IF NOT EXISTS "PosStockLots" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "ProductId" uuid NOT NULL,
    "VariantId" uuid NULL,
    "LotNo" text NULL,
    "ManufactureDate" timestamp without time zone NULL,
    "ExpiryDate" timestamp without time zone NULL,
    "QtyOnHand" numeric(18,2) NOT NULL DEFAULT 0,
    "UnitCost" numeric(18,2) NOT NULL DEFAULT 0,
    "Status" integer NOT NULL DEFAULT 0,
    "StockReceiptId" uuid NULL,
    "StockReceiptLineId" uuid NULL,
    CONSTRAINT "PK_PosStockLots" PRIMARY KEY ("Id")
);

-- PosSupplierGroup
CREATE TABLE IF NOT EXISTS "PosSupplierGroups" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "Name" text NULL DEFAULT '',
    CONSTRAINT "PK_PosSupplierGroups" PRIMARY KEY ("Id")
);

-- PosSupplierPayment
CREATE TABLE IF NOT EXISTS "PosSupplierPayments" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "SupplierId" uuid NOT NULL,
    "StockReceiptId" uuid NULL,
    "PaymentNo" text NULL DEFAULT '',
    "Amount" numeric(18,2) NOT NULL DEFAULT 0,
    "PaymentMethod" text NULL,
    "PaidAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "Note" text NULL,
    CONSTRAINT "PK_PosSupplierPayments" PRIMARY KEY ("Id")
);

-- PosVoucher
CREATE TABLE IF NOT EXISTS "PosVouchers" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "Code" text NULL DEFAULT '',
    "Name" text NULL,
    "DiscountType" integer NOT NULL DEFAULT 0,
    "DiscountValue" numeric(18,2) NOT NULL DEFAULT 0,
    "MinOrderAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "MaxDiscountAmount" numeric(18,2) NULL,
    "ValidFrom" timestamp without time zone NULL,
    "ValidTo" timestamp without time zone NULL,
    "MaxUses" integer NULL,
    "UsedCount" integer NOT NULL DEFAULT 0,
    "CustomerId" uuid NULL,
    CONSTRAINT "PK_PosVouchers" PRIMARY KEY ("Id")
);

-- ShiftSalaryLevel
CREATE TABLE IF NOT EXISTS "ShiftSalaryLevels" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "ShiftTemplateId" uuid NOT NULL,
    "LevelName" text NULL DEFAULT '',
    "SortOrder" integer NOT NULL DEFAULT 0,
    "RateType" text NULL,
    "FixedRate" numeric(18,2) NOT NULL DEFAULT 0,
    "HourlyRate" numeric(18,2) NOT NULL DEFAULT 0,
    "Multiplier" numeric(18,2) NOT NULL DEFAULT 1.0,
    "ShiftAllowance" numeric(18,2) NOT NULL DEFAULT 0,
    "IsNightShift" boolean NOT NULL DEFAULT false,
    "EmployeeIds" text NULL,
    "Description" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "StoreId" uuid NULL,
    CONSTRAINT "PK_ShiftSalaryLevels" PRIMARY KEY ("Id")
);

-- AdvanceRequests
ALTER TABLE "AdvanceRequests" ADD COLUMN IF NOT EXISTS "ApprovedAmount" numeric(18,2) NULL;

-- Allowances
ALTER TABLE "Allowances" ADD COLUMN IF NOT EXISTS "StartDate" timestamp without time zone NULL;
ALTER TABLE "Allowances" ADD COLUMN IF NOT EXISTS "EndDate" timestamp without time zone NULL;
ALTER TABLE "Allowances" ADD COLUMN IF NOT EXISTS "EmployeeIds" text NULL;

-- AuthorizedMobileDevices
ALTER TABLE "AuthorizedMobileDevices" ADD COLUMN IF NOT EXISTS "SelectedLocationIdsJson" text NULL;

-- DeviceChangeRequests
ALTER TABLE "DeviceChangeRequests" ADD COLUMN IF NOT EXISTS "SelectedLocationIdsJson" text NULL;

-- DeviceInfos
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "Platform" text NULL;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "PushVersion" text NULL;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "DeviceModelName" text NULL;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "OemVendor" text NULL;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "EngineProfile" text NULL;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "SupportsUserQuery" boolean NULL;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "SupportsAttendanceQuery" boolean NULL;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "SupportsEnrollFingerprint" boolean NULL;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "SupportsFaceUpdate" boolean NULL;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "SupportsDoorControl" boolean NULL;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "PreferStampSync" boolean NOT NULL DEFAULT false;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "CapabilityUpdatedAt" timestamp without time zone NULL;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "CapabilityNotes" text NULL;

-- EmployeeTaxDeductions
ALTER TABLE "EmployeeTaxDeductions" ADD COLUMN IF NOT EXISTS "DependentRegistrationFormUrl" text NULL;
ALTER TABLE "EmployeeTaxDeductions" ADD COLUMN IF NOT EXISTS "DependentDocumentsJson" text NULL;

-- InternalCommunications
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "CategoryId" uuid NULL;

-- PayslipAttendanceSnapshots
ALTER TABLE "PayslipAttendanceSnapshots" ADD COLUMN IF NOT EXISTS "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW();
ALTER TABLE "PayslipAttendanceSnapshots" ADD COLUMN IF NOT EXISTS "UpdatedAt" timestamp without time zone NULL;
ALTER TABLE "PayslipAttendanceSnapshots" ADD COLUMN IF NOT EXISTS "UpdatedBy" text NULL;
ALTER TABLE "PayslipAttendanceSnapshots" ADD COLUMN IF NOT EXISTS "CreatedBy" text NULL;

-- Payslips
ALTER TABLE "Payslips" ADD COLUMN IF NOT EXISTS "EmployeeId" uuid NULL;
ALTER TABLE "Payslips" ADD COLUMN IF NOT EXISTS "CashTransactionId" uuid NULL;

-- PosSaleOrderLines
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "DiscountAmount" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "LineNote" text NULL;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "DurationMinutes" integer NULL;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "BillableMinutes" integer NULL;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "ServiceStartedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "ServiceEndedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "AssignedEmployeeId" uuid NULL;

-- PosStockReceiptLines
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "UnitName" text NULL;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "DiscountAmount" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "VatRate" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "VatAmount" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "VatIncluded" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "VatExempt" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "LineNote" text NULL;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "LotNo" text NULL;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "ManufactureDate" timestamp without time zone NULL;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "ExpiryDate" timestamp without time zone NULL;

-- PosStockReceipts
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "Status" integer NOT NULL DEFAULT 0;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "ImportDate" timestamp without time zone NULL;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "ImportedBy" text NULL;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "InputInvoiceNo" text NULL;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "PurchaseOrderNo" text NULL;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "DiscountAmount" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "PaidAmount" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "DiscountIsPercent" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "DiscountInput" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "TotalVat" numeric(18,2) NOT NULL DEFAULT 0;

-- PosStockTransactions
ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "UnitCost" numeric(18,2) NULL;
ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "LineAmount" numeric(18,2) NULL;
ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "StockIssueId" uuid NULL;
ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "StockCountId" uuid NULL;
ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "PurchaseReturnId" uuid NULL;
ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "LotId" uuid NULL;

-- SalaryProfiles
ALTER TABLE "SalaryProfiles" ADD COLUMN IF NOT EXISTS "FixedStandardWorkDays" integer NULL;
ALTER TABLE "SalaryProfiles" ADD COLUMN IF NOT EXISTS "DeductIfBelowFixedStandard" boolean NOT NULL DEFAULT true;
ALTER TABLE "SalaryProfiles" ADD COLUMN IF NOT EXISTS "AddIfAboveFixedStandard" boolean NOT NULL DEFAULT true;
ALTER TABLE "SalaryProfiles" ADD COLUMN IF NOT EXISTS "TravelSalaryMode" text NULL;
ALTER TABLE "SalaryProfiles" ADD COLUMN IF NOT EXISTS "TravelFixedHourlyRate" numeric(18,2) NULL;
ALTER TABLE "SalaryProfiles" ADD COLUMN IF NOT EXISTS "ApplyLateEarlyOnRestDayOt" boolean NOT NULL DEFAULT true;
ALTER TABLE "SalaryProfiles" ADD COLUMN IF NOT EXISTS "RestDayOtHoursOnly" boolean NOT NULL DEFAULT false;
ALTER TABLE "SalaryProfiles" ADD COLUMN IF NOT EXISTS "OvertimeHourlyBaseMode" text NULL;

-- TaskDependencies
ALTER TABLE "TaskDependencies" ADD COLUMN IF NOT EXISTS "UpdatedAt" timestamp without time zone NULL;
ALTER TABLE "TaskDependencies" ADD COLUMN IF NOT EXISTS "UpdatedBy" text NULL;
ALTER TABLE "TaskDependencies" ADD COLUMN IF NOT EXISTS "CreatedBy" text NULL;

-- TaskTemplates
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;

UPDATE "Payslips" p
SET "EmployeeId" = e."Id"
FROM "Employees" e
WHERE p."EmployeeId" IS NULL AND e."ApplicationUserId" = p."EmployeeUserId";
