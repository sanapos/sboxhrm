
export interface DashboardSummary {
  totalEmployees: number
  activeEmployees: number
  inactiveEmployees: number
  totalDevices: number
  onlineDevices: number
  offlineDevices: number
  todayCheckIns: number
  todayCheckOuts: number
  todayAbsences: number
  todayLateArrivals: number
  averageAttendanceRate: number
}

export interface EmployeePerformance {
  userId: string
  fullName: string
  department: string
  totalAttendanceDays: number
  onTimeDays: number
  lateDays: number
  absentDays: number
  attendanceRate: number
  punctualityRate: number
  averageWorkHours: string
  averageLateTime?: string
  lastCheckIn?: string
  lastCheckOut?: string
}

export interface DepartmentStatistics {
  department: string
  totalEmployees: number
  activeToday: number
  absentToday: number
  lateToday: number
  attendanceRate: number
  punctualityRate: number
  averageWorkHours: string
}

export interface AttendanceTrend {
  date: string
  totalCheckIns: number
  totalCheckOuts: number
  lateArrivals: number
  absences: number
  attendanceRate: number
}

export interface DeviceStatus {
  deviceId: string
  deviceName: string
  location: string
  status: string
  lastOnline?: string
  registeredUsers: number
  todayAttendances: number
}

export interface DashboardData {
  summary: DashboardSummary
  topPerformers: EmployeePerformance[]
  lateEmployees: EmployeePerformance[]
  departmentStats: DepartmentStatistics[]
  attendanceTrends: AttendanceTrend[]
  deviceStatuses: DeviceStatus[]
}

export interface DashboardParams {
  startDate?: string
  endDate?: string
  department?: string
  topPerformersCount?: number
  lateEmployeesCount?: number
  trendDays?: number
}