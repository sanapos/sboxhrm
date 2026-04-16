import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { EmployeeOnLeave } from '@/types/manager-dashboard';
import { Coffee, Calendar, Clock } from 'lucide-react';
import { format } from 'date-fns';

interface EmployeesOnLeaveListProps {
  employees: EmployeeOnLeave[];
}

export const EmployeesOnLeaveList = ({ employees }: EmployeesOnLeaveListProps) => {
  if (employees.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Coffee className="h-5 w-5" />
            Employees on Leave
          </CardTitle>
          <CardDescription>No employees on leave today</CardDescription>
        </CardHeader>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Coffee className="h-5 w-5" />
          Employees on Leave ({employees.length})
        </CardTitle>
        <CardDescription>Approved leaves for today</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          {employees.map((employee) => (
            <div
              key={employee.leaveId}
              className="flex items-start justify-between border-b pb-4 last:border-0"
            >
              <div className="space-y-1">
                <p className="font-medium">{employee.fullName}</p>
                <p className="text-sm text-muted-foreground">{employee.email}</p>
                <div className="flex items-center gap-2 text-sm">
                  <Badge variant="outline">{employee.leaveType}</Badge>
                  <Badge variant="secondary">
                    {employee.isFullDay ? 'Full Day' : 'Half Day'}
                  </Badge>
                </div>
                <p className="text-xs text-muted-foreground mt-2">{employee.reason}</p>
              </div>
              <div className="text-right space-y-1 text-sm text-muted-foreground">
                <div className="flex items-center gap-1">
                  <Calendar className="h-3 w-3" />
                  <span>{format(new Date(employee.leaveStartDate), 'MMM dd')}</span>
                </div>
                <div className="flex items-center gap-1">
                  <Clock className="h-3 w-3" />
                  <span>
                    {format(new Date(employee.shiftStartTime), 'h:mm a')} -{' '}
                    {format(new Date(employee.shiftEndTime), 'h:mm a')}
                  </span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
};
