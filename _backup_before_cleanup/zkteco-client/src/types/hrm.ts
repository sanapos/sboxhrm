// ============ ALLOWANCE TYPES ============

export enum AllowanceType {
  FIXED = 0,
  DAILY = 1,
  HOURLY = 2
}

export const getAllowanceTypeLabel = (type: AllowanceType): string => {
  switch (type) {
    case AllowanceType.FIXED:
      return 'Cố định';
    case AllowanceType.DAILY:
      return 'Theo ngày';
    case AllowanceType.HOURLY:
      return 'Theo giờ';
    default:
      return 'Không xác định';
  }
};

export interface Allowance {
  id: string;
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  name: string;
  description?: string;
  type: AllowanceType;
  amount: number;
  effectiveFrom: string;
  effectiveTo?: string;
  isActive: boolean;
  createdAt: string;
  updatedAt?: string;
}

export interface CreateAllowanceRequest {
  employeeId: string;
  name: string;
  description?: string;
  type: AllowanceType;
  amount: number;
  effectiveFrom: string;
  effectiveTo?: string;
}

export interface UpdateAllowanceRequest {
  name: string;
  description?: string;
  type: AllowanceType;
  amount: number;
  effectiveFrom: string;
  effectiveTo?: string;
  isActive: boolean;
}

export interface AllowanceQueryParams {
  page?: number;
  pageSize?: number;
  employeeId?: string;
  type?: AllowanceType;
  isActive?: boolean;
  searchTerm?: string;
}

// ============ ADVANCE REQUEST TYPES ============

export enum AdvanceRequestStatus {
  PENDING = 0,
  APPROVED = 1,
  REJECTED = 2
}

export const getAdvanceStatusLabel = (status: AdvanceRequestStatus): string => {
  switch (status) {
    case AdvanceRequestStatus.PENDING:
      return 'Chờ duyệt';
    case AdvanceRequestStatus.APPROVED:
      return 'Đã duyệt';
    case AdvanceRequestStatus.REJECTED:
      return 'Từ chối';
    default:
      return 'Không xác định';
  }
};

export const getAdvanceStatusColor = (status: AdvanceRequestStatus): string => {
  switch (status) {
    case AdvanceRequestStatus.PENDING:
      return 'bg-yellow-100 text-yellow-800';
    case AdvanceRequestStatus.APPROVED:
      return 'bg-green-100 text-green-800';
    case AdvanceRequestStatus.REJECTED:
      return 'bg-red-100 text-red-800';
    default:
      return 'bg-gray-100 text-gray-800';
  }
};

export interface AdvanceRequest {
  id: string;
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  amount: number;
  reason?: string;
  requestDate: string;
  month: number;
  year: number;
  status: AdvanceRequestStatus;
  approvedBy?: string;
  approvedByName?: string;
  approvedAt?: string;
  rejectReason?: string;
  isPaid: boolean;
  paidAt?: string;
  createdAt: string;
  updatedAt?: string;
}

export interface CreateAdvanceRequest {
  amount: number;
  reason?: string;
  month: number;
  year: number;
}

export interface ApproveAdvanceRequest {
  requestId: string;
  isApproved: boolean;
  rejectReason?: string;
}

export interface AdvanceRequestQueryParams {
  page?: number;
  pageSize?: number;
  employeeId?: string;
  status?: AdvanceRequestStatus;
  month?: number;
  year?: number;
  isPaid?: boolean;
}

// ============ ATTENDANCE CORRECTION TYPES ============

export enum CorrectionAction {
  ADD = 0,
  EDIT = 1,
  DELETE = 2
}

export enum CorrectionStatus {
  PENDING = 0,
  APPROVED = 1,
  REJECTED = 2
}

export const getCorrectionActionLabel = (action: CorrectionAction): string => {
  switch (action) {
    case CorrectionAction.ADD:
      return 'Thêm mới';
    case CorrectionAction.EDIT:
      return 'Chỉnh sửa';
    case CorrectionAction.DELETE:
      return 'Xóa';
    default:
      return 'Không xác định';
  }
};

export const getCorrectionStatusLabel = (status: CorrectionStatus): string => {
  switch (status) {
    case CorrectionStatus.PENDING:
      return 'Chờ duyệt';
    case CorrectionStatus.APPROVED:
      return 'Đã duyệt';
    case CorrectionStatus.REJECTED:
      return 'Từ chối';
    default:
      return 'Không xác định';
  }
};

export const getCorrectionStatusColor = (status: CorrectionStatus): string => {
  switch (status) {
    case CorrectionStatus.PENDING:
      return 'bg-yellow-100 text-yellow-800';
    case CorrectionStatus.APPROVED:
      return 'bg-green-100 text-green-800';
    case CorrectionStatus.REJECTED:
      return 'bg-red-100 text-red-800';
    default:
      return 'bg-gray-100 text-gray-800';
  }
};

export interface AttendanceCorrectionRequest {
  id: string;
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  attendanceId?: string;
  action: CorrectionAction;
  correctionDate: string;
  originalCheckIn?: string;
  originalCheckOut?: string;
  newCheckIn?: string;
  newCheckOut?: string;
  reason?: string;
  requestDate: string;
  status: CorrectionStatus;
  approvedBy?: string;
  approvedByName?: string;
  approvedAt?: string;
  rejectReason?: string;
  createdAt: string;
  updatedAt?: string;
}

export interface CreateAttendanceCorrectionRequest {
  attendanceId?: string;
  action: CorrectionAction;
  correctionDate: string;
  newCheckIn?: string;
  newCheckOut?: string;
  reason?: string;
}

export interface ApproveAttendanceCorrectionRequest {
  requestId: string;
  isApproved: boolean;
  rejectReason?: string;
}

export interface AttendanceCorrectionQueryParams {
  page?: number;
  pageSize?: number;
  employeeId?: string;
  status?: CorrectionStatus;
  action?: CorrectionAction;
  fromDate?: string;
  toDate?: string;
}
