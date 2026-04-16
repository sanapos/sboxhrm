import { apiService } from './api';
import { AssignSalaryProfileRequest, Benefit, CreateBenefitRequest, EmployeeBenefit, UpdateBenefitRequest } from '@/types/benefit';

const benefitService = {
  // Get all salary profiles
  getBenefits: async ( salaryRateType?: number): Promise<Benefit[]> => {
    const params = new URLSearchParams();
    if (salaryRateType !== undefined) params.append('salaryRateType', salaryRateType.toString());

    const queryString = params.toString();
    return await apiService.get<Benefit[]>(`/api/benefits${queryString ? `?${queryString}` : ''}`);
  },

  // Get salary profile by ID
  getBenefitById: async (id: string): Promise<Benefit> => {
    return await apiService.get<Benefit>(`/api/benefits/${id}`);
  },

  // Create new salary profile
  createBenefit: async (request: CreateBenefitRequest): Promise<Benefit> => {
    return await apiService.post<Benefit>('/api/benefits', request);
  },

  // Update salary profile
  updateBenefit: async (id: string, request: UpdateBenefitRequest): Promise<Benefit> => {
    return await apiService.put<Benefit>(`/api/benefits/${id}`, request);
  },

  // Delete salary profile
  deleteBenefit: async (id: string): Promise<boolean> => {
    return await apiService.delete<boolean>(`/api/benefits/${id}`);
  },

  // Assign salary profile to employee
  assignEmployee: async (request: AssignSalaryProfileRequest): Promise<EmployeeBenefit> => {
    return await apiService.post<EmployeeBenefit>('/api/benefits/assign', request);
  },

  // Get employee's active salary profile
  getEmployeeSalaryProfile: async (employeeId: string): Promise<EmployeeBenefit> => {
    return await apiService.get<EmployeeBenefit>(`/api/benefits/employees/${employeeId}`);
  },

  // Get all employee salary profiles
  getEmployeeBenefits: async (): Promise<EmployeeBenefit[]> => {

    return await apiService.get<EmployeeBenefit[]>(
      `/api/benefits/employees`
    );
  }
};

export default benefitService;
