
// ==========================================
// src/services/usersService.ts
// ==========================================
import { CreateDeviceUserRequest, UpdateDeviceUserRequest } from '@/types/deviceUser';
import { apiService } from './api';
import type { DeviceUser } from '@/types/deviceUser';
import { Employee } from '@/types/employee';

export const deviceUserService = {
  getEmployeesByDevices: async (deviceIds?: string[]) => {
    return await apiService.post<DeviceUser[]>('/api/deviceUsers/devices', { deviceIds })
  },
  
  getById: (id: string) => apiService.get<DeviceUser>(`/api/deviceUsers/${id}`),
  
  getByPin: (pin: string) => apiService.get<DeviceUser>(`/api/deviceUsers/pin/${pin}`),
  
  create: async (data: CreateDeviceUserRequest) => {
    return await apiService.post<DeviceUser>('/api/deviceUsers', data)
  },
  
  update: (data: UpdateDeviceUserRequest) => 
    apiService.put<DeviceUser>(`/api/deviceUsers/${data.userId}`, data),

  delete: (id: string) => apiService.delete<string>(`/api/deviceUsers/${id}`),

  mapToEmployee: (deviceUserId: string, employeeId: string) =>
    apiService.post<Employee>(`/api/deviceUsers/${deviceUserId}/map-employee/${employeeId}`),
};