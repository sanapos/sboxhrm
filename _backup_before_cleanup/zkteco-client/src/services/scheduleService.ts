import { apiService, buildQueryParams } from './api';
import { PaginatedResponse } from '../types';
import {
  WorkSchedule,
  CreateWorkScheduleRequest,
  BulkCreateWorkScheduleRequest,
  UpdateWorkScheduleRequest,
  WorkScheduleQueryParams,
  ScheduleRegistration,
  CreateScheduleRegistrationRequest,
  ApproveScheduleRegistrationRequest,
  ScheduleRegistrationQueryParams,
} from '../types/schedule';

// ============ WORK SCHEDULE SERVICE ============
export const workScheduleService = {
  // Get my schedules
  getMySchedules: async (params?: WorkScheduleQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<WorkSchedule>>(
      '/api/work-schedules/my' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get all schedules (admin)
  getAllSchedules: async (params?: WorkScheduleQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<WorkSchedule>>(
      '/api/work-schedules' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get schedules by employee
  getByEmployee: async (employeeId: string, params?: WorkScheduleQueryParams) => {
    const queryString = buildQueryParams({ ...params, employeeId });
    return await apiService.get<PaginatedResponse<WorkSchedule>>(
      '/api/work-schedules' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get schedules by date range
  getByDateRange: async (fromDate: string, toDate: string, params?: WorkScheduleQueryParams) => {
    const queryString = buildQueryParams({ ...params, fromDate, toDate });
    return await apiService.get<PaginatedResponse<WorkSchedule>>(
      '/api/work-schedules' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get schedule by id
  getById: async (id: string) => {
    return await apiService.get<WorkSchedule>(`/api/work-schedules/${id}`);
  },

  // Create schedule
  create: async (data: CreateWorkScheduleRequest) => {
    return await apiService.post<WorkSchedule>('/api/work-schedules', data);
  },

  // Bulk create schedules
  bulkCreate: async (data: BulkCreateWorkScheduleRequest) => {
    return await apiService.post<{ count: number }>('/api/work-schedules/bulk', data);
  },

  // Update schedule
  update: async (id: string, data: UpdateWorkScheduleRequest) => {
    return await apiService.put<WorkSchedule>(`/api/work-schedules/${id}`, data);
  },

  // Delete schedule
  delete: async (id: string) => {
    return await apiService.delete(`/api/work-schedules/${id}`);
  },

  // Get weekly view
  getWeeklyView: async (startDate: string, storeId?: string) => {
    const queryString = buildQueryParams({ startDate, storeId });
    return await apiService.get<{
      startDate: string;
      endDate: string;
      schedules: WorkSchedule[];
      employeeSummary: {
        employeeId: string;
        employeeName: string;
        totalHours: number;
        workDays: number;
        dayOffs: number;
      }[];
    }>('/api/work-schedules/weekly' + (queryString ? `?${queryString}` : ''));
  },

  // Copy schedules from previous week
  copyFromPreviousWeek: async (targetStartDate: string, storeId?: string) => {
    return await apiService.post<{ count: number }>('/api/work-schedules/copy-week', {
      targetStartDate,
      storeId,
    });
  },
};

// ============ SCHEDULE REGISTRATION SERVICE ============
export const scheduleRegistrationService = {
  // Get my registrations
  getMyRegistrations: async (params?: ScheduleRegistrationQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<ScheduleRegistration>>(
      '/api/schedule-registrations/my' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get all registrations (admin)
  getAllRegistrations: async (params?: ScheduleRegistrationQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<ScheduleRegistration>>(
      '/api/schedule-registrations' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get pending registrations (for manager approval)
  getPendingRegistrations: async (params?: ScheduleRegistrationQueryParams) => {
    const queryString = buildQueryParams({ ...params, status: 0 });
    return await apiService.get<PaginatedResponse<ScheduleRegistration>>(
      '/api/schedule-registrations' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get registration by id
  getById: async (id: string) => {
    return await apiService.get<ScheduleRegistration>(`/api/schedule-registrations/${id}`);
  },

  // Create registration
  create: async (data: CreateScheduleRegistrationRequest) => {
    return await apiService.post<ScheduleRegistration>('/api/schedule-registrations', data);
  },

  // Approve/Reject registration
  approve: async (data: ApproveScheduleRegistrationRequest) => {
    return await apiService.post<ScheduleRegistration>(
      `/api/schedule-registrations/${data.requestId}/approve`,
      data
    );
  },

  // Cancel registration
  cancel: async (id: string) => {
    return await apiService.post<ScheduleRegistration>(
      `/api/schedule-registrations/${id}/cancel`,
      {}
    );
  },
};
