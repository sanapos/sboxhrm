import { apiService, buildQueryParams } from './api';
import { PaginatedResponse } from '../types';
import {
  AppNotification,
  CreateNotificationRequest,
  BulkCreateNotificationRequest,
  NotificationQueryParams,
  NotificationSummary,
} from '../types/notification';

export const notificationService = {
  // Get my notifications
  getMyNotifications: async (params?: NotificationQueryParams) => {
    const queryString = buildQueryParams(params || {});
    return await apiService.get<PaginatedResponse<AppNotification>>(
      '/api/notifications/my' + (queryString ? `?${queryString}` : '')
    );
  },

  // Get notification summary (unread count, recent)
  getSummary: async () => {
    return await apiService.get<NotificationSummary>('/api/notifications/summary');
  },

  // Get notification by id
  getById: async (id: string) => {
    return await apiService.get<AppNotification>(`/api/notifications/${id}`);
  },

  // Mark as read
  markAsRead: async (id: string) => {
    return await apiService.post<AppNotification>(`/api/notifications/${id}/read`, {});
  },

  // Mark all as read
  markAllAsRead: async () => {
    return await apiService.post<{ count: number }>('/api/notifications/read-all', {});
  },

  // Delete notification
  delete: async (id: string) => {
    return await apiService.delete(`/api/notifications/${id}`);
  },

  // Delete all read notifications
  deleteAllRead: async () => {
    return await apiService.delete('/api/notifications/read');
  },

  // Create notification (admin)
  create: async (data: CreateNotificationRequest) => {
    return await apiService.post<Notification>('/api/notifications', data);
  },

  // Bulk create notifications (admin)
  bulkCreate: async (data: BulkCreateNotificationRequest) => {
    return await apiService.post<{ count: number }>('/api/notifications/bulk', data);
  },

  // Send to all users (admin)
  sendToAll: async (data: Omit<CreateNotificationRequest, 'userId'>) => {
    return await apiService.post<{ count: number }>('/api/notifications/broadcast', data);
  },
};
