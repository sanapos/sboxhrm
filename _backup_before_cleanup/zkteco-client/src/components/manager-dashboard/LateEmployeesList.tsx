import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { LateEmployee } from '@/types/manager-dashboard';
import { Clock, AlertCircle, Building2 } from 'lucide-react';
import { format } from 'date-fns';

interface LateEmployeesListProps {
  employees: LateEmployee[];
}

// Parse C# TimeSpan format (e.g., "00:15:00" or "1.02:30:00")
const parseTimeSpan = (timeSpan: string): number => {
  const parts = timeSpan.split(':');
  if (parts.length === 3) {
    const [hours, minutes] = parts;
    if (hours.includes('.')) {
      const [days, hrs] = hours.split('.');
      return parseInt(days) * 24 * 60 + parseInt(hrs) * 60 + parseInt(minutes);
    }
    return parseInt(hours) * 60 + parseInt(minutes);
  }
  return 0;
};

export const LateEmployeesList = ({ employees }: LateEmployeesListProps) => {
  if (employees.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Clock className="h-5 w-5 text-green-600" />
            Late Arrivals
          </CardTitle>
          <CardDescription>Everyone is on time! 👏</CardDescription>
        </CardHeader>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Clock className="h-5 w-5 text-yellow-600" />
          Late Arrivals ({employees.length})
        </CardTitle>
        <CardDescription>Employees who checked in late</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="space-y-3">
          {employees.map((employee) => {
            const lateMinutes = parseTimeSpan(employee.lateBy);
            return (
              <div
                key={employee.employeeUserId}
                className="flex items-start justify-between border-b pb-3 last:border-0"
              >
                <div className="space-y-1">
                  <p className="font-medium">{employee.fullName}</p>
                  <p className="text-sm text-muted-foreground">{employee.email}</p>
                  {employee.department && (
                    <div className="flex items-center gap-1 text-xs text-muted-foreground">
                      <Building2 className="h-3 w-3" />
                      <span>{employee.department}</span>
                    </div>
                  )}
                </div>
                <div className="text-right space-y-1">
                  <Badge variant="outline" className="bg-yellow-50 text-yellow-700 border-yellow-300">
                    <AlertCircle className="h-3 w-3 mr-1" />
                    Late by {lateMinutes}m
                  </Badge>
                  <div className="text-xs text-muted-foreground">
                    <div>Shift: {format(new Date(employee.shiftStartTime), 'h:mm a')}</div>
                    <div>Checked in: {format(new Date(employee.actualCheckInTime), 'h:mm a')}</div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
};
