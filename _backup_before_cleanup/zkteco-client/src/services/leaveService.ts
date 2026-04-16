import { PaginatedResponse, PaginationRequest } from '@/types';
import { apiService, buildQueryParams } from './api';
import type { 
    LeaveRequest, 
    CreateLeaveRequest,
    UpdateLeaveRequest,
    RejectLeaveRequest 
} from '@/types/leave';

export const leaveService = {
    // Employee endpoints
    getMyLeaves: async () => {
        return await apiService.get<LeaveRequest[]>('/api/leaves/my-leaves');
    },

    createLeave: async (data: CreateLeaveRequest) => {
        return await apiService.post<LeaveRequest>('/api/leaves', data);
    },

    updateLeave: async (id: string, data: UpdateLeaveRequest) => {
        return await apiService.put<LeaveRequest>(`/api/leaves/${id}`, data);
    },

    cancelLeave: async (id: string) => {
        return await apiService.delete<boolean>(`/api/leaves/${id}`);
    },

    // Manager endpoints
    getPendingLeaves: async (paginationRequest: PaginationRequest) => {
        const queryString = buildQueryParams(paginationRequest);
        return await apiService.get<PaginatedResponse<LeaveRequest>>('/api/leaves/pending' + (queryString ? `?${queryString}` : ''));
    },

    getAllLeaves: async (paginationRequest: PaginationRequest) => {
        const queryString = buildQueryParams(paginationRequest);
        return await apiService.get<PaginatedResponse<LeaveRequest>>('/api/leaves' + (queryString ? `?${queryString}` : ''));
    },

    approveLeave: async (id: string) => {
        return await apiService.post<LeaveRequest>(`/api/leaves/${id}/approve`, {});
    },

    rejectLeave: async (id: string, data: RejectLeaveRequest) => {
        return await apiService.post<LeaveRequest>(`/api/leaves/${id}/reject`, data);
    },
};
