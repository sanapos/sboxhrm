// Employee Dashboard Types

export interface EmployeeDashboardData {
  todayShift: ShiftInfo | null;
  nextShift: ShiftInfo | null;
  currentAttendance: AttendanceInfo | null;
  attendanceStats: AttendanceStats;
}

export interface ShiftInfo {
  id: string;
  startTime: string;
  endTime: string;
  description?: string;
  status: number;
  totalHours: number;
  isToday: boolean;
}

export interface AttendanceInfo {
  id: string;
  checkInTime: string | null;
  checkOutTime: string | null;
  workHours: number;
  status: 'checked-in' | 'checked-out' | 'not-started';
  isLate: boolean;
  isEarlyOut: boolean;
  lateMinutes?: number;
  earlyOutMinutes?: number;
}

export interface AttendanceStats {
  totalWorkDays: number;
  presentDays: number;
  absentDays: number;
  lateCheckIns: number;
  earlyCheckOuts: number;
  attendanceRate: number;
  punctualityRate: number;
  averageWorkHours: string;
  period: 'week' | 'month' | 'year';
}

export interface EmployeeDashboardParams {
  period?: 'week' | 'month' | 'year';
  startDate?: string;
  endDate?: string;
}
