import { Employee } from "./employee";

export enum SalaryRateType {
  Hourly,
  Monthly,
}

export interface Benefit {
  id: string;
  name: string;
  description?: string;
  rateType: SalaryRateType;
  rateTypeName: string;
  rate: number;
  currency: string;

  overtimeMultiplier?: number;
  holidayMultiplier?: number;
  nightShiftMultiplier?: number;
  // Base Salary Configuration
  standardHoursPerDay?: number;
  
  // Leave & Attendance Rules
  weeklyOffDays?: string;
  paidLeaveDays?: number;
  unpaidLeaveDays?: number;
  // Allowances
  mealAllowance?: number;
  transportAllowance?: number;
  housingAllowance?: number;
  responsibilityAllowance?: number;
  attendanceBonus?: number;
  phoneSkillShiftAllowance?: number;
  // Overtime Configuration
  otRateWeekday?: number;
  otRateWeekend?: number;
  otRateHoliday?: number;
  nightShiftRate?: number;
  otHourLimitPerMonth?: number;
  // Health Insurance
  hasHealthInsurance?: boolean;
  healthInsuranceRate?: number;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;

  employees?: Employee[];

}

export interface EmployeeBenefit {
  id: string;
  employeeId: string;
  employee: Employee;
  benefitId: string;
  benefit?: Benefit;
  effectiveDate: string;
  endDate?: string;
  notes?: string;
  balancedPaidLeaveDays?: number;
  balancedUnpaidLeaveDays?: number;
}

export interface CreateBenefitRequest extends UpdateBenefitRequest {
  rateType: SalaryRateType;
}

export interface UpdateBenefitRequest {
  name: string;
  description?: string;
  rateType: SalaryRateType;
  rate: number;
  currency: string;
  overtimeMultiplier?: number;
  holidayMultiplier?: number;
  nightShiftMultiplier?: number;

  // Base Salary Configuration
  standardHoursPerDay?: number;
  // Leave & Attendance Rules
  weeklyOffDays?: string;
  paidLeaveDays?: number;
  unpaidLeaveDays?: number;
  checkIn?: string;
  checkOut?: string;

  // Allowances
  mealAllowance?: number;
  transportAllowance?: number;
  housingAllowance?: number;
  responsibilityAllowance?: number;
  attendanceBonus?: number;
  phoneSkillShiftAllowance?: number;
  // Overtime Configuration
  otRateWeekday?: number;
  otRateWeekend?: number;
  otRateHoliday?: number;
  nightShiftRate?: number;

  // Health Insurance
  hasHealthInsurance?: boolean;
  healthInsuranceRate?: number;

}

export interface AssignSalaryProfileRequest {
  employeeId: string;
  benefitId: string;
  effectiveDate: string;
  notes?: string;
}


export interface BenefitFormData {
  name: string;
  description?: string;
  rateType: SalaryRateType;
  rate: number;
  currency: string;
  overtimeMultiplier?: number;
  holidayMultiplier?: number;
  nightShiftMultiplier?: number;
  // Base Salary Configuration
  standardHoursPerDay?: number;
  // Leave & Attendance Rules
  weeklyOffDays?: string;
  paidLeaveDays?: number;
  unpaidLeaveDays?: number;
  checkIn?: string;
  checkOut?: string;
  
  // Allowances
  mealAllowance?: number;
  transportAllowance?: number;
  housingAllowance?: number;
  responsibilityAllowance?: number;
  attendanceBonus?: number;
  phoneSkillShiftAllowance?: number;
  // Overtime Configuration
  otRateWeekday?: number;
  otRateWeekend?: number;
  otRateHoliday?: number;
  nightShiftRate?: number;
  
  // Health Insurance
  hasHealthInsurance?: boolean;
  healthInsuranceRate?: number;
  isActive?: boolean;
}