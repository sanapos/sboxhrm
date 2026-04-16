// ============ PENALTY SETTING TYPES ============

export interface PenaltySetting {
  id: string;
  name: string;
  description?: string;
  isLatePolicy: boolean; // true = đi muộn, false = về sớm
  level: number;
  minMinutes: number;
  maxMinutes: number;
  penaltyAmount: number;
  isPercentage: boolean;
  isActive: boolean;
  createdAt: string;
  updatedAt?: string;
}

export interface CreatePenaltySettingRequest {
  name: string;
  description?: string;
  isLatePolicy: boolean;
  level: number;
  minMinutes: number;
  maxMinutes: number;
  penaltyAmount: number;
  isPercentage: boolean;
}

export interface UpdatePenaltySettingRequest {
  name: string;
  description?: string;
  minMinutes: number;
  maxMinutes: number;
  penaltyAmount: number;
  isPercentage: boolean;
  isActive: boolean;
}

// ============ INSURANCE SETTING TYPES ============

export interface InsuranceSetting {
  id: string;
  code: string; // BHXH, BHYT, BHTN
  name: string;
  description?: string;
  employeeRate: number;
  employerRate: number;
  maxSalaryBase?: number;
  isActive: boolean;
  createdAt: string;
  updatedAt?: string;
}

export interface CreateInsuranceSettingRequest {
  code: string;
  name: string;
  description?: string;
  employeeRate: number;
  employerRate: number;
  maxSalaryBase?: number;
}

export interface UpdateInsuranceSettingRequest {
  name: string;
  description?: string;
  employeeRate: number;
  employerRate: number;
  maxSalaryBase?: number;
  isActive: boolean;
}

// ============ TAX SETTING TYPES ============

export interface TaxSetting {
  id: string;
  name: string;
  description?: string;
  level: number;
  minIncome: number;
  maxIncome?: number;
  taxRate: number;
  deductionAmount: number;
  isActive: boolean;
  createdAt: string;
  updatedAt?: string;
}

export interface CreateTaxSettingRequest {
  name: string;
  description?: string;
  level: number;
  minIncome: number;
  maxIncome?: number;
  taxRate: number;
  deductionAmount: number;
}

export interface UpdateTaxSettingRequest {
  name: string;
  description?: string;
  minIncome: number;
  maxIncome?: number;
  taxRate: number;
  deductionAmount: number;
  isActive: boolean;
}

// ============ TAX CALCULATION TYPES ============

export interface TaxCalculationRequest {
  grossIncome: number;
  totalInsurance: number;
  personalDeduction: number;
  numberOfDependents: number;
  dependentDeductionPerPerson: number;
}

export interface TaxBracketCalculation {
  level: number;
  taxRate: number;
  taxableAmount: number;
  taxAmount: number;
}

export interface TaxCalculation {
  grossIncome: number;
  totalInsurance: number;
  personalDeduction: number;
  dependentDeduction: number;
  taxableIncome: number;
  taxAmount: number;
  netIncome: number;
  taxBrackets: TaxBracketCalculation[];
}

// ============ PAYMENT TRANSACTION TYPES ============

export interface PaymentTransaction {
  id: string;
  transactionCode: string;
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  amount: number;
  isIncome: boolean;
  paymentMethod?: string;
  bankAccount?: string;
  bankName?: string;
  transactionDate: string;
  month: number;
  year: number;
  payslipId?: string;
  advanceRequestId?: string;
  description?: string;
  notes?: string;
  processedBy?: string;
  processedByName?: string;
  createdAt: string;
  updatedAt?: string;
}

export interface CreatePaymentTransactionRequest {
  employeeId: string;
  amount: number;
  isIncome: boolean;
  paymentMethod?: string;
  bankAccount?: string;
  bankName?: string;
  transactionDate: string;
  month: number;
  year: number;
  payslipId?: string;
  advanceRequestId?: string;
  description?: string;
  notes?: string;
}

export interface SalaryPaymentRequest {
  payslipId: string;
  paymentMethod?: string;
  bankAccount?: string;
  bankName?: string;
  notes?: string;
}

export interface BulkSalaryPaymentRequest {
  payslipIds: string[];
  paymentMethod?: string;
  notes?: string;
}

export interface PaymentTransactionQueryParams {
  page?: number;
  pageSize?: number;
  employeeId?: string;
  isIncome?: boolean;
  month?: number;
  year?: number;
  fromDate?: string;
  toDate?: string;
  searchTerm?: string;
}

export interface PaymentSummary {
  month: number;
  year: number;
  totalIncome: number;
  totalExpense: number;
  balance: number;
  totalTransactions: number;
  employeesPaid: number;
  totalAdvancePaid: number;
}

export interface EmployeePaymentSummary {
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  totalSalaryPaid: number;
  totalAdvancePaid: number;
  totalDeductions: number;
  netPaid: number;
  transactions: PaymentTransaction[];
}
