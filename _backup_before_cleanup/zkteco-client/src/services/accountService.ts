// ==========================================
// src/services/accountService.ts
// ==========================================
import { CreateEmployeeAccountRequest, Account, UpdateEmployeeAccountRequest } from '@/types/account'
import { apiService } from './api'

export const accountService = {
  createUserAccount: async (employeeAccount: CreateEmployeeAccountRequest) => {
    return await apiService.post<Account>(
      '/api/Accounts',
      employeeAccount
    )
  },

  updateUserAccount: async (
    employeeDeviceId: string,
    employeeAccount: UpdateEmployeeAccountRequest
  ) => {
    return await apiService.put<Account>(
      `/api/Accounts/${employeeDeviceId}`,
      employeeAccount
    )
  },

  getEmployeeAccountsByManager: async () => {
    return await apiService.get<Account[]>(
      '/api/Accounts/employees'
    )
  },
}
