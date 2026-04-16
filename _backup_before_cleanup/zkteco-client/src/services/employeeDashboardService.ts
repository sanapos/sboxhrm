import { apiService } from './api';
import { EmployeeDashboardData, EmployeeDashboardParams } from '@/types/employee-dashboard';

export const employeeDashboardService = {
  // Get employee dashboard data
  getDashboard: (params?: EmployeeDashboardParams) => 
    apiService.get<EmployeeDashboardData>('/api/dashboard/employee', { params }),

  // Get Current Shift
  getTodayShift: () => 
    apiService.get('/api/dashboard/shifts/today'),

  // Get next upcoming shift
  getNextShift: () => 
    apiService.get('/api/dashboard/shifts/next'),

  // Get current attendance
  getCurrentAttendance: () => 
    apiService.get('/api/dashboard/attendance/current'),

  // Get attendance statistics
  getAttendanceStats: (params?: EmployeeDashboardParams) => 
    apiService.get('/api/dashboard/attendance/stats', { params }),
};
