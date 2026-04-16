import { apiService } from './api';
import { Employee, CreateEmployeeRequest, UpdateEmployeeRequest } from '@/types/employee';
import { PaginatedResponse } from '@/types';

export interface GetEmployeesParams {
  pageNumber?: number;
  pageSize?: number;
  searchTerm?: string;
  employmentType?: string;
  workStatus?: string;
}

export const employeeService = {
  getEmployees: async (params: GetEmployeesParams = {}) => {
    return apiService.get<PaginatedResponse<Employee>>('/api/employees', params);
  },

  getEmployeeById: async (id: string) => {
    return apiService.get<Employee>(`/api/employees/${id}`);
  },

  createEmployee: async (data: CreateEmployeeRequest) => {
    return apiService.post<string>('/api/employees', data);
  },

  updateEmployee: async (id: string, data: UpdateEmployeeRequest) => {
    return apiService.put<boolean>(`/api/employees/${id}`, data);
  },

  deleteEmployee: async (id: string) => {
    return apiService.delete<boolean>(`/api/employees/${id}`);
  },
};
