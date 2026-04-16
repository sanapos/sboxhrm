export interface ManagerDashboardData {
  employeesOnLeave: EmployeeOnLeave[];
  absentEmployees: AbsentEmployee[];
  lateEmployees: LateEmployee[];
  todayEmployees: TodayEmployee[];
  attendanceRate: AttendanceRate;
}

export interface EmployeeOnLeave {
  employeeUserId: string;
  fullName: string;
  email: string;
  leaveId: string;
  leaveType: string;
  leaveStartDate: string;
  leaveEndDate: string;
  isFullDay: boolean;
  reason: string;
  shiftId: string;
  shiftStartTime: string;
  shiftEndTime: string;
}

export interface AbsentEmployee {
  employeeUserId: string;
  fullName: string;
  email: string;
  shiftId: string;
  shiftStartTime: string;
  shiftEndTime: string;
  department: string;
}

export interface LateEmployee {
  employeeUserId: string;
  fullName: string;
  email: string;
  shiftId: string;
  shiftStartTime: string;
  actualCheckInTime: string;
  lateBy: string; // TimeSpan from backend
  department: string;
}

export interface TodayEmployee {
  employeeUserId: string;
  fullName: string;
  email: string;
  shiftId: string | null;
  shiftStartTime: string | null;
  shiftEndTime: string | null;
  status: 'On Leave' | 'Present' | 'Late' | 'Absent' | 'No Shift';
  checkInTime: string | null;
  checkOutTime: string | null;
  department: string;
}

export interface AttendanceRate {
  totalEmployeesWithShift: number;
  presentEmployees: number;
  lateEmployees: number;
  absentEmployees: number;
  onLeaveEmployees: number;
  attendancePercentage: number;
  punctualityPercentage: number;
}
