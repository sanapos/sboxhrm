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
    "UsedAt" timestamp without time zone NULL,
    "EmployeeId" uuid NULL,
    "EmployeeName" text NULL,
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
ALTER TABLE "Allowances" ADD COLUMN IF NOT EXISTS "ShiftIds" text NULL;

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

ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "ComboTrackStock" boolean NOT NULL DEFAULT true;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'PosProductComboLines'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'PosProductComboLines'
          AND column_name = 'TrackStock'
    ) THEN
        ALTER TABLE "PosProductComboLines" ADD COLUMN "TrackStock" boolean NOT NULL DEFAULT true;
        UPDATE "PosProductComboLines" l
        SET "TrackStock" = false
        FROM "PosProducts" p
        WHERE l."ComponentProductId" = p."Id" AND p."ProductType" = 1;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS "PosQuotes" (
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
    "QuoteNo" character varying(30) NOT NULL DEFAULT '',
    "Status" integer NOT NULL DEFAULT 0,
    "CustomerId" uuid NULL,
    "CustomerName" character varying(200) NULL,
    "CustomerPhone" character varying(50) NULL,
    "CustomerAddress" character varying(500) NULL,
    "ValidUntil" timestamp without time zone NULL,
    "IssuedAt" timestamp without time zone NULL,
    "IssuedBy" character varying(200) NULL,
    "SubTotal" numeric(18,2) NOT NULL DEFAULT 0,
    "Discount" numeric(18,2) NOT NULL DEFAULT 0,
    "VatAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "Total" numeric(18,2) NOT NULL DEFAULT 0,
    "Note" character varying(1000) NULL,
    "Terms" character varying(2000) NULL,
    "PrintTemplateId" uuid NULL,
    "Revision" integer NOT NULL DEFAULT 1,
    "QuotedBy" character varying(200) NULL,
    "QuotedByEmployeeId" uuid NULL,
    CONSTRAINT "PK_PosQuotes" PRIMARY KEY ("Id")
);

CREATE TABLE IF NOT EXISTS "PosQuoteLines" (
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
    "QuoteId" uuid NOT NULL,
    "ProductId" uuid NULL,
    "ProductCode" character varying(50) NULL,
    "ProductName" character varying(500) NOT NULL DEFAULT '',
    "UnitName" character varying(100) NULL,
    "Qty" numeric(18,4) NOT NULL DEFAULT 1,
    "UnitPrice" numeric(18,2) NOT NULL DEFAULT 0,
    "DiscountAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "VatRate" numeric(5,2) NOT NULL DEFAULT 0,
    "LineTotal" numeric(18,2) NOT NULL DEFAULT 0,
    "LineNote" character varying(500) NULL,
    "SortOrder" integer NOT NULL DEFAULT 0,
    CONSTRAINT "PK_PosQuoteLines" PRIMARY KEY ("Id")
);

ALTER TABLE "PosQuotes" ADD COLUMN IF NOT EXISTS "CommercialStage" integer NOT NULL DEFAULT 0;
-- Migration 20260925010000_AddPosQuoteIncludeImages (migrations không tự chạy trên server).
ALTER TABLE "PosQuotes" ADD COLUMN IF NOT EXISTS "IncludeImages" boolean NOT NULL DEFAULT false;

-- Mẫu Word giữ nguyên bố cục (AI gắn mã trường).
ALTER TABLE "PosPrintTemplates" ADD COLUMN IF NOT EXISTS "DocxFilePath" text NULL;
ALTER TABLE "PosPrintTemplates" ADD COLUMN IF NOT EXISTS "DocxMappingJson" text NULL;
ALTER TABLE "PosStockIssues" ADD COLUMN IF NOT EXISTS "QuoteId" uuid NULL;

CREATE TABLE IF NOT EXISTS "PosQuoteDocuments" (
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
    "QuoteId" uuid NOT NULL,
    "Kind" integer NOT NULL DEFAULT 0,
    "DocNo" character varying(30) NOT NULL DEFAULT '',
    "Title" character varying(200) NOT NULL DEFAULT '',
    "HtmlContent" text NOT NULL DEFAULT '',
    "Note" character varying(1000) NULL,
    "IssuedAt" timestamp without time zone NULL,
    "IssuedBy" character varying(200) NULL,
    "PrintTemplateId" uuid NULL,
    "StockIssueId" uuid NULL,
    CONSTRAINT "PK_PosQuoteDocuments" PRIMARY KEY ("Id")
);
ALTER TABLE "PosCustomerSessionTransactions" ADD COLUMN IF NOT EXISTS "EmployeeId" uuid NULL;
ALTER TABLE "PosCustomerSessionTransactions" ADD COLUMN IF NOT EXISTS "EmployeeName" character varying(200) NULL;
ALTER TABLE "PosCustomerSessionTransactions" ADD COLUMN IF NOT EXISTS "UsedAt" timestamp without time zone NULL;

