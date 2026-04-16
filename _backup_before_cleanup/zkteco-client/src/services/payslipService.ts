import { apiService } from './api';
import { Payslip, GeneratePayslipRequest } from '@/types/payslip';

export const payslipService = {
  // Get employee's payslips (or current user's if no employeeUserId provided)
  getPayslips: async (employeeUserId?: string): Promise<Payslip[]> => {
    const endpoint = employeeUserId 
      ? `/api/payslips/employee/${employeeUserId}`
      : '/api/payslips/my-payslips';
    
    return await apiService.get<Payslip[]>(endpoint);
  },

  // Get a specific payslip by ID
  getPayslipById: async (id: string): Promise<Payslip> => {
    return await apiService.get<Payslip>(`/api/payslips/${id}`);
  },

  // Generate a payslip
  generatePayslip: async (data: GeneratePayslipRequest): Promise<Payslip> => {
    return await apiService.post<Payslip>('/api/payslips/generate', data);
  },
};
