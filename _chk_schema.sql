-- Check columns used across report controllers
SELECT table_name, column_name FROM information_schema.columns 
WHERE table_name IN ('Employees','Payslips','LeaveRequests','ShiftSwaps','MobileAttendanceRecords','FieldVisitReports','Attendances','Assets','KpiRecords','ProductionRecords','Penalties','SalaryAdvances','MealDebts','Holidays','Shifts','EmployeeShifts')
ORDER BY table_name, ordinal_position;