UPDATE "Payslips" p
SET "EmployeeId" = e."Id"
FROM "Employees" e
WHERE p."EmployeeId" IS NULL AND e."ApplicationUserId" = p."EmployeeUserId";

-- Hình thức thu phạt: Salary = trừ vào lương (không phiếu thu), Cash = thu tiền mặt từng lần (phiếu thu).
ALTER TABLE "PenaltySettings" ADD COLUMN IF NOT EXISTS "CollectionMethod" character varying(20) NOT NULL DEFAULT 'Salary';
ALTER TABLE "PenaltyTickets" ADD COLUMN IF NOT EXISTS "CollectionMethod" character varying(20) NULL;
-- Phiếu đã duyệt trước đây: phiếu thu đã thu tiền → Cash; còn lại → Salary (trừ lương).
UPDATE "PenaltyTickets" t
SET "CollectionMethod" = CASE WHEN EXISTS (
        SELECT 1 FROM "CashTransactions" c
        WHERE c."Id" = t."CashTransactionId" AND c."Deleted" IS NULL
          AND (c."IsPaid" = true OR c."Status" = 2)) THEN 'Cash' ELSE 'Salary' END
WHERE t."CollectionMethod" IS NULL AND t."Status" IN (1, 3);

-- Đăng ký lịch: dòng lịch lần duyệt ghi vào (hoàn duyệt / xóa phiếu không xóa lịch quản lý xếp sẵn).
ALTER TABLE "ScheduleRegistrations" ADD COLUMN IF NOT EXISTS "AppliedWorkScheduleId" uuid NULL;
ALTER TABLE "ScheduleRegistrations" ADD COLUMN IF NOT EXISTS "AppliedCreatedNewSchedule" boolean NOT NULL DEFAULT false;

-- Khách lưu trú (khách sạn): thông tin khai báo tạm trú theo lượt nhận phòng.
CREATE TABLE IF NOT EXISTS "PosStayGuests" (
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
    "ResourceSessionId" uuid NOT NULL,
    "FullName" character varying(200) NOT NULL DEFAULT '',
    "IdType" character varying(30) NOT NULL DEFAULT 'CCCD',
    "IdNumber" character varying(50) NULL,
    "DateOfBirth" timestamp without time zone NULL,
    "Gender" character varying(20) NULL,
    "Nationality" character varying(100) NULL,
    "Address" character varying(500) NULL,
    "Phone" character varying(30) NULL,
    "Note" character varying(500) NULL,
    "IsPrimary" boolean NOT NULL DEFAULT false,
    CONSTRAINT "PK_PosStayGuests" PRIMARY KEY ("Id")
);
CREATE INDEX IF NOT EXISTS "IX_PosStayGuests_Store_Session" ON "PosStayGuests" ("StoreId", "ResourceSessionId");

-- Gym: hội viên trên máy chấm công (PIN riêng) + lượt vào/ra — tách biệt chấm công nhân viên
CREATE TABLE IF NOT EXISTS "PosGymMemberDevices" (
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
    "DeviceId" uuid NOT NULL,
    "DeviceUserId" uuid NULL,
    "Pin" character varying(20) NOT NULL DEFAULT '',
    "CardNumber" character varying(50) NULL,
    CONSTRAINT "PK_PosGymMemberDevices" PRIMARY KEY ("Id")
);
CREATE INDEX IF NOT EXISTS "IX_PosGymMemberDevices_Device_Pin" ON "PosGymMemberDevices" ("DeviceId", "Pin");
CREATE INDEX IF NOT EXISTS "IX_PosGymMemberDevices_Store_Customer" ON "PosGymMemberDevices" ("StoreId", "CustomerId");

CREATE TABLE IF NOT EXISTS "PosGymVisits" (
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
    "DeviceId" uuid NULL,
    "Pin" character varying(20) NULL,
    "CheckInAt" timestamp without time zone NOT NULL,
    "CheckOutAt" timestamp without time zone NULL,
    "DurationMinutes" integer NULL,
    "BalanceId" uuid NULL,
    "PackageName" character varying(200) NULL,
    "SessionDeducted" boolean NOT NULL DEFAULT false,
    "Status" character varying(30) NOT NULL DEFAULT 'Ok',
    "Source" character varying(20) NOT NULL DEFAULT 'Device',
    "Note" character varying(500) NULL,
    CONSTRAINT "PK_PosGymVisits" PRIMARY KEY ("Id")
);
CREATE INDEX IF NOT EXISTS "IX_PosGymVisits_Store_CheckIn" ON "PosGymVisits" ("StoreId", "CheckInAt");
CREATE INDEX IF NOT EXISTS "IX_PosGymVisits_Customer_CheckIn" ON "PosGymVisits" ("CustomerId", "CheckInAt");

-- Lịch sử thao tác cửa hàng: lọc theo cửa hàng + thời gian
CREATE INDEX IF NOT EXISTS "IX_AuditLogs_Store_Timestamp" ON "AuditLogs" ("StoreId", "Timestamp" DESC);

