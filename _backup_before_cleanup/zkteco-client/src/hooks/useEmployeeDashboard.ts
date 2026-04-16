import { useQuery } from '@tanstack/react-query';
import { employeeDashboardService } from '@/services/employeeDashboardService';
import { EmployeeDashboardParams } from '@/types/employee-dashboard';

export const useEmployeeDashboard = (params?: EmployeeDashboardParams) => {
  return useQuery({
    queryKey: ['employee-dashboard', params],
    queryFn: () => employeeDashboardService.getDashboard(params),
    refetchInterval: 60000, // Refetch every minute
  });
};

export const useTodayShift = () => {
  return useQuery({
    queryKey: ['today-shift'],
    queryFn: () => employeeDashboardService.getTodayShift(),
  });
};

export const useNextShift = () => {
  return useQuery({
    queryKey: ['next-shift'],
    queryFn: () => employeeDashboardService.getNextShift(),
  });
};

export const useCurrentAttendance = () => {
  return useQuery({
    queryKey: ['current-attendance'],
    queryFn: () => employeeDashboardService.getCurrentAttendance(),
    refetchInterval: 30000, // Refetch every 30 seconds
  });
};

export const useAttendanceStats = (params?: EmployeeDashboardParams) => {
  return useQuery({
    queryKey: ['attendance-stats', params],
    queryFn: () => employeeDashboardService.getAttendanceStats(params),
  });
};
