import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { UserPlus } from 'lucide-react';
import { LeaveDialogState } from '@/types/leave';

interface EmployeeSelectorProps {
  employeeUserId: string;
  employees: any[];
  onEmployeeChange: (state: Partial<LeaveDialogState>) => void;
}

export const EmployeeSelector = ({ employeeUserId, employees, onEmployeeChange }: EmployeeSelectorProps) => (
  <div className="space-y-3">
    <Label htmlFor="employee" className="text-base font-semibold flex items-center gap-2">
      <UserPlus className="h-4 w-4" />
      Select Employee
    </Label>
    <Select value={employeeUserId} onValueChange={v => onEmployeeChange({ employeeUserId: v })}>
      <SelectTrigger id="employee">
        <SelectValue placeholder="Choose an employee" />
      </SelectTrigger>
      <SelectContent>
        {employees.length === 0 ? (
          <div className="p-4 text-sm text-muted-foreground text-center">
            No employees available
          </div>
        ) : (
          employees.map((employee: any) => (
            <SelectItem key={employee.id} value={employee.id}>
              <div className="flex flex-col gap-1">
                <span className="font-medium">{employee.fullName || employee.email}</span>
                <span className="text-xs text-muted-foreground">{employee.email}</span>
              </div>
            </SelectItem>
          ))
        )}
      </SelectContent>
    </Select>
  </div>
);
