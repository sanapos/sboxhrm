import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { Building2, Users, UserCheck, UserX, Clock } from 'lucide-react'
import { Progress } from '@/components/ui/progress'
import { DepartmentStatistics } from '@/types/dashboard'

interface DepartmentStatsProps {
  departments?: DepartmentStatistics[]
  isLoading?: boolean
}

export const DepartmentStatsCard = ({
  departments,
  isLoading,
}: DepartmentStatsProps) => {
  if (isLoading) {
    return (
      <Card className="col-span-full">
        <CardHeader>
          <CardTitle>Department Statistics</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {[...Array(3)].map((_, i) => (
              <Skeleton key={i} className="h-24 w-full" />
            ))}
          </div>
        </CardContent>
      </Card>
    )
  }

  if (!departments || departments.length === 0) {
    return (
      <Card className="col-span-full">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Building2 className="w-5 h-5" />
            Department Statistics
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center h-[200px] text-muted-foreground">
            No department data available
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card className="col-span-full">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Building2 className="w-5 h-5" />
          Department Statistics
        </CardTitle>
        <p className="text-sm text-muted-foreground">
          Comparative analysis across departments
        </p>
      </CardHeader>
      <CardContent>
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {departments.map((dept) => (
            <div
              key={dept.department}
              className="p-4 rounded-lg border hover:shadow-md transition-shadow"
            >
              <div className="flex items-center justify-between mb-4">
                <h3 className="font-semibold">{dept.department}</h3>
                <div className="flex items-center gap-1 text-xs text-muted-foreground">
                  <Users className="w-3 h-3" />
                  {dept.totalEmployees}
                </div>
              </div>

              <div className="space-y-3">
                {/* Today's Status */}
                <div className="grid grid-cols-3 gap-2 text-xs">
                  <div className="flex flex-col items-center p-2 rounded bg-green-50 dark:bg-green-950/20">
                    <UserCheck className="w-4 h-4 text-green-600 mb-1" />
                    <span className="font-medium">{dept.activeToday}</span>
                    <span className="text-muted-foreground">Active</span>
                  </div>
                  <div className="flex flex-col items-center p-2 rounded bg-red-50 dark:bg-red-950/20">
                    <UserX className="w-4 h-4 text-red-600 mb-1" />
                    <span className="font-medium">{dept.absentToday}</span>
                    <span className="text-muted-foreground">Absent</span>
                  </div>
                  <div className="flex flex-col items-center p-2 rounded bg-yellow-50 dark:bg-yellow-950/20">
                    <Clock className="w-4 h-4 text-yellow-600 mb-1" />
                    <span className="font-medium">{dept.lateToday}</span>
                    <span className="text-muted-foreground">Late</span>
                  </div>
                </div>

                {/* Attendance Rate */}
                <div className="space-y-1">
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-muted-foreground">Attendance Rate</span>
                    <span className="font-medium">
                      {dept.attendanceRate.toFixed(1)}%
                    </span>
                  </div>
                  <Progress value={dept.attendanceRate} />
                </div>

                {/* Punctuality Rate */}
                <div className="space-y-1">
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-muted-foreground">Punctuality</span>
                    <span className="font-medium">
                      {dept.punctualityRate.toFixed(1)}%
                    </span>
                  </div>
                  <Progress value={dept.punctualityRate} />
                </div>

                {/* Average Work Hours */}
                <div className="flex items-center justify-between text-xs pt-2 border-t">
                  <span className="text-muted-foreground">Avg Work Hours</span>
                  <span className="font-medium">{dept.averageWorkHours}</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}