-- Gói giờ đếm ngược (mua 1h: hết giờ báo + tính quá giờ)
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "TimePackageMinutes" integer NOT NULL DEFAULT 0;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "OvertimeProductId" uuid NULL;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "TimeAlertBeforeMinutes" integer NOT NULL DEFAULT 5;

-- Chốt tiền giờ (đếm lên) + hoa hồng theo từng buổi làm (gói liệu trình)
ALTER TABLE "PosResourceSessions" ADD COLUMN IF NOT EXISTS "BillingLockedAt" timestamp without time zone NULL;
ALTER TABLE "PosResourceSessions" ADD COLUMN IF NOT EXISTS "BillingLockedBy" character varying(256) NULL;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "CommissionPerSession" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosSaleCommissionLines" ADD COLUMN IF NOT EXISTS "PerformedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleCommissionLines" ADD COLUMN IF NOT EXISTS "SessionTransactionId" uuid NULL;

-- Đếm giờ riêng từng dòng dịch vụ (tạm dừng / kết thúc từng dòng)
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "ServicePausedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "ServicePauseMinutes" integer NOT NULL DEFAULT 0;

-- Chống trùng khi máy gửi lại do lỗi mạng (idempotency key)
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "ClientRequestId" character varying(64) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "KitchenSendRequestId" character varying(64) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "KitchenSendReplayJson" text NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosSaleOrders_Store_ClientRequestId" ON "PosSaleOrders" ("StoreId", "ClientRequestId") WHERE "ClientRequestId" IS NOT NULL AND "Deleted" IS NULL;
ALTER TABLE "PosPrintJobs" ADD COLUMN IF NOT EXISTS "ClientRequestId" character varying(64) NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosPrintJobs_Store_ClientRequestId" ON "PosPrintJobs" ("StoreId", "ClientRequestId") WHERE "ClientRequestId" IS NOT NULL AND "Deleted" IS NULL;

