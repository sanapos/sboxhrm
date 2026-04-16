import { apiService, buildQueryParams } from './api';
import { PaginatedResponse } from '../types';
import {
  Allowance,
  CreateAllowanceRequest,
  UpdateAllowanceRequest,
  AllowanceQueryParams,
  AdvanceRequest,
  CreateAdvanceRequest,
  ApproveAdvanceRequest,
  AdvanceRequestQueryParams,
  AttendanceCorrectionRequest,
  CreateAttendanceCorrectionRequest,
  ApproveAttendanceCorrectionRequest,
  AttendanceCorrectionQueryParams,
} from '../types/hrm';

// ============ ALLOWANCE SERVICE ============
export const allowanceService = {
  // Get employee's allowances
  getMyAllowances: async (params?: AllowanceQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<Allowance>>(
      '/api/allowances/my' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get all allowances (admin)
  getAllAllowances: async (params?: AllowanceQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<Allowance>>(
      '/api/allowances' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get allowances by employee
  getByEmployee: async (employeeId: string, params?: AllowanceQueryParams) => {
    const queryString = buildQueryParams({ ...params, employeeId });
    return await apiService.get<PaginatedResponse<Allowance>>(
      '/api/allowances' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get allowance by id
  getById: async (id: string) => {
    return await apiService.get<Allowance>(`/api/allowances/${id}`);
  },

  // Create allowance
  create: async (data: CreateAllowanceRequest) => {
    return await apiService.post<Allowance>('/api/allowances', data);
  },

  // Update allowance
  update: async (id: string, data: UpdateAllowanceRequest) => {
    return await apiService.put<Allowance>(`/api/allowances/${id}`, data);
  },

  // Delete allowance
  delete: async (id: string) => {
    return await apiService.delete(`/api/allowances/${id}`);
  },

  // Toggle active status
  toggleActive: async (id: string) => {
    return await apiService.post<Allowance>(`/api/allowances/${id}/toggle-active`, {});
  },
};

// ============ ADVANCE REQUEST SERVICE ============
export const advanceRequestService = {
  // Get my advance requests
  getMyRequests: async (params?: AdvanceRequestQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<AdvanceRequest>>(
      '/api/advance-requests/my' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get all advance requests (admin)
  getAllRequests: async (params?: AdvanceRequestQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<AdvanceRequest>>(
      '/api/advance-requests' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get pending requests (for manager approval)
  getPendingRequests: async (params?: AdvanceRequestQueryParams) => {
    const queryString = buildQueryParams({ ...params, status: 0 });
    return await apiService.get<PaginatedResponse<AdvanceRequest>>(
      '/api/advance-requests' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get request by id
  getById: async (id: string) => {
    return await apiService.get<AdvanceRequest>(`/api/advance-requests/${id}`);
  },

  // Create advance request
  create: async (data: CreateAdvanceRequest) => {
    return await apiService.post<AdvanceRequest>('/api/advance-requests', data);
  },

  // Approve/Reject request
  approve: async (data: ApproveAdvanceRequest) => {
    return await apiService.post<AdvanceRequest>(
      `/api/advance-requests/${data.requestId}/approve`,
      data
    );
  },

  // Mark as paid
  markAsPaid: async (id: string) => {
    return await apiService.post<AdvanceRequest>(`/api/advance-requests/${id}/paid`, {});
  },

  // Cancel request
  cancel: async (id: string) => {
    return await apiService.post<AdvanceRequest>(`/api/advance-requests/${id}/cancel`, {});
  },

  // Get summary for month/year
  getSummary: async (month: number, year: number) => {
    return await apiService.get<{
      totalRequests: number;
      totalAmount: number;
      totalApproved: number;
      totalPending: number;
      totalPaid: number;
    }>(`/api/advance-requests/summary?month=${month}&year=${year}`);
  },
};

// ============ ATTENDANCE CORRECTION SERVICE ============
export const attendanceCorrectionService = {
  // Get my correction requests
  getMyRequests: async (params?: AttendanceCorrectionQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<AttendanceCorrectionRequest>>(
      '/api/attendance-corrections/my' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get all correction requests (admin)
  getAllRequests: async (params?: AttendanceCorrectionQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<AttendanceCorrectionRequest>>(
      '/api/attendance-corrections' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get pending requests (for manager approval)
  getPendingRequests: async (params?: AttendanceCorrectionQueryParams) => {
    const queryString = buildQueryParams({ ...params, status: 0 });
    return await apiService.get<PaginatedResponse<AttendanceCorrectionRequest>>(
      '/api/attendance-corrections' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get request by id
  getById: async (id: string) => {
    return await apiService.get<AttendanceCorrectionRequest>(
      `/api/attendance-corrections/${id}`
    );
  },

  // Create correction request
  create: async (data: CreateAttendanceCorrectionRequest) => {
    return await apiService.post<AttendanceCorrectionRequest>(
      '/api/attendance-corrections',
      data
    );
  },

  // Approve/Reject request
  approve: async (data: ApproveAttendanceCorrectionRequest) => {
    return await apiService.post<AttendanceCorrectionRequest>(
      `/api/attendance-corrections/${data.requestId}/approve`,
      data
    );
  },

  // Cancel request
  cancel: async (id: string) => {
    return await apiService.post<AttendanceCorrectionRequest>(
      `/api/attendance-corrections/${id}/cancel`,
      {}
    );
  },
};
