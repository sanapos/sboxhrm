import { apiService, buildQueryParams } from './api';
import { PaginatedResponse } from '../types';
import {
  PenaltySetting,
  CreatePenaltySettingRequest,
  UpdatePenaltySettingRequest,
  InsuranceSetting,
  CreateInsuranceSettingRequest,
  UpdateInsuranceSettingRequest,
  TaxSetting,
  CreateTaxSettingRequest,
  UpdateTaxSettingRequest,
  TaxCalculationRequest,
  TaxCalculation,
  PaymentTransaction,
  CreatePaymentTransactionRequest,
  SalaryPaymentRequest,
  BulkSalaryPaymentRequest,
  PaymentTransactionQueryParams,
  PaymentSummary,
  EmployeePaymentSummary,
} from '../types/settings';

// ============ PENALTY SETTING SERVICE ============
export const penaltySettingService = {
  // Get all penalty settings
  getAll: async () => {
    return await apiService.get<PenaltySetting[]>('/api/settings/penalties');
  },

  // Get active penalty settings
  getActive: async () => {
    return await apiService.get<PenaltySetting[]>('/api/settings/penalties/active');
  },

  // Get late policies
  getLatePolicies: async () => {
    return await apiService.get<PenaltySetting[]>('/api/settings/penalties?isLatePolicy=true');
  },

  // Get early leave policies
  getEarlyLeavePolicies: async () => {
    return await apiService.get<PenaltySetting[]>('/api/settings/penalties?isLatePolicy=false');
  },

  // Get by id
  getById: async (id: string) => {
    return await apiService.get<PenaltySetting>(`/api/settings/penalties/${id}`);
  },

  // Create
  create: async (data: CreatePenaltySettingRequest) => {
    return await apiService.post<PenaltySetting>('/api/settings/penalties', data);
  },

  // Update
  update: async (id: string, data: UpdatePenaltySettingRequest) => {
    return await apiService.put<PenaltySetting>(`/api/settings/penalties/${id}`, data);
  },

  // Delete
  delete: async (id: string) => {
    return await apiService.delete(`/api/settings/penalties/${id}`);
  },

  // Toggle active
  toggleActive: async (id: string) => {
    return await apiService.post<PenaltySetting>(`/api/settings/penalties/${id}/toggle`, {});
  },

  // Calculate penalty for late/early leave
  calculatePenalty: async (minutes: number, isLate: boolean) => {
    return await apiService.get<{ penaltyAmount: number; penaltyLevel: number }>(
      `/api/settings/penalties/calculate?minutes=${minutes}&isLate=${isLate}`
    );
  },
};

// ============ INSURANCE SETTING SERVICE ============
export const insuranceSettingService = {
  // Get all insurance settings
  getAll: async () => {
    return await apiService.get<InsuranceSetting[]>('/api/settings/insurance');
  },

  // Get active insurance settings
  getActive: async () => {
    return await apiService.get<InsuranceSetting[]>('/api/settings/insurance/active');
  },

  // Get by id
  getById: async (id: string) => {
    return await apiService.get<InsuranceSetting>(`/api/settings/insurance/${id}`);
  },

  // Get by code (BHXH, BHYT, BHTN)
  getByCode: async (code: string) => {
    return await apiService.get<InsuranceSetting>(`/api/settings/insurance/code/${code}`);
  },

  // Create
  create: async (data: CreateInsuranceSettingRequest) => {
    return await apiService.post<InsuranceSetting>('/api/settings/insurance', data);
  },

  // Update
  update: async (id: string, data: UpdateInsuranceSettingRequest) => {
    return await apiService.put<InsuranceSetting>(`/api/settings/insurance/${id}`, data);
  },

  // Delete
  delete: async (id: string) => {
    return await apiService.delete(`/api/settings/insurance/${id}`);
  },

  // Toggle active
  toggleActive: async (id: string) => {
    return await apiService.post<InsuranceSetting>(`/api/settings/insurance/${id}/toggle`, {});
  },

  // Calculate insurance for salary
  calculateInsurance: async (baseSalary: number) => {
    return await apiService.get<{
      bhxh: { employee: number; employer: number };
      bhyt: { employee: number; employer: number };
      bhtn: { employee: number; employer: number };
      totalEmployee: number;
      totalEmployer: number;
    }>(`/api/settings/insurance/calculate?baseSalary=${baseSalary}`);
  },
};