-- Vận chuyển: trạng thái chuẩn, mốc thời gian, phí hãng, COD, nhật ký hành trình
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryStatusCode" character varying(30) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryStatusAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryShippedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryPickedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryDeliveredAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryFailCount" integer NOT NULL DEFAULT 0;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryLastReason" character varying(500) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryReturnedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryReturnReceivedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryReturnReceivedBy" character varying(200) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryCancelledAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryCarrierFee" numeric(18,2) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryCodAmount" numeric(18,2) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryFeePayer" character varying(20) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryServiceName" character varying(120) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryCodSettledAt" timestamp without time zone NULL;
CREATE INDEX IF NOT EXISTS "IX_PosSaleOrders_Store_DeliveryStatusCode" ON "PosSaleOrders" ("StoreId", "DeliveryStatusCode") WHERE "IsDelivery";
CREATE TABLE IF NOT EXISTS "PosShipmentEvents" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "SaleOrderId" uuid NOT NULL,
    "CarrierCode" character varying(30) NULL,
    "TrackingCode" character varying(64) NULL,
    "StatusCode" character varying(30) NOT NULL,
    "RawStatus" character varying(200) NULL,
    "Reason" character varying(500) NULL,
    "Source" character varying(20) NOT NULL DEFAULT 'webhook',
    "OccurredAt" timestamp without time zone NOT NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text NULL,
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosShipmentEvents_Order" ON "PosShipmentEvents" ("SaleOrderId", "OccurredAt");
CREATE INDEX IF NOT EXISTS "IX_PosShipmentEvents_Store_Status" ON "PosShipmentEvents" ("StoreId", "StatusCode", "OccurredAt");
-- Công việc v2: dự án / giai đoạn ngành / checklist có ảnh / việc lặp lại
CREATE TABLE IF NOT EXISTS "TaskProjects" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores" ("Id") ON DELETE CASCADE,
    "Code" character varying(32) NOT NULL,
    "Name" character varying(200) NOT NULL,
    "Description" character varying(4000) NULL,
    "IndustryKey" character varying(40) NULL,
    "Color" character varying(9) NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "OwnerEmployeeId" uuid NULL REFERENCES "Employees" ("Id") ON DELETE SET NULL,
    "BranchId" uuid NULL,
    "CustomerName" character varying(200) NULL,
    "CustomerPhone" character varying(30) NULL,
    "Address" character varying(300) NULL,
    "Budget" numeric(18,2) NULL,
    "StartDate" timestamp without time zone NULL,
    "DueDate" timestamp without time zone NULL,
    "CompletedAt" timestamp without time zone NULL,
    "Stages" character varying(4000) NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text NULL,
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_TaskProjects_Store_Status" ON "TaskProjects" ("StoreId", "Status");
CREATE UNIQUE INDEX IF NOT EXISTS "IX_TaskProjects_Store_Code" ON "TaskProjects" ("StoreId", "Code");
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "ProjectId" uuid NULL REFERENCES "TaskProjects" ("Id") ON DELETE SET NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "StageKey" character varying(40) NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "ProgressMode" integer NOT NULL DEFAULT 0;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "Location" character varying(300) NULL;
CREATE INDEX IF NOT EXISTS "IX_WorkTasks_Store_Project" ON "WorkTasks" ("StoreId", "ProjectId");
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "IndustryKey" character varying(40) NULL;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "StageKey" character varying(40) NULL;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "ProgressMode" integer NOT NULL DEFAULT 1;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "ProjectId" uuid NULL;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "RecurrenceType" integer NOT NULL DEFAULT 0;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "RecurrenceDays" character varying(100) NULL;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "RecurrenceTime" character varying(5) NULL;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "DueAfterHours" integer NULL;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "DefaultAssigneeIds" character varying(2000) NULL;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "NextRunAt" timestamp without time zone NULL;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "LastRunAt" timestamp without time zone NULL;
CREATE INDEX IF NOT EXISTS "IX_TaskTemplates_Recurrence_NextRun" ON "TaskTemplates" ("RecurrenceType", "NextRunAt");
-- Truyền thông v2: kênh, đính kèm file, xác nhận đọc, bình chọn, lưu bài, hẹn giờ
CREATE TABLE IF NOT EXISTS "CommChannels" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores" ("Id") ON DELETE CASCADE,
    "Key" character varying(40) NULL,
    "Name" character varying(120) NOT NULL,
    "Description" character varying(500) NULL,
    "Icon" character varying(40) NULL,
    "Color" character varying(9) NULL,
    "PostPolicy" integer NOT NULL DEFAULT 0,
    "RequireApproval" boolean NOT NULL DEFAULT false,
    "BranchId" uuid NULL,
    "DepartmentId" uuid NULL,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "IsSystem" boolean NOT NULL DEFAULT false,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text NULL,
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_CommChannels_Store" ON "CommChannels" ("StoreId", "SortOrder");
CREATE TABLE IF NOT EXISTS "CommunicationReads" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "CommunicationId" uuid NOT NULL REFERENCES "InternalCommunications" ("Id") ON DELETE CASCADE,
    "UserId" uuid NOT NULL,
    "EmployeeId" uuid NULL,
    "FirstViewedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "LastViewedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "ViewCount" integer NOT NULL DEFAULT 1,
    "AcknowledgedAt" timestamp without time zone NULL,
    "AckVersion" integer NOT NULL DEFAULT 0,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text NULL,
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_CommunicationReads_Post_User" ON "CommunicationReads" ("CommunicationId", "UserId");
CREATE INDEX IF NOT EXISTS "IX_CommunicationReads_Store_User" ON "CommunicationReads" ("StoreId", "UserId");
CREATE TABLE IF NOT EXISTS "CommunicationPollVotes" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "CommunicationId" uuid NOT NULL REFERENCES "InternalCommunications" ("Id") ON DELETE CASCADE,
    "UserId" uuid NOT NULL,
    "OptionId" character varying(40) NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text NULL,
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_CommunicationPollVotes_Post_User_Option" ON "CommunicationPollVotes" ("CommunicationId", "UserId", "OptionId");
CREATE TABLE IF NOT EXISTS "CommunicationBookmarks" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "CommunicationId" uuid NOT NULL REFERENCES "InternalCommunications" ("Id") ON DELETE CASCADE,
    "UserId" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text NULL,
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_CommunicationBookmarks_Post_User" ON "CommunicationBookmarks" ("CommunicationId", "UserId");
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "ChannelId" uuid NULL REFERENCES "CommChannels" ("Id") ON DELETE SET NULL;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "ContentFormat" character varying(10) NULL;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "ContentDelta" text NULL;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "Attachments" text NULL;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "RequireAck" boolean NOT NULL DEFAULT false;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "AckDeadline" timestamp without time zone NULL;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "Version" integer NOT NULL DEFAULT 1;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "Audience" text NULL;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "Poll" text NULL;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "EventAt" timestamp without time zone NULL;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "EventLocation" character varying(300) NULL;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "ScheduledAt" timestamp without time zone NULL;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "AllowComments" boolean NOT NULL DEFAULT true;
CREATE INDEX IF NOT EXISTS "IX_InternalCommunications_Store_Channel" ON "InternalCommunications" ("StoreId", "ChannelId", "PublishedAt");
-- Tài chính nhân sự v2: liên kết chuẩn phiếu thu/chi ↔ chứng từ gốc, khiếu nại, trừ dần ứng lương
ALTER TABLE "CashTransactions" ADD COLUMN IF NOT EXISTS "SourceType" character varying(30) NULL;
ALTER TABLE "CashTransactions" ADD COLUMN IF NOT EXISTS "SourceId" uuid NULL;
ALTER TABLE "CashTransactions" ADD COLUMN IF NOT EXISTS "EmployeeId" uuid NULL;
ALTER TABLE "CashTransactions" ADD COLUMN IF NOT EXISTS "Attachments" text NULL;
ALTER TABLE "PaymentTransactions" ADD COLUMN IF NOT EXISTS "Source" character varying(20) NULL;
ALTER TABLE "PaymentTransactions" ADD COLUMN IF NOT EXISTS "Settlement" character varying(10) NULL;
ALTER TABLE "PaymentTransactions" ADD COLUMN IF NOT EXISTS "CashTransactionId" uuid NULL;
ALTER TABLE "PaymentTransactions" ADD COLUMN IF NOT EXISTS "EvidenceUrls" text NULL;
ALTER TABLE "PaymentTransactions" ADD COLUMN IF NOT EXISTS "DisputeStatus" integer NOT NULL DEFAULT 0;
ALTER TABLE "PaymentTransactions" ADD COLUMN IF NOT EXISTS "DisputeReason" character varying(1000) NULL;
ALTER TABLE "PaymentTransactions" ADD COLUMN IF NOT EXISTS "DisputedAt" timestamp without time zone NULL;
ALTER TABLE "PaymentTransactions" ADD COLUMN IF NOT EXISTS "DisputeResponse" character varying(1000) NULL;
ALTER TABLE "PenaltyTickets" ADD COLUMN IF NOT EXISTS "EvidenceUrls" text NULL;
ALTER TABLE "PenaltyTickets" ADD COLUMN IF NOT EXISTS "DisputeStatus" integer NOT NULL DEFAULT 0;
ALTER TABLE "PenaltyTickets" ADD COLUMN IF NOT EXISTS "DisputeReason" character varying(1000) NULL;
ALTER TABLE "PenaltyTickets" ADD COLUMN IF NOT EXISTS "DisputedAt" timestamp without time zone NULL;
ALTER TABLE "PenaltyTickets" ADD COLUMN IF NOT EXISTS "DisputeResponse" character varying(1000) NULL;
ALTER TABLE "AdvanceRequests" ADD COLUMN IF NOT EXISTS "InstallmentCount" integer NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS "HrFinanceSettings" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores" ("Id") ON DELETE CASCADE,
    "AdvanceLimitPercent" numeric(9,2) NULL,
    "AdvanceLimitAmount" numeric(18,2) NULL,
    "AdvanceMaxRequestsPerPeriod" integer NULL,
    "AdvanceMaxInstallments" integer NOT NULL DEFAULT 3,
    "BonusDefaultSettlement" character varying(10) NOT NULL DEFAULT 'salary',
    "PenaltyDefaultSettlement" character varying(10) NOT NULL DEFAULT 'salary',
    "DisputeWindowDays" integer NOT NULL DEFAULT 7,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text NULL,
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_HrFinanceSettings_Store" ON "HrFinanceSettings" ("StoreId") WHERE "Deleted" IS NULL;
UPDATE "CashTransactions" SET "SourceType" = 'advance', "SourceId" = CAST(substring("InternalNote" from 'ứng lương #([0-9a-fA-F-]{36})') AS uuid) WHERE "SourceId" IS NULL AND "InternalNote" ~ 'ứng lương #[0-9a-fA-F-]{36}';
UPDATE "CashTransactions" SET "SourceType" = 'reward', "SourceId" = CAST(substring("InternalNote" from 'thưởng/phạt #([0-9a-fA-F-]{36})') AS uuid) WHERE "SourceId" IS NULL AND "InternalNote" ~ 'thưởng/phạt #[0-9a-fA-F-]{36}';
UPDATE "CashTransactions" SET "SourceType" = 'trip_refund', "SourceId" = CAST(substring("InternalNote" from 'thu hoàn ứng công tác #([0-9a-fA-F-]{36})') AS uuid) WHERE "SourceId" IS NULL AND "InternalNote" ~ 'thu hoàn ứng công tác #[0-9a-fA-F-]{36}';
UPDATE "CashTransactions" SET "SourceType" = 'trip_settlement', "SourceId" = CAST(substring("InternalNote" from 'quyết toán công tác phí #([0-9a-fA-F-]{36})') AS uuid) WHERE "SourceId" IS NULL AND "InternalNote" ~ 'quyết toán công tác phí #[0-9a-fA-F-]{36}';
UPDATE "CashTransactions" SET "SourceType" = 'trip_advance', "SourceId" = CAST(substring("InternalNote" from 'ứng công tác #([0-9a-fA-F-]{36})') AS uuid) WHERE "SourceId" IS NULL AND "InternalNote" ~ 'ứng công tác #[0-9a-fA-F-]{36}';
UPDATE "CashTransactions" c SET "SourceType" = 'penalty_ticket', "SourceId" = t."Id", "EmployeeId" = t."EmployeeId" FROM "PenaltyTickets" t WHERE t."CashTransactionId" = c."Id" AND c."SourceId" IS NULL;
UPDATE "CashTransactions" c SET "SourceType" = 'trip_advance', "SourceId" = a."Id" FROM "BusinessTripAdvanceClaims" a WHERE a."CashTransactionId" = c."Id" AND c."SourceId" IS NULL;
UPDATE "CashTransactions" c SET "SourceType" = 'trip_settlement', "SourceId" = s."Id" FROM "BusinessTripSettlementClaims" s WHERE s."ExtraCashTransactionId" = c."Id" AND c."SourceId" IS NULL;
UPDATE "CashTransactions" c SET "EmployeeId" = a."EmployeeId" FROM "AdvanceRequests" a WHERE c."SourceType" = 'advance' AND c."SourceId" = a."Id" AND c."EmployeeId" IS NULL;
UPDATE "CashTransactions" c SET "EmployeeId" = p."EmployeeId" FROM "PaymentTransactions" p WHERE c."SourceType" = 'reward' AND c."SourceId" = p."Id" AND c."EmployeeId" IS NULL;
UPDATE "PaymentTransactions" SET "Source" = 'manual' WHERE "Source" IS NULL AND "Type" IN ('Bonus', 'Penalty');
CREATE UNIQUE INDEX IF NOT EXISTS "UX_CashTransactions_Source" ON "CashTransactions" ("StoreId", "SourceType", "SourceId") WHERE "SourceId" IS NOT NULL AND "IsActive" = true AND "Deleted" IS NULL;
CREATE INDEX IF NOT EXISTS "IX_CashTransactions_Store_Employee" ON "CashTransactions" ("StoreId", "EmployeeId") WHERE "EmployeeId" IS NOT NULL;
-- Duyệt chấm công v2: chấm điểm rủi ro, lý do ngoài vị trí, tự duyệt tin cậy, hạn giữ ảnh bằng chứng
ALTER TABLE "MobileAttendanceRecords" ADD COLUMN IF NOT EXISTS "IsOutside" boolean NOT NULL DEFAULT false;
ALTER TABLE "MobileAttendanceRecords" ADD COLUMN IF NOT EXISTS "OutsideReason" character varying(500) NULL;
ALTER TABLE "MobileAttendanceRecords" ADD COLUMN IF NOT EXISTS "GpsAccuracy" double precision NULL;
ALTER TABLE "MobileAttendanceRecords" ADD COLUMN IF NOT EXISTS "RiskScore" integer NOT NULL DEFAULT 0;
ALTER TABLE "MobileAttendanceRecords" ADD COLUMN IF NOT EXISTS "RiskLevel" character varying(10) NULL;
ALTER TABLE "MobileAttendanceRecords" ADD COLUMN IF NOT EXISTS "RiskFlags" text NULL;
ALTER TABLE "MobileAttendanceRecords" ADD COLUMN IF NOT EXISTS "EvidencePurgedAt" timestamp without time zone NULL;
ALTER TABLE "AuthorizedMobileDevices" ADD COLUMN IF NOT EXISTS "RequireOutsideReason" boolean NOT NULL DEFAULT false;
ALTER TABLE "MobileAttendanceSettings" ADD COLUMN IF NOT EXISTS "AutoApproveTrusted" boolean NOT NULL DEFAULT true;
ALTER TABLE "MobileAttendanceSettings" ADD COLUMN IF NOT EXISTS "TrustedMaxDistanceMeters" integer NOT NULL DEFAULT 300;
ALTER TABLE "MobileAttendanceSettings" ADD COLUMN IF NOT EXISTS "TrustedMinFaceScore" double precision NOT NULL DEFAULT 85;
ALTER TABLE "MobileAttendanceSettings" ADD COLUMN IF NOT EXISTS "EvidenceRetentionDays" integer NOT NULL DEFAULT 30;
UPDATE "MobileAttendanceRecords" SET "IsOutside" = true WHERE "IsOutside" = false AND "Status" = 'pending' AND "WifiBssid" IS NULL AND "DistanceFromLocation" IS NOT NULL AND "DistanceFromLocation" > 100;
CREATE INDEX IF NOT EXISTS "IX_MobileAttendanceRecords_Store_Status_Punch" ON "MobileAttendanceRecords" ("StoreId", "Status", "PunchTime");
-- Quản trị gói dịch vụ v2: giá, dòng sản phẩm, chức năng riêng theo cửa hàng
ALTER TABLE "ServicePackages" ADD COLUMN IF NOT EXISTS "ProductLine" character varying(10) NOT NULL DEFAULT 'both';
ALTER TABLE "ServicePackages" ADD COLUMN IF NOT EXISTS "MonthlyPrice" numeric(18,2) NULL;
ALTER TABLE "ServicePackages" ADD COLUMN IF NOT EXISTS "YearlyPrice" numeric(18,2) NULL;
ALTER TABLE "ServicePackages" ADD COLUMN IF NOT EXISTS "TrialDays" integer NOT NULL DEFAULT 0;
ALTER TABLE "ServicePackages" ADD COLUMN IF NOT EXISTS "SortOrder" integer NOT NULL DEFAULT 0;
ALTER TABLE "ServicePackages" ADD COLUMN IF NOT EXISTS "IsFeatured" boolean NOT NULL DEFAULT false;
ALTER TABLE "ServicePackages" ADD COLUMN IF NOT EXISTS "Badge" character varying(40) NULL;
ALTER TABLE "ServicePackages" ADD COLUMN IF NOT EXISTS "Highlights" text NULL;
ALTER TABLE "Stores" ADD COLUMN IF NOT EXISTS "ExtraModules" text NULL;
ALTER TABLE "Stores" ADD COLUMN IF NOT EXISTS "BlockedModules" text NULL;
ALTER TABLE "Stores" ADD COLUMN IF NOT EXISTS "AdminNote" text NULL;
-- Chức năng đã cấp quyền vai trò lần gần nhất — phát hiện chức năng mới thêm vào gói (StorePermissionSyncHelper).
ALTER TABLE "Stores" ADD COLUMN IF NOT EXISTS "PermissionSyncedModules" text NULL;
CREATE TABLE IF NOT EXISTS "SchemaPatchMarkers" ("Key" character varying(100) NOT NULL PRIMARY KEY, "AppliedAt" timestamp without time zone NOT NULL DEFAULT NOW());
-- Chạy 1 lần (đánh dấu pkg_modules_v2). Chấm công Mobile chuyển thành chức năng chọn theo gói: giữ nguyên cho gói đang có chấm công
UPDATE "ServicePackages" SET "AllowedModules" = ("AllowedModules"::jsonb || '["MobileAttendance"]'::jsonb)::text WHERE "AllowedModules" LIKE '[%' AND "AllowedModules" LIKE '%Attendance%' AND "AllowedModules" NOT LIKE '%"MobileAttendance"%' AND NOT EXISTS (SELECT 1 FROM "SchemaPatchMarkers" WHERE "Key" = 'pkg_modules_v2');
-- Trợ lý AI thành chức năng riêng: giữ nguyên cho mọi gói hiện có (Super Admin có thể bỏ tick)
UPDATE "ServicePackages" SET "AllowedModules" = ("AllowedModules"::jsonb || '["AIAssistant"]'::jsonb)::text WHERE "AllowedModules" LIKE '[%' AND "AllowedModules" <> '[]' AND "AllowedModules" NOT LIKE '%"AIAssistant"%' AND NOT EXISTS (SELECT 1 FROM "SchemaPatchMarkers" WHERE "Key" = 'pkg_modules_v2');
INSERT INTO "SchemaPatchMarkers" ("Key") VALUES ('pkg_modules_v2') ON CONFLICT ("Key") DO NOTHING;
-- Đăng ký thiết bị chấm công: lưu lý do từ chối để nhân viên xem và đăng ký lại
ALTER TABLE "AuthorizedMobileDevices" ADD COLUMN IF NOT EXISTS "RejectionReason" character varying(500) NULL;
ALTER TABLE "AuthorizedMobileDevices" ADD COLUMN IF NOT EXISTS "RejectedAt" timestamp without time zone NULL;
-- Quá trình công tác: khen thưởng, kỷ luật, điều chuyển / bổ nhiệm (gắn theo hồ sơ nhân viên)
CREATE TABLE IF NOT EXISTS "EmployeeCareerRecords" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores" ("Id") ON DELETE CASCADE,
    "EmployeeId" uuid NOT NULL REFERENCES "Employees" ("Id") ON DELETE CASCADE,
    "Kind" character varying(20) NOT NULL DEFAULT 'award',
    "Title" character varying(500) NOT NULL DEFAULT '',
    "Form" character varying(100) NULL,
    "DecisionNumber" character varying(100) NULL,
    "EffectiveDate" timestamp without time zone NOT NULL,
    "EndDate" timestamp without time zone NULL,
    "IssuedBy" character varying(200) NULL,
    "Amount" numeric(18,2) NULL,
    "Note" character varying(2000) NULL,
    "AttachmentUrls" text NULL,
    "OrgAssignmentId" uuid NULL,
    "FromDepartment" character varying(200) NULL,
    "ToDepartment" character varying(200) NULL,
    "FromPosition" character varying(200) NULL,
    "ToPosition" character varying(200) NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text NULL,
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_EmployeeCareerRecords_Employee" ON "EmployeeCareerRecords" ("StoreId", "EmployeeId", "EffectiveDate");

