// ==========================================
// src/pages/MonthlyAttendanceSummary.tsx
// ==========================================
import { PageHeader } from '@/components/PageHeader'
import { MonthlyAttendanceProvider } from '@/contexts/MonthlyAttendanceContext'
import { 
  AttendanceFilterBar, 
  EmployeeInfoHeader, 
  AttendanceStats, 
  AttendanceTable 
} from '@/components/monthly-attendance'

export const MonthlyAttendanceSummary = () => {
  return (
    <MonthlyAttendanceProvider>
      <div className="space-y-4">
        <PageHeader
          title="Monthly Attendance Summary"
          description="View monthly attendance records with shifts and leave information"
        />

        <AttendanceFilterBar />
        
        <EmployeeInfoHeader />
        
        <AttendanceStats />
        
        <AttendanceTable />
      </div>
    </MonthlyAttendanceProvider>
  )
}
