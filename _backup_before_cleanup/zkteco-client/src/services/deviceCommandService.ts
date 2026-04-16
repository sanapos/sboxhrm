
// ==========================================
// src/services/attendanceService.ts
// ==========================================
import { DeviceCommandRequest } from '@/types/device';
import { apiService } from './api';
import type { DeviceCommand } from '@/types';

export const deviceCommandService = {
  getByDevice: (deviceId: string) => {
    return apiService.get<DeviceCommand[]>(`/api/devices/${deviceId}/commands`);
  },
  createDeviceCommand: (deviceId: string, data: DeviceCommandRequest) => 
    apiService.post<DeviceCommand>(`/api/devices/${deviceId}/commands`, data),

};