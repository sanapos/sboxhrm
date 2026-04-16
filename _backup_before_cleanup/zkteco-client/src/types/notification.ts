// ============ NOTIFICATION TYPES ============

export enum NotificationType {
  INFO = 0,
  WARNING = 1,
  ERROR = 2,
  SUCCESS = 3,
  LEAVE_REQUEST = 4,
  ADVANCE_REQUEST = 5,
  ATTENDANCE_CORRECTION = 6,
  SCHEDULE_REGISTRATION = 7,
  PAYSLIP = 8,
  SYSTEM = 9
}

export const getNotificationTypeLabel = (type: NotificationType): string => {
  switch (type) {
    case NotificationType.INFO:
      return 'Thông tin';
    case NotificationType.WARNING:
      return 'Cảnh báo';
    case NotificationType.ERROR:
      return 'Lỗi';
    case NotificationType.SUCCESS:
      return 'Thành công';
    case NotificationType.LEAVE_REQUEST:
      return 'Nghỉ phép';
    case NotificationType.ADVANCE_REQUEST:
      return 'Ứng lương';
    case NotificationType.ATTENDANCE_CORRECTION:
      return 'Sửa chấm công';
    case NotificationType.SCHEDULE_REGISTRATION:
      return 'Đăng ký lịch';
    case NotificationType.PAYSLIP:
      return 'Bảng lương';
    case NotificationType.SYSTEM:
      return 'Hệ thống';
    default:
      return 'Khác';
  }
};

export const getNotificationTypeIcon = (type: NotificationType): string => {
  switch (type) {
    case NotificationType.INFO:
      return '📋';
    case NotificationType.WARNING:
      return '⚠️';
    case NotificationType.ERROR:
      return '❌';
    case NotificationType.SUCCESS:
      return '✅';
    case NotificationType.LEAVE_REQUEST:
      return '🏖️';
    case NotificationType.ADVANCE_REQUEST:
      return '💰';
    case NotificationType.ATTENDANCE_CORRECTION:
      return '⏰';
    case NotificationType.SCHEDULE_REGISTRATION:
      return '📅';
    case NotificationType.PAYSLIP:
      return '💵';
    case NotificationType.SYSTEM:
      return '⚙️';
    default:
      return '📌';
  }
};

export interface AppNotification {
  id: string;
  userId: string;
  title: string;
  message: string;
  type: NotificationType;
  isRead: boolean;
  readAt?: string;
  actionUrl?: string;
  relatedEntityId?: string;
  relatedEntityType?: string;
  createdAt: string;
}

export interface CreateNotificationRequest {
  userId: string;
  title: string;
  message: string;
  type: NotificationType;
  actionUrl?: string;
  relatedEntityId?: string;
  relatedEntityType?: string;
}

export interface BulkCreateNotificationRequest {
  userIds: string[];
  title: string;
  message: string;
  type: NotificationType;
  actionUrl?: string;
}

export interface NotificationQueryParams {
  page?: number;
  pageSize?: number;
  isRead?: boolean;
  type?: NotificationType;
}

export interface NotificationSummary {
  totalCount: number;
  unreadCount: number;
  recentNotifications: AppNotification[];
}
