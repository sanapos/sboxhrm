
// ==========================================
// src/services/deviceService.ts
// ==========================================
import { apiService } from './api';
import type { Device, CreateDeviceRequest, DeviceInfo } from '@/types';

export const deviceService = {
  getAll: async () => {
    return  await apiService.get<Device[]>('/api/devices')
  },

  getByUserId: async (userId: string) => {
    return await apiService.get<Device[]>(`/api/devices/users/${userId}`)
  },
  
  getById: (id: string) => apiService.get<Device>(`/api/devices/${id}`),
  
  create: async (data: CreateDeviceRequest) => {
    return await apiService.post<Device>('/api/devices', data);
  },
  
  delete: (id: string) => apiService.delete<boolean>(`/api/devices/${id}`),

  toggleActive: (id: string) => 
    apiService.put<Device>(`/api/devices/${id}/toggle-active`),
  
  getDeviceInfo: async (deviceId: string) => {
    return await apiService.get<DeviceInfo>(`/api/devices/${deviceId}/device-info`);
  },
};