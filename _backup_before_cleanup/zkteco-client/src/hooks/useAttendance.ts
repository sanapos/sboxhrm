
// ==========================================
// src/hooks/useAttendance.ts
// ==========================================
import { useQuery } from '@tanstack/react-query';
import { attendanceService } from '@/services/attendanceService';
import { PaginationRequest } from '@/types';
import { AttendancesFilterParams } from '@/types/attendance';

export const useAttendancesByDevices = (
  paginationRequest: PaginationRequest,
  filter: AttendancesFilterParams,
) => {
  return useQuery({
    queryKey: ['attendance', 'devices', filter],
    queryFn: () => {
      return attendanceService.getByDevices(paginationRequest, filter)
    },
    enabled: !!filter?.deviceIds?.length && filter.fromDate <= filter.toDate,
  });
};

export const useAttendanceByUser = (
  userId: number,
  startDate?: string,
  endDate?: string
) => {
  return useQuery({
    queryKey: ['attendance', 'user', userId, startDate, endDate],
    queryFn: () => attendanceService.getByUser(userId, startDate, endDate),
    enabled: !!userId,
  });
};

export const useMonthlyAttendanceSummary = (
  employeeIds: string[],
  year: number,
  month: number,
  enabled: boolean = true
) => {
  return useQuery({
    queryKey: ['attendance', 'monthly-summary', employeeIds, year, month],
    queryFn: () => attendanceService.getMonthlySummary(employeeIds, year, month),
    enabled: enabled && employeeIds.length > 0 && !!year && !!month,
  });
};