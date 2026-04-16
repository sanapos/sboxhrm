import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { AbsentEmployee } from '@/types/manager-dashboard';
import { XCircle, Clock, Building2 } from 'lucide-react';
import { format } from 'date-fns';

interface AbsentEmployeesListProps {
  employees: AbsentEmployee[];
}

export const AbsentEmployeesList = ({ employees }: AbsentEmployeesListProps) => {
  if (employees.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <XCircle className="h-5 w-5 text-green-600" />
            Absent Employees
          </CardTitle>
          <CardDescription>All employees checked in! 🎉</CardDescription>
        </CardHeader>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <XCircle className="h-5 w-5 text-red-600" />
          Absent Employees ({employees.length})
        </CardTitle>
        <CardDescription>No check-in recorded yet</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="space-y-3">
          {employees.map((employee) => (
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
              <div className="text-right space-y-1 text-sm">
                <div className="flex items-center gap-1 text-muted-foreground">
                  <Clock className="h-3 w-3" />
                  <span>Shift: {format(new Date(employee.shiftStartTime), 'h:mm a')}</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
};
