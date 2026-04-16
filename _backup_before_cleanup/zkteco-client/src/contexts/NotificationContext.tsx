// ==========================================
// src/contexts/NotificationContext.tsx
// ==========================================
import { createContext, useContext, useState, ReactNode, useCallback } from 'react';
import { AppNotification, NotificationSummary, NotificationQueryParams } from '@/types/notification';
import { notificationService } from '@/services/notificationService';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';

interface NotificationContextValue {
  // State
  notifications: AppNotification[];
  summary: NotificationSummary | null;
  isLoading: boolean;
  unreadCount: number;

  // Actions
  fetchNotifications: (params?: NotificationQueryParams) => void;
  markAsRead: (id: string) => Promise<void>;
  markAllAsRead: () => Promise<void>;
  deleteNotification: (id: string) => Promise<void>;
  deleteAllRead: () => Promise<void>;
  refetch: () => void;
}

const NotificationContext = createContext<NotificationContextValue | undefined>(undefined);

export const useNotificationContext = () => {
  const context = useContext(NotificationContext);
  if (!context) {
    throw new Error('useNotificationContext must be used within NotificationProvider');
  }
  return context;
};

interface NotificationProviderProps {
  children: ReactNode;
}

export const NotificationProvider = ({ children }: NotificationProviderProps) => {
  const queryClient = useQueryClient();
  const [params, setParams] = useState<NotificationQueryParams>({ page: 1, pageSize: 20 });

  // Queries
  const { data: paginatedNotifications, isLoading: isNotificationsLoading, refetch } = useQuery({
    queryKey: ['notifications', params],
    queryFn: () => notificationService.getMyNotifications(params),
    refetchInterval: 60000, // Refetch every minute
  });

  const { data: summary, isLoading: isSummaryLoading } = useQuery({
    queryKey: ['notification-summary'],
    queryFn: () => notificationService.getSummary(),
    refetchInterval: 30000, // Refetch every 30 seconds
  });

  // Mutations
  const markAsReadMutation = useMutation({
    mutationFn: notificationService.markAsRead,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notifications'] });
      queryClient.invalidateQueries({ queryKey: ['notification-summary'] });
    },
  });

  const markAllAsReadMutation = useMutation({
    mutationFn: notificationService.markAllAsRead,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notifications'] });
      queryClient.invalidateQueries({ queryKey: ['notification-summary'] });
      toast.success('Đã đánh dấu tất cả đã đọc');
    },
    onError: () => {
      toast.error('Không thể đánh dấu đã đọc');
    },
  });

  const deleteMutation = useMutation({
    mutationFn: notificationService.delete,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notifications'] });
      queryClient.invalidateQueries({ queryKey: ['notification-summary'] });
      toast.success('Đã xóa thông báo');
    },
    onError: () => {
      toast.error('Không thể xóa thông báo');
    },
  });

  const deleteAllReadMutation = useMutation({
    mutationFn: notificationService.deleteAllRead,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notifications'] });
      queryClient.invalidateQueries({ queryKey: ['notification-summary'] });
      toast.success('Đã xóa tất cả thông báo đã đọc');
    },
    onError: () => {
      toast.error('Không thể xóa thông báo');
    },
  });

  const isLoading = isNotificationsLoading || isSummaryLoading;

  const notifications = paginatedNotifications?.items || [];
  const unreadCount = summary?.unreadCount || 0;

  // Handlers
  const fetchNotifications = useCallback((newParams?: NotificationQueryParams) => {
    if (newParams) {
      setParams(prev => ({ ...prev, ...newParams }));
    }
  }, []);

  const markAsRead = async (id: string) => {
    await markAsReadMutation.mutateAsync(id);
  };

  const markAllAsRead = async () => {
    await markAllAsReadMutation.mutateAsync();
  };

  const deleteNotification = async (id: string) => {
    await deleteMutation.mutateAsync(id);
  };

  const deleteAllRead = async () => {
    await deleteAllReadMutation.mutateAsync();
  };

  const value: NotificationContextValue = {
    notifications,
    summary: summary || null,
    isLoading,
    unreadCount,
    fetchNotifications,
    markAsRead,
    markAllAsRead,
    deleteNotification,
    deleteAllRead,
    refetch,
  };

  return (
    <NotificationContext.Provider value={value}>
      {children}
    </NotificationContext.Provider>
  );
};