// ============ TAX SETTING SERVICE ============
export const taxSettingService = {
  // Get all tax settings
  getAll: async () => {
    return await apiService.get<TaxSetting[]>('/api/settings/tax');
  },

  // Get active tax settings
  getActive: async () => {
    return await apiService.get<TaxSetting[]>('/api/settings/tax/active');
  },

  // Get by id
  getById: async (id: string) => {
    return await apiService.get<TaxSetting>(`/api/settings/tax/${id}`);
  },

  // Create
  create: async (data: CreateTaxSettingRequest) => {
    return await apiService.post<TaxSetting>('/api/settings/tax', data);
  },

  // Update
  update: async (id: string, data: UpdateTaxSettingRequest) => {
    return await apiService.put<TaxSetting>(`/api/settings/tax/${id}`, data);
  },

  // Delete
  delete: async (id: string) => {
    return await apiService.delete(`/api/settings/tax/${id}`);
  },

  // Toggle active
  toggleActive: async (id: string) => {
    return await apiService.post<TaxSetting>(`/api/settings/tax/${id}/toggle`, {});
  },

  // Calculate tax
  calculateTax: async (data: TaxCalculationRequest) => {
    return await apiService.post<TaxCalculation>('/api/settings/tax/calculate', data);
  },
};

// ============ PAYMENT TRANSACTION SERVICE ============
export const paymentTransactionService = {
  // Get all transactions
  getAll: async (params?: PaymentTransactionQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<PaymentTransaction>>(
      '/api/transactions' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get my transactions
  getMyTransactions: async (params?: PaymentTransactionQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<PaymentTransaction>>(
      '/api/transactions/my' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get by employee
  getByEmployee: async (employeeId: string, params?: PaymentTransactionQueryParams) => {
    const queryString = buildQueryParams({ ...params, employeeId });
    return await apiService.get<PaginatedResponse<PaymentTransaction>>(
      '/api/transactions' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get by id
  getById: async (id: string) => {
    return await apiService.get<PaymentTransaction>(`/api/transactions/${id}`);
  },

  // Create transaction
  create: async (data: CreatePaymentTransactionRequest) => {
    return await apiService.post<PaymentTransaction>('/api/transactions', data);
  },

  // Pay salary from payslip
  paySalary: async (data: SalaryPaymentRequest) => {
    return await apiService.post<PaymentTransaction>('/api/transactions/pay-salary', data);
  },

  // Bulk pay salaries
  bulkPaySalaries: async (data: BulkSalaryPaymentRequest) => {
    return await apiService.post<{ count: number; totalAmount: number }>(
      '/api/transactions/bulk-pay-salaries',
      data
    );
  },

  // Get payment summary for month
  getSummary: async (month: number, year: number) => {
    return await apiService.get<PaymentSummary>(
      `/api/transactions/summary?month=${month}&year=${year}`
    );
  },

  // Get employee payment summary
  getEmployeeSummary: async (employeeId: string, month: number, year: number) => {
    return await apiService.get<EmployeePaymentSummary>(
      `/api/transactions/employee-summary?employeeId=${employeeId}&month=${month}&year=${year}`
    );
  },

  // Export transactions to Excel
  exportToExcel: async (month: number, year: number) => {
    return await apiService.get<Blob>(
      `/api/transactions/export?month=${month}&year=${year}`,
      { responseType: 'blob' }
    );
  },
};
