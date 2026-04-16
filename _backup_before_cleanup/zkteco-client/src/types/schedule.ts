// ============ WORK SCHEDULE TYPES ============

export interface WorkSchedule {
  id: string;
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  shiftId: string;
  shiftName: string;
  shiftStartTime: string;
  shiftEndTime: string;
  workDate: string;
  storeId?: string;
  storeName?: string;
  isDayOff: boolean;
  notes?: string;
  createdAt: string;
  updatedAt?: string;
}

export interface CreateWorkScheduleRequest {
  employeeId: string;
  shiftId: string;
  workDate: string;
  storeId?: string;
  isDayOff: boolean;
  notes?: string;
}

export interface BulkCreateWorkScheduleRequest {
  employeeIds: string[];
  shiftId: string;
  startDate: string;
  endDate: string;
  storeId?: string;
  workDays: number[]; // 0-6 for Sunday-Saturday
}

export interface UpdateWorkScheduleRequest {
  shiftId: string;
  storeId?: string;
  isDayOff: boolean;
  notes?: string;
}

export interface WorkScheduleQueryParams {
  page?: number;
  pageSize?: number;
  employeeId?: string;
  shiftId?: string;
  storeId?: string;
  fromDate?: string;
  toDate?: string;
  isDayOff?: boolean;
}

// ============ SCHEDULE REGISTRATION TYPES ============

export enum ScheduleRegistrationStatus {
  PENDING = 0,
  APPROVED = 1,
  REJECTED = 2
}

export const getScheduleRegistrationStatusLabel = (status: ScheduleRegistrationStatus): string => {
  switch (status) {
    case ScheduleRegistrationStatus.PENDING:
      return 'Chờ duyệt';
    case ScheduleRegistrationStatus.APPROVED:
      return 'Đã duyệt';
    case ScheduleRegistrationStatus.REJECTED:
      return 'Từ chối';
    default:
      return 'Không xác định';
  }
};

export const getScheduleRegistrationStatusColor = (status: ScheduleRegistrationStatus): string => {
  switch (status) {
    case ScheduleRegistrationStatus.PENDING:
      return 'bg-yellow-100 text-yellow-800';
    case ScheduleRegistrationStatus.APPROVED:
      return 'bg-green-100 text-green-800';
    case ScheduleRegistrationStatus.REJECTED:
      return 'bg-red-100 text-red-800';
    default:
      return 'bg-gray-100 text-gray-800';
  }
};

export interface ScheduleRegistration {
  id: string;
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  workDate: string;
  shiftId: string;
  shiftName: string;
  storeId?: string;
  storeName?: string;
  reason?: string;
  requestDate: string;
  status: ScheduleRegistrationStatus;
  approvedBy?: string;
  approvedByName?: string;
  approvedAt?: string;
  rejectReason?: string;
  createdAt: string;
  updatedAt?: string;
}

export interface CreateScheduleRegistrationRequest {
  workDate: string;
  shiftId: string;
  storeId?: string;
  reason?: string;
}

export interface ApproveScheduleRegistrationRequest {
  requestId: string;
  isApproved: boolean;
  rejectReason?: string;
}

export interface ScheduleRegistrationQueryParams {
  page?: number;
  pageSize?: number;
  employeeId?: string;
  status?: ScheduleRegistrationStatus;
  fromDate?: string;
  toDate?: string;
}
