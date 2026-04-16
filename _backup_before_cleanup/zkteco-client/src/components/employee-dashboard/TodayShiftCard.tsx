import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Clock, Calendar } from "lucide-react";
import { ShiftInfo } from "@/types/employee-dashboard";
import { format, parseISO } from "date-fns";

interface TodayShiftCardProps {
  shift: ShiftInfo | null;
  isLoading?: boolean;
}

export const TodayShiftCard = ({ shift, isLoading }: TodayShiftCardProps) => {
  if (isLoading) {
    return (
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Current Shift</CardTitle>
          <Calendar className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center h-20">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary"></div>
          </div>
        </CardContent>
      </Card>
    );
  }

  if (!shift) {
    return (
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Current Shift</CardTitle>
          <Calendar className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div className="text-sm text-muted-foreground">No shift scheduled for today</div>
        </CardContent>
      </Card>
    );
  }

  const startTime = format(parseISO(shift.startTime), "h:mm a");
  const endTime = format(parseISO(shift.endTime), "h:mm a");

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">Current Shift</CardTitle>
        <Calendar className="h-4 w-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <Clock className="h-4 w-4 text-muted-foreground" />
            <span className="text-2xl font-bold">
              {startTime} - {endTime}
            </span>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Duration:</span>
            <span className="font-medium">{shift.totalHours} hours</span>
          </div>
          {shift.description && (
            <div className="text-sm text-muted-foreground mt-2">
              {shift.description}
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
};
