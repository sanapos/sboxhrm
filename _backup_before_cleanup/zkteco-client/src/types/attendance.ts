export interface AttendancesFilterParams {
    fromDate: string
    toDate: string
    deviceIds?: string[]
}

export interface MonthlyAttendanceSummary {
    employeeId: string;
    employeeName: string;
    year: number;
    month: number;
    dailyRecords: DailyAttendance[];
}

export interface DailyAttendance {
    date: string;
    attendances: AttendanceRecord[];
    shift?: ShiftInfo;
    leave?: LeaveInfo;
    hasShift: boolean;
    isLeave: boolean;
}

export interface AttendanceRecord {
    id: string;
    checkInTime: string;
    checkOutTime?: string;
    deviceName: string;
    verifyMode: number;
    attendanceState: number;
}

export interface ShiftInfo {
    id: string;
    startTime: string;
    endTime: string;
    description?: string;
    status: number;
}

export interface LeaveInfo {
    id: string;
    type: number;
    reason: string;
    status: number;
    isHalfShift: boolean;
}

export enum LeaveType {
    Sick = 0,
    Vacation = 1,
    Personal = 2,
    Other = 3
}

export enum LeaveStatus {
    Pending = 0,
    Approved = 1,
    Rejected = 2,
    Cancelled = 3
}

export enum ShiftStatus {
    Pending = 0,
    Approved = 1,
    Rejected = 2,
    Cancelled = 3
}
