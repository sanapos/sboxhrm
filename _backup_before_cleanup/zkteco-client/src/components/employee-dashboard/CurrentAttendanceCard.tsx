import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ClockIcon, LogIn, LogOut } from "lucide-react";
import { AttendanceInfo } from "@/types/employee-dashboard";
import { format, parseISO } from "date-fns";
import { Badge } from "@/components/ui/badge";

interface CurrentAttendanceCardProps {
  attendance: AttendanceInfo | null;
  isLoading?: boolean;
}

export const CurrentAttendanceCard = ({ attendance, isLoading }: CurrentAttendanceCardProps) => {
  if (isLoading) {
    return (
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Current Attendance</CardTitle>
          <ClockIcon className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center h-20">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary"></div>
          </div>
        </CardContent>
      </Card>
    );
  }

  if (!attendance) {
    return (
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Current Attendance</CardTitle>
          <ClockIcon className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div className="text-sm text-muted-foreground">No attendance record for today</div>
        </CardContent>
      </Card>
    );
  }

  const getStatusBadge = () => {
    if (attendance.status === 'checked-out') {
      return <Badge variant="secondary">Checked Out</Badge>;
    } else if (attendance.status === 'checked-in') {
      return <Badge variant="default" className="bg-green-600">Active</Badge>;
    }
    return <Badge variant="outline">Not Started</Badge>;
  };

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">Current Attendance</CardTitle>
        <ClockIcon className="h-4 w-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground">Status:</span>
            {getStatusBadge()}
          </div>

          {attendance.checkInTime && (
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <LogIn className="h-4 w-4 text-green-600" />
                <span className="text-sm text-muted-foreground">Check In:</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="font-medium">
                  {format(parseISO(attendance.checkInTime), "h:mm a")}
                </span>
                {attendance.isLate && (
                  <Badge variant="destructive" className="text-xs">
                    Late {attendance.lateMinutes}m
                  </Badge>
                )}
              </div>
            </div>
          )}

          {attendance.checkOutTime && (
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <LogOut className="h-4 w-4 text-orange-600" />
                <span className="text-sm text-muted-foreground">Check Out:</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="font-medium">
                  {format(parseISO(attendance.checkOutTime), "h:mm a")}
                </span>
                {attendance.isEarlyOut && (
                  <Badge variant="destructive" className="text-xs">
                    Early {attendance.earlyOutMinutes}m
                  </Badge>
                )}
              </div>
            </div>
          )}

          {attendance.status === 'checked-in' && attendance.checkInTime && (
            <div className="flex items-center justify-between pt-2 border-t">
              <span className="text-sm text-muted-foreground">Working Time:</span>
              <span className="text-lg font-bold text-green-600">
                {Math.floor(attendance.workHours)} hrs {Math.round((attendance.workHours % 1) * 60)} min
              </span>
            </div>
          )}

          {attendance.status === 'checked-out' && (
            <div className="flex items-center justify-between pt-2 border-t">
              <span className="text-sm text-muted-foreground">Total Work Hours:</span>
              <span className="text-lg font-bold">
                {Math.floor(attendance.workHours)} hrs {Math.round((attendance.workHours % 1) * 60)} min
              </span>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
};
