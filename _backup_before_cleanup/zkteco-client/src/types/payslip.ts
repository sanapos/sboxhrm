export enum PayslipStatus {
  Draft = 0,
  PendingApproval = 1,
  Approved = 2,
  Paid = 3,
  Cancelled = 4
}

export interface Payslip {
  id: string;
  employeeUserId: string;
  employeeName: string;
  salaryProfileId: string;
  salaryProfileName: string;
  year: number;
  month: number;
  periodStart: string;
  periodEnd: string;
  regularWorkUnits: number;
  overtimeUnits?: number;
  holidayUnits?: number;
  nightShiftUnits?: number;
  baseSalary: number;
  overtimePay?: number;
  holidayPay?: number;
  nightShiftPay?: number;
  bonus?: number;
  deductions?: number;
  grossSalary: number;
  netSalary: number;
  currency: string;
  status: PayslipStatus;
  statusName: string;
  generatedDate?: string;
  generatedByUserName?: string;
  approvedDate?: string;
  approvedByUserName?: string;
  paidDate?: string;
  notes?: string;
  createdAt: string;
}

export interface GeneratePayslipRequest {
  employeeUserId: string;
  year: number;
  month: number;
  bonus?: number;
  deductions?: number;
  notes?: string;
}
