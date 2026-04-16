import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { Trophy, Clock, Calendar } from 'lucide-react'
import { Progress } from '@/components/ui/progress'
import { EmployeePerformance } from '@/types/dashboard'

interface TopPerformersListProps {
  performers?: EmployeePerformance[]
  isLoading?: boolean
}

export const TopPerformersList = ({
  performers,
  isLoading,
}: TopPerformersListProps) => {
  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Top Performers</CardTitle>
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

  if (!performers || performers.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Trophy className="w-5 h-5" />
            Top Performers
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center h-[200px] text-muted-foreground">
            No performance data available
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Trophy className="w-5 h-5 text-yellow-500" />
          Top Performers
        </CardTitle>
        <p className="text-sm text-muted-foreground">
          Employees with best attendance and punctuality
        </p>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          {performers.map((performer, index) => (
            <div
              key={performer.userId}
              className="p-4 rounded-lg border hover:bg-accent/50 transition-colors"
            >
              <div className="flex items-start justify-between mb-3">
                <div className="flex items-center gap-3">
                  <div className="flex items-center justify-center w-8 h-8 rounded-full bg-primary/10 font-bold text-primary">
                    {index + 1}
                  </div>
                  <div>
                    <p className="font-medium">{performer.fullName}</p>
                    <p className="text-xs text-muted-foreground">
                      {performer.department}
                    </p>
                  </div>
                </div>
                <Badge variant="success">
                  {performer.attendanceRate.toFixed(1)}%
                </Badge>
              </div>

              <div className="grid grid-cols-2 gap-2 mb-3">
                <div className="flex items-center gap-2 text-xs">
                  <Calendar className="w-3 h-3 text-muted-foreground" />
                  <span className="text-muted-foreground">
                    {performer.totalAttendanceDays} days attended
                  </span>
                </div>
                <div className="flex items-center gap-2 text-xs">
                  <Clock className="w-3 h-3 text-muted-foreground" />
                  <span className="text-muted-foreground">
                    {performer.onTimeDays} on-time
                  </span>
                </div>
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between text-xs">
                  <span className="text-muted-foreground">Punctuality</span>
                  <span className="font-medium">
                    {performer.punctualityRate.toFixed(1)}%
                  </span>
                </div>
                <Progress value={performer.punctualityRate} />
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}
