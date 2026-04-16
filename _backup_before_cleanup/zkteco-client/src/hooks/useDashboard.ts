import { useQuery } from '@tanstack/react-query'
import { dashboardService } from '@/services/dashboardService'
import type {
  DashboardData,
  DashboardSummary,
  EmployeePerformance,
  DepartmentStatistics,
  AttendanceTrend,
  DeviceStatus,
  DashboardParams,
} from '@/types/dashboard'

// Get complete dashboard data
export const useDashboardData = (params?: DashboardParams) => {
  return useQuery({
    queryKey: ['dashboard', params],
    queryFn: async () => {
      return  await dashboardService.getAll(params)
    },
  })
}

// Get today's summary
export const useDashboardSummary = () => {
  return useQuery({
    queryKey: ['dashboard', 'summary'],
    queryFn: async () => {
      return  await dashboardService.getSummary()
    },
    refetchInterval: 60000, // Refetch every minute
  })
}

// Get top performers
export const useTopPerformers = (params?: {
  startDate?: string
  endDate?: string
  count?: number
  department?: string
}) => {
  return useQuery({
    queryKey: ['dashboard', 'top-performers', params],
    queryFn: async () => {
      return  await dashboardService.getTopPerformers(params)
    },
  })
}

// Get late employees
export const useLateEmployees = (params?: {
  startDate?: string
  endDate?: string
  count?: number
  department?: string
}) => {
  return useQuery({
    queryKey: ['dashboard', 'late-employees', params],
    queryFn: async () => {
      return  await dashboardService.getLateEmployees(params)
    },
  })
}

// Get department statistics
export const useDepartmentStats = (params?: {
  startDate?: string
  endDate?: string
}) => {
  return useQuery({
    queryKey: ['dashboard', 'department-stats', params],
    queryFn: async () => {
      return  await dashboardService.getDepartmentStats(params)
    },
  })
}

// Get attendance trends
export const useAttendanceTrends = (days?: number) => {
  return useQuery({
    queryKey: ['dashboard', 'attendance-trends', days],
    queryFn: async () => {
      return  await dashboardService.getAttendanceTrends(days)
    },
  })
}

// Get device status
export const useDeviceStatus = () => {
  return useQuery({
    queryKey: ['dashboard', 'device-status'],
    queryFn: async () => {
      return  await dashboardService.getDeviceStatus()
    },
    refetchInterval: 60000, // Refetch every minute
  })
}

// Additional convenience hooks

// Get weekly dashboard data
export const useWeeklyDashboard = () => {
  return useQuery({
    queryKey: ['dashboard', 'weekly'],
    queryFn: async () => {
      return  await dashboardService.getWeeklyData()
    },
  })
}

// Get monthly dashboard data
export const useMonthlyDashboard = () => {
  return useQuery({
    queryKey: ['dashboard', 'monthly'],
    queryFn: async () => {
      return  await dashboardService.getMonthlyData()
    },
  })
}

// Get quarterly dashboard data
export const useQuarterlyDashboard = () => {
  return useQuery({
    queryKey: ['dashboard', 'quarterly'],
    queryFn: async () => {
      return  await dashboardService.getQuarterlyData()
    },
  })
}

// Get dashboard by date range
export const useDashboardByDateRange = (
  startDate: string,
  endDate: string,
  department?: string
) => {
  return useQuery({
    queryKey: ['dashboard', 'date-range', startDate, endDate, department],
    queryFn: async () => {
      return  await dashboardService.getByDateRange(startDate, endDate, department)
    },
    enabled: !!startDate && !!endDate,
  })
}

// Get dashboard by department
export const useDashboardByDepartment = (
  department: string,
  startDate?: string,
  endDate?: string
) => {
  return useQuery({
    queryKey: ['dashboard', 'department', department, startDate, endDate],
    queryFn: async () => {
      return  await dashboardService.getByDepartment(department, startDate, endDate)
    },
    enabled: !!department,
  })
}

// Export types for convenience
export type {
  DashboardData,
  DashboardSummary,
  EmployeePerformance,
  DepartmentStatistics,
  AttendanceTrend,
  DeviceStatus,
  DashboardParams,
}