-- Phép năm: chính sách cửa hàng + sổ phép (điều chỉnh / chuyển phép / trả tiền).
CREATE TABLE IF NOT EXISTS "AnnualLeavePolicies" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores" ("Id") ON DELETE CASCADE,
    "DefaultDays" numeric(6,2) NOT NULL DEFAULT 12,
    "ApplyTo" character varying(20) NOT NULL DEFAULT 'monthly',
    "SeniorityEveryYears" integer NOT NULL DEFAULT 5,
    "SeniorityDays" numeric(6,2) NOT NULL DEFAULT 1,
    "ProrateByMonths" boolean NOT NULL DEFAULT true,
    "ProrateCutoffDay" integer NOT NULL DEFAULT 15,
    "YearEndMode" character varying(20) NOT NULL DEFAULT 'carry',
    "CarryMaxDays" numeric(6,2) NULL DEFAULT 12,
    "CarryExpireMonth" integer NOT NULL DEFAULT 3,
    "PayoutBasis" character varying(30) NOT NULL DEFAULT 'base',
    "PayoutStandardDays" numeric(6,2) NOT NULL DEFAULT 26,
    "CountWorkingDaysOnly" boolean NOT NULL DEFAULT true,
    "AllowNegative" boolean NOT NULL DEFAULT false,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text NULL,
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "UX_AnnualLeavePolicies_Store" ON "AnnualLeavePolicies" ("StoreId") WHERE "Deleted" IS NULL;

