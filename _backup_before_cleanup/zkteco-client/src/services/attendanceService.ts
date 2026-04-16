
// ==========================================
// src/services/attendanceService.ts
// ==========================================
import { AttendancesFilterParams, MonthlyAttendanceSummary } from '@/types/attendance';
import { apiService } from './api';
import type { AttendanceLog, PaginatedResponse, PaginationRequest } from '@/types';

const buildQueryString = (params: any) => {
  return Object.entries(params)
    .map(([key, value]) => {
      if (Array.isArray(value)) {
        return value.map(v => `${encodeURIComponent(key)}=${encodeURIComponent(v)}`).join('&');
      }
      return `${encodeURIComponent(key)}=${encodeURIComponent(value as any)}`;
    })
    .join('&');
}

export const attendanceService = {
  getByDevices: (paginationRequest: PaginationRequest, filterParams: AttendancesFilterParams) => {
    return apiService.post<PaginatedResponse<AttendanceLog>>('/api/attendances/devices?' + buildQueryString(paginationRequest), filterParams);
  },
  
  getByUser: (userId: number, startDate?: string, endDate?: string) => {
    const params = { startDate, endDate };
    return apiService.get<AttendanceLog[]>(`/api/attendances/users/${userId}`, params);
  },

  getMonthlySummary: (employeeIds: string[], year: number, month: number) => {
    return apiService.post<MonthlyAttendanceSummary>(
      `/api/attendances/monthly-summary?year=${year}&month=${month}`,
      { employeeIds }
    );
  }

};