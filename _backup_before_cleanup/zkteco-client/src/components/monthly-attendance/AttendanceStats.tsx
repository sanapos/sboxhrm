// ==========================================
// src/components/monthly-attendance/AttendanceStats.tsx
// ==========================================
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useMonthlyAttendanceContext } from '@/contexts/MonthlyAttendanceContext'
import { DailyAttendance } from '@/types/attendance'

export const AttendanceStats = () => {
  const { data } = useMonthlyAttendanceContext()

  if (!data || !data.dailyRecords) return null

  const totalDays = data.dailyRecords.length
  const daysPresent = data.dailyRecords.filter((d: DailyAttendance) => d.attendances.length > 0).length
  const daysOnLeave = data.dailyRecords.filter((d: DailyAttendance) => d.isLeave).length
  const scheduledShifts = data.dailyRecords.filter((d: DailyAttendance) => d.hasShift).length

  return (
    <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium text-muted-foreground">
            Total Days
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold">
            {totalDays}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium text-muted-foreground">
            Days Present
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold text-green-600">
            {daysPresent}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium text-muted-foreground">
            Days on Leave
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold text-orange-600">
            {daysOnLeave}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium text-muted-foreground">
            Scheduled Shifts
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold text-blue-600">
            {scheduledShifts}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
