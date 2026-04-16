// ==========================================
// src/services/dashboardService.ts
// ==========================================
import { apiService } from './api';
import type {
  DashboardData,
  DashboardSummary,
  EmployeePerformance,
  DepartmentStatistics,
  AttendanceTrend,
  DeviceStatus,
  DashboardParams,
} from '@/types/dashboard';

/**
 * Build query string from params object
 */
const buildQueryString = (params: Record<string, any>) => {
  return Object.entries(params)
    .filter(([_, value]) => value !== undefined && value !== null)
    .map(([key, value]) => {
      if (Array.isArray(value)) {
        return value.map(v => `${encodeURIComponent(key)}=${encodeURIComponent(v)}`).join('&');
      }
      return `${encodeURIComponent(key)}=${encodeURIComponent(value)}`;
    })
    .join('&');
};

/**
 * Dashboard Service
 * Provides methods to fetch dashboard analytics and metrics
 */
export const dashboardService = {
  /**
   * Get complete dashboard data with all metrics
   * @param params Dashboard filter parameters
   * @returns Complete dashboard data including summary, performers, trends, etc.
   */
  getAll: (params?: DashboardParams) => {
    const queryString = params ? `?${buildQueryString(params)}` : '';
    return apiService.get<DashboardData>(`/api/dashboard${queryString}`);
  },

  /**
   * Get today's summary statistics
   * @returns Summary of today's key metrics
   */
  getSummary: () => {
    return apiService.get<DashboardSummary>('/api/dashboard/manager');
  },

  /**
   * Get top performing employees
   * @param params Filter parameters (startDate, endDate, count, department)
   * @returns List of top performing employees
   */
  getTopPerformers: (params?: {
    startDate?: string;
    endDate?: string;
    count?: number;
    department?: string;
  }) => {
    const queryString = params ? `?${buildQueryString(params)}` : '';
    return apiService.get<EmployeePerformance[]>(
      `/api/dashboard/top-performers${queryString}`
    );
  },

  /**
   * Get employees with frequent late arrivals
   * @param params Filter parameters (startDate, endDate, count, department)
   * @returns List of employees with tardiness issues
   */
  getLateEmployees: (params?: {
    startDate?: string;
    endDate?: string;
    count?: number;
    department?: string;
  }) => {
    const queryString = params ? `?${buildQueryString(params)}` : '';
    return apiService.get<EmployeePerformance[]>(
      `/api/dashboard/late-employees${queryString}`
    );
  },

  /**
   * Get department statistics
   * @param params Filter parameters (startDate, endDate)
   * @returns Statistics grouped by department
   */
  getDepartmentStats: (params?: {
    startDate?: string;
    endDate?: string;
  }) => {
    const queryString = params ? `?${buildQueryString(params)}` : '';
    return apiService.get<DepartmentStatistics[]>(
      `/api/dashboard/department-stats${queryString}`
    );
  },

  /**
   * Get attendance trends over time
   * @param days Number of days for trend analysis (1-90)
   * @returns Daily attendance trends
   */
  getAttendanceTrends: (days?: number) => {
    const queryString = days ? `?days=${days}` : '';
    return apiService.get<AttendanceTrend[]>(
      `/api/dashboard/attendance-trends${queryString}`
    );
  },

  /**
   * Get device status information
   * @returns List of devices with their current status
   */
  getDeviceStatus: () => {
    return apiService.get<DeviceStatus[]>('/api/dashboard/device-status');
  },

  /**
   * Get filtered dashboard data by date range
   * @param startDate Start date (ISO string)
   * @param endDate End date (ISO string)
   * @param department Optional department filter
   * @returns Filtered dashboard data
   */
  getByDateRange: (startDate: string, endDate: string, department?: string) => {
    const params: DashboardParams = {
      startDate,
      endDate,
      department,
    };
    return dashboardService.getAll(params);
  },

  /**
   * Get dashboard data for a specific department
   * @param department Department name
   * @param startDate Optional start date
   * @param endDate Optional end date
   * @returns Department-specific dashboard data
   */
  getByDepartment: (department: string, startDate?: string, endDate?: string) => {
    const params: DashboardParams = {
      department,
      startDate,
      endDate,
    };
    return dashboardService.getAll(params);
  },

  /**
   * Get comprehensive performance analysis
   * @param params Filter parameters with custom counts
   * @returns Dashboard data with specified number of performers
   */
  getPerformanceAnalysis: (params: {
    startDate?: string;
    endDate?: string;
    topPerformersCount?: number;
    lateEmployeesCount?: number;
    department?: string;
  }) => {
    return dashboardService.getAll(params);
  },

  /**
   * Get weekly dashboard data (last 7 days)
   * @returns Dashboard data for the past week
   */
  getWeeklyData: () => {
    const endDate = new Date().toISOString().split('T')[0];
    const startDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
      .toISOString()
      .split('T')[0];
    return dashboardService.getByDateRange(startDate, endDate);
  },

  /**
   * Get monthly dashboard data (last 30 days)
   * @returns Dashboard data for the past month
   */
  getMonthlyData: () => {
    const endDate = new Date().toISOString().split('T')[0];
    const startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
      .toISOString()
      .split('T')[0];
    return dashboardService.getByDateRange(startDate, endDate);
  },

  /**
   * Get quarterly dashboard data (last 90 days)
   * @returns Dashboard data for the past quarter
   */
  getQuarterlyData: () => {
    const endDate = new Date().toISOString().split('T')[0];
    const startDate = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000)
      .toISOString()
      .split('T')[0];
    return dashboardService.getByDateRange(startDate, endDate);
  },
};
