import { LeaveDialogState, LeaveStatus, LeaveType } from '@/types/leave';
import { CreateDeviceRequest, PaginationRequest } from "@/types";
import { AttendancesFilterParams } from "@/types/attendance";
import { CreateShiftTemplateRequest, CreatShiftDialog, ShiftManagementFilter } from "@/types/shift";
import { format, startOfMonth, subMonths } from "date-fns";
import { DateTimeFormat } from ".";

export const defaultNewDevice: CreateDeviceRequest = {
    serialNumber: '',
    deviceName: '',
    location: '',
    description: '',
}

const today = new Date()
const threeMonthsAgo = subMonths(today, 3)

export const defaultAttendanceFilter: AttendancesFilterParams = {
    fromDate: format(threeMonthsAgo, DateTimeFormat),
    toDate: format(today, DateTimeFormat),
    deviceIds: []
}

export const defaultAttendancePaginationRequest: PaginationRequest = {
    pageNumber: 1,
    pageSize: 20,
    sortBy: 'attendanceTime',
    sortOrder: 'desc'
}

export const defaultShiftPaginationRequest: PaginationRequest = {
    pageNumber: 1,
    pageSize: 20,
    sortBy: 'startTime',
    sortOrder: 'desc'
}

export const defaultPaginationRequest: PaginationRequest = {
    pageNumber: 1,
    pageSize: 20,
    sortBy: 'createdAt',
    sortOrder: 'desc'
}

export const defaultNewShiftTemplate: CreateShiftTemplateRequest = {
    name: '',
    startTime: '09:00:00',
    endTime: '17:00:00',
    maximumAllowedLateMinutes: 30,
    maximumAllowedEarlyLeaveMinutes: 30,
    breakTimeMinutes: 60,
}

export const defaultShiftManagementFilter: ShiftManagementFilter = {
    employeeIds: [],
    dateRange: {
        from: startOfMonth(new Date()),
        to: today,
    },
};

const now = new Date();
const tomorrow = new Date(now);
tomorrow.setDate(tomorrow.getDate() + 1);

export const defaultNewShiftWithEmployeeUserId: CreatShiftDialog = {
    employeeUserId: null,
    startTime: tomorrow,
    endTime: tomorrow,
    maximumAllowedLateMinutes: 30,
    maximumAllowedEarlyLeaveMinutes: 30,
    breakTimeMinutes: 60,
    description: ''
}

export const defaultTemplateShift = {
    templateId: '',
    date: new Date(),
    description: '',
}

export const defaultLeaveDialogState: LeaveDialogState = {
    employeeUserId: null,
    shiftId: '',
    type: LeaveType.PERSONAL,
    isHalfShift: false,
    halfShiftType: '',
    startDate: undefined,
    endDate: undefined,
    reason: '',
    status: LeaveStatus.APPROVED
};