CREATE TABLE IF NOT EXISTS "AnnualLeaveEntries" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores" ("Id") ON DELETE CASCADE,
    "EmployeeId" uuid NOT NULL REFERENCES "Employees" ("Id") ON DELETE CASCADE,
    "Year" integer NOT NULL,
    "Kind" character varying(20) NOT NULL DEFAULT 'adjust',
    "Days" numeric(8,2) NOT NULL DEFAULT 0,
    "Amount" numeric(18,2) NULL,
    "DailyRate" numeric(18,2) NULL,
    "PayrollMonth" timestamp without time zone NULL,
    "Note" character varying(1000) NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text NULL,
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_AnnualLeaveEntries_Employee" ON "AnnualLeaveEntries" ("StoreId", "EmployeeId", "Year");
CREATE INDEX IF NOT EXISTS "IX_AnnualLeaveEntries_Payroll" ON "AnnualLeaveEntries" ("StoreId", "PayrollMonth");
-- Truyền thông: mỗi người một cảm xúc / bài (dọn bản trùng trước khi tạo chỉ mục duy nhất), thích bình luận
DELETE FROM "CommunicationReactions" r USING "CommunicationReactions" o
WHERE r."CommunicationId" = o."CommunicationId" AND r."UserId" = o."UserId"
  AND (r."CreatedAt" < o."CreatedAt" OR (r."CreatedAt" = o."CreatedAt" AND r."Id" < o."Id"));
