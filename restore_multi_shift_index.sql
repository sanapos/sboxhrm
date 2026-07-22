DROP INDEX IF EXISTS ""IX_WorkSchedules_Employee_Date"";
DROP INDEX IF EXISTS ""IX_WorkSchedules_Employee_Date_Shift"";
CREATE UNIQUE INDEX IF NOT EXISTS ""IX_WorkSchedules_Employee_Date_Shift""
  ON ""WorkSchedules"" (""EmployeeId"", ""Date"", ""ShiftId"");
