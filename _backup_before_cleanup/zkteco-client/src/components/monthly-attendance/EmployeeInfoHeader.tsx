// ==========================================
// src/components/monthly-attendance/EmployeeInfoHeader.tsx
// ==========================================
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { useMonthlyAttendanceContext } from '@/contexts/MonthlyAttendanceContext'

const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
]

export const EmployeeInfoHeader = () => {
  const { data, selectedMonth, selectedYear } = useMonthlyAttendanceContext()

  if (!data || !data.dailyRecords) return null

  return (
    <Card>
      <CardContent className="pt-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-2xl font-bold">{data.employeeName}</h2>
            <p className="text-sm text-muted-foreground">
              {MONTHS[selectedMonth - 1]} {selectedYear} Attendance Summary
            </p>
          </div>
          <Badge variant="outline" className="text-sm">
            {data.dailyRecords?.length || 0} Days
          </Badge>
        </div>
      </CardContent>
    </Card>
  )
}
