import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { AlertTriangle, Clock } from 'lucide-react'
import { EmployeePerformance } from '@/types/dashboard'

interface LateEmployeesListProps {
  employees?: EmployeePerformance[]
  isLoading?: boolean
}

export const LateEmployeesList = ({
  employees,
  isLoading,
}: LateEmployeesListProps) => {
  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Late Employees</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {[...Array(5)].map((_, i) => (
              <Skeleton key={i} className="h-20 w-full" />
            ))}
          </div>
        </CardContent>
      </Card>
    )
  }

  if (!employees || employees.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <AlertTriangle className="w-5 h-5" />
            Late Employees
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col items-center justify-center h-[200px] text-muted-foreground">
            <p className="text-green-600 font-medium">Great news!</p>
            <p className="text-sm">No employees with tardiness issues</p>
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <AlertTriangle className="w-5 h-5 text-yellow-500" />
          Late Employees
        </CardTitle>
        <p className="text-sm text-muted-foreground">
          Employees requiring attendance attention
        </p>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          {employees.map((employee) => (
            <div
              key={employee.userId}
              className="p-4 rounded-lg border border-yellow-200 bg-yellow-50/50 dark:bg-yellow-950/20 dark:border-yellow-900"
            >
              <div className="flex items-start justify-between mb-3">
                <div>
                  <p className="font-medium">{employee.fullName}</p>
                  <p className="text-xs text-muted-foreground">
                    {employee.department}
                  </p>
                </div>
                <Badge variant="warning">{employee.lateDays} late days</Badge>
              </div>

              <div className="grid grid-cols-2 gap-2 text-xs">
                <div>
                  <span className="text-muted-foreground">Attendance Rate:</span>
                  <p className="font-medium">
                    {employee.attendanceRate.toFixed(1)}%
                  </p>
                </div>
                <div>
                  <span className="text-muted-foreground">Punctuality:</span>
                  <p className="font-medium">
                    {employee.punctualityRate.toFixed(1)}%
                  </p>
                </div>
                <div>
                  <span className="text-muted-foreground">Absent Days:</span>
                  <p className="font-medium">{employee.absentDays}</p>
                </div>
                {employee.averageLateTime && (
                  <div className="flex items-center gap-1">
                    <Clock className="w-3 h-3 text-muted-foreground" />
                    <span className="text-muted-foreground">
                      Avg late: {employee.averageLateTime}
                    </span>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}
