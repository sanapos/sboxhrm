import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { CalendarClock } from "lucide-react";
import { ShiftInfo } from "@/types/employee-dashboard";
import { format, parseISO } from "date-fns";

interface NextShiftCardProps {
  shift: ShiftInfo | null;
  isLoading?: boolean;
}

export const NextShiftCard = ({ shift, isLoading }: NextShiftCardProps) => {
  if (isLoading) {
    return (
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Next Shift</CardTitle>
          <CalendarClock className="h-4 w-4 text-muted-foreground" />
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
          <CardTitle className="text-sm font-medium">Next Shift</CardTitle>
          <CalendarClock className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div className="text-sm text-muted-foreground">No upcoming shift scheduled</div>
        </CardContent>
      </Card>
    );
  }

  const shiftDate = format(parseISO(shift.startTime), "EEEE, MMM d");
  const startTime = format(parseISO(shift.startTime), "h:mm a");
  const endTime = format(parseISO(shift.endTime), "h:mm a");

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">Next Shift</CardTitle>
        <CalendarClock className="h-4 w-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="space-y-2">
          <div className="text-lg font-semibold">{shiftDate}</div>
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground text-sm">Time:</span>
            <span className="font-medium">
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
