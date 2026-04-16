SELECT t.table_name, 
       CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='Deleted') THEN 'YES' ELSE 'NO' END as has_deleted,
       CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='DeletedBy') THEN 'YES' ELSE 'NO' END as has_deletedby,
       CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='IsActive') THEN 'YES' ELSE 'NO' END as has_isactive,
       CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='LastModified') THEN 'YES' ELSE 'NO' END as has_lastmodified,
       CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='LastModifiedBy') THEN 'YES' ELSE 'NO' END as has_lastmodifiedby
FROM information_schema.tables t
WHERE t.table_schema='public' AND t.table_type='BASE TABLE'
  AND t.table_name IN ('Allowances','Agents','AdvanceRequests','AppSettings','ApprovalFlows','ApprovalSteps','Assets','AssetCategories','AssetInventories','AttendanceCorrectionRequests','AuthorizedMobileDevices','BankAccounts','Benefits','Branches','CashTransactions','Departments','Devices','DeviceUsers','EmployeeBenefits','Employees','Feedbacks','Geofences','Holidays','HrDocuments','InsuranceSettings','KpiConfigs','KpiBonusRules','KpiEmployeeTargets','KpiPeriods','KpiResults','KpiSalaries','Leaves','MealMenus','MealSessions','MobileFaceRegistrations','MobileAttendanceRecords','MobileAttendanceSettings','MobileWorkLocations','OrgAssignments','OrgPositions','Overtimes','PaymentTransactions','PenaltySettings','PenaltyTickets','Payslips','ProductGroups','ProductItems','ProductionEntries','ProductPriceTiers','ScheduleRegistrations','Shifts','ShiftSalaryLevels','ShiftSwapRequests','TaxSettings','TransactionCategories','WorkSchedules','WorkTasks')
ORDER BY t.table_name;
