import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Bell, Check, Trash2, MailOpen } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { NotificationProvider, useNotificationContext } from "@/contexts/NotificationContext";
import { 
  AppNotification,
  NotificationType, 
  getNotificationTypeLabel, 
  getNotificationTypeIcon 
} from "@/types/notification";
import { formatDistanceToNow } from "date-fns";
import { vi } from "date-fns/locale";
import { useNavigate } from "react-router-dom";

const NotificationsHeader = () => {
  const { unreadCount, markAllAsRead, deleteAllRead } = useNotificationContext();

  return (
    <PageHeader
      title="Thông báo"
      description={`Bạn có ${unreadCount} thông báo chưa đọc`}
      action={
        <div className="flex gap-2">
          <Button variant="outline" onClick={markAllAsRead} disabled={unreadCount === 0}>
            <MailOpen className="mr-2 h-4 w-4" />
            Đánh dấu tất cả đã đọc
          </Button>
          <Button variant="outline" onClick={deleteAllRead}>
            <Trash2 className="mr-2 h-4 w-4" />
            Xóa đã đọc
          </Button>
        </div>
      }
    />
  );
};

const NotificationsSummary = () => {
  const { summary, isLoading } = useNotificationContext();

  if (isLoading || !summary) {
    return null;
  }

  return (
    <div className="grid gap-4 md:grid-cols-2 mb-6">
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Tổng thông báo</CardTitle>
          <Bell className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold">{summary.totalCount}</div>
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Chưa đọc</CardTitle>
          <Bell className="h-4 w-4 text-blue-500" />
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold text-blue-600">{summary.unreadCount}</div>
        </CardContent>
      </Card>
    </div>
  );
};

interface NotificationItemProps {
  notification: AppNotification;
  onRead: (id: string) => void;
  onDelete: (id: string) => void;
}

const NotificationItem = ({ notification, onRead, onDelete }: NotificationItemProps) => {
  const navigate = useNavigate();

  const handleClick = () => {
    if (!notification.isRead) {
      onRead(notification.id);
    }
    if (notification.actionUrl) {
      navigate(notification.actionUrl);
    }
  };

  const getTypeColor = (type: NotificationType): string => {
    switch (type) {
      case NotificationType.INFO:
        return 'bg-blue-100 text-blue-800';
      case NotificationType.WARNING:
        return 'bg-yellow-100 text-yellow-800';
      case NotificationType.ERROR:
        return 'bg-red-100 text-red-800';
      case NotificationType.SUCCESS:
        return 'bg-green-100 text-green-800';
      case NotificationType.LEAVE_REQUEST:
        return 'bg-purple-100 text-purple-800';
      case NotificationType.ADVANCE_REQUEST:
        return 'bg-orange-100 text-orange-800';
      case NotificationType.ATTENDANCE_CORRECTION:
        return 'bg-cyan-100 text-cyan-800';
      case NotificationType.SCHEDULE_REGISTRATION:
        return 'bg-indigo-100 text-indigo-800';
      case NotificationType.PAYSLIP:
        return 'bg-emerald-100 text-emerald-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  return (
    <div
      className={`p-4 rounded-lg cursor-pointer transition-colors ${
        notification.isRead ? 'bg-gray-50 hover:bg-gray-100' : 'bg-blue-50 hover:bg-blue-100'
      }`}
      onClick={handleClick}
    >
      <div className="flex items-start gap-3">
        <span className="text-2xl">{getNotificationTypeIcon(notification.type)}</span>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <h4 className={`font-medium truncate ${!notification.isRead ? 'text-blue-900' : ''}`}>
              {notification.title}
            </h4>
            {!notification.isRead && (
              <Badge className="bg-blue-500 text-white text-xs">Mới</Badge>
            )}
          </div>
          <p className="text-sm text-muted-foreground line-clamp-2">{notification.message}</p>
          <div className="flex items-center gap-2 mt-2">
            <Badge variant="outline" className={getTypeColor(notification.type)}>
              {getNotificationTypeLabel(notification.type)}
            </Badge>
            <span className="text-xs text-muted-foreground">
              {formatDistanceToNow(new Date(notification.createdAt), { addSuffix: true, locale: vi })}
            </span>
          </div>
        </div>
        <div className="flex items-center gap-1">
          {!notification.isRead && (
            <Button
              size="icon"
              variant="ghost"
              onClick={(e) => {
                e.stopPropagation();
                onRead(notification.id);
              }}
            >
              <Check className="h-4 w-4" />
            </Button>
          )}
          <Button
            size="icon"
            variant="ghost"
            className="text-red-500 hover:text-red-700"
            onClick={(e) => {
              e.stopPropagation();
              onDelete(notification.id);
            }}
          >
            <Trash2 className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </div>
  );
};

const NotificationsList = () => {
  const { notifications, isLoading, markAsRead, deleteNotification } = useNotificationContext();

  if (isLoading) {
    return <div className="text-center py-8">Đang tải...</div>;
  }

  if (!notifications || notifications.length === 0) {
    return (
      <div className="text-center py-12">
        <Bell className="mx-auto h-12 w-12 text-muted-foreground" />
        <h3 className="mt-4 text-lg font-medium">Không có thông báo</h3>
        <p className="mt-2 text-sm text-muted-foreground">
          Bạn chưa có thông báo nào. Thông báo mới sẽ xuất hiện ở đây.
        </p>
      </div>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Danh sách thông báo</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="h-[600px] overflow-y-auto">
          <div className="space-y-3">
            {notifications.map((notification, index) => (
              <div key={notification.id}>
                <NotificationItem
                  notification={notification}
                  onRead={markAsRead}
                  onDelete={deleteNotification}
                />
                {index < notifications.length - 1 && <Separator className="my-3" />}
              </div>
            ))}
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

const NotificationsContent = () => {
  return (
    <div className="container mx-auto py-6">
      <NotificationsHeader />
      <div className="mt-6">
        <NotificationsSummary />
        <NotificationsList />
      </div>
    </div>
  );
};

const Notifications = () => {
  return (
    <NotificationProvider>
      <NotificationsContent />
    </NotificationProvider>
  );
};

export default Notifications;