CREATE UNIQUE INDEX IF NOT EXISTS "IX_CommunicationReactions_Post_User" ON "CommunicationReactions" ("CommunicationId", "UserId");
CREATE INDEX IF NOT EXISTS "IX_CommunicationComments_Post_Created" ON "CommunicationComments" ("CommunicationId", "CreatedAt");
CREATE INDEX IF NOT EXISTS "IX_InternalCommunications_Store_Status_Published" ON "InternalCommunications" ("StoreId", "Status", "PublishedAt");
CREATE TABLE IF NOT EXISTS "CommunicationCommentLikes" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "CommentId" uuid NOT NULL REFERENCES "CommunicationComments" ("Id") ON DELETE CASCADE,
    "UserId" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text NULL,
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_CommunicationCommentLikes_Comment_User" ON "CommunicationCommentLikes" ("CommentId", "UserId");
-- FCM: gắn token với mã thiết bị truy cập (thu hồi thiết bị → ngừng đẩy thông báo tới máy đó)
ALTER TABLE "UserDeviceTokens" ADD COLUMN IF NOT EXISTS "DeviceKey" character varying(80) NULL;
CREATE INDEX IF NOT EXISTS "IX_UserDeviceTokens_DeviceKey" ON "UserDeviceTokens" ("DeviceKey");
-- Trả lương nhiều lần / nhiều phương thức: số đã trả trên phiếu lương
ALTER TABLE "Payslips" ADD COLUMN IF NOT EXISTS "PaidAmount" numeric(18,2) NOT NULL DEFAULT 0;
UPDATE "Payslips" SET "PaidAmount" = "NetSalary" WHERE "Status" = 3 AND "PaidAmount" = 0 AND "NetSalary" > 0;
CREATE INDEX IF NOT EXISTS "IX_CashTransactions_Source" ON "CashTransactions" ("SourceType", "SourceId");
UPDATE "CashTransactions" SET "SourceType" = 'payslip', "SourceId" = CAST(substring("InternalNote" from 'phiếu lương #([0-9a-fA-F-]{36})') AS uuid) WHERE "SourceId" IS NULL AND "InternalNote" ~ 'phiếu lương #[0-9a-fA-F-]{36}';
-- Phụ cấp theo ngày / theo ca: điều kiện số giờ làm trong ca
ALTER TABLE "Allowances" ADD COLUMN IF NOT EXISTS "MinWorkPercent" numeric(5,2) NULL;
ALTER TABLE "Allowances" ADD COLUMN IF NOT EXISTS "MinWorkHours" numeric(5,2) NULL;
