import { useState } from 'react'
import { format } from 'date-fns'
import { PageHeader } from '@/components/PageHeader'
import { LoadingSpinner } from '@/components/LoadingSpinner'
import { useManagerDashboard } from '@/hooks/useManagerDashboard'
import {
  AttendanceStatsCards,
  EmployeesOnLeaveList,
  AbsentEmployeesList,
  LateEmployeesList
} from '@/components/manager-dashboard'
import { Calendar } from '@/components/ui/calendar'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Button } from '@/components/ui/button'
import { CalendarIcon } from 'lucide-react'
import { cn } from '@/lib/utils'

export const ManagerDashboard = () => {
  const [selectedDate, setSelectedDate] = useState<Date>(new Date())
  const { data: dashboardData, isLoading } = useManagerDashboard(selectedDate)

  if (isLoading) {
    return <LoadingSpinner />
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <PageHeader
          title="Manager Dashboard"
          description="Overview of today's attendance and leave status"
        />
        <Popover>
          <PopoverTrigger asChild>
            <Button
              variant="outline"
              className={cn(
                'w-[240px] justify-start text-left font-normal',
                !selectedDate && 'text-muted-foreground'
              )}
            >
              <CalendarIcon className="mr-2 h-4 w-4" />
              {selectedDate ? format(selectedDate, 'PPP') : <span>Pick a date</span>}
            </Button>
          </PopoverTrigger>
          <PopoverContent className="w-auto p-0" align="end">
            <Calendar
              mode="single"
              selected={selectedDate}
              onSelect={(date) => date && setSelectedDate(date)}
              initialFocus
            />
          </PopoverContent>
        </Popover>
      </div>

      {dashboardData && (
        <>
          <AttendanceStatsCards data={dashboardData.attendanceRate} />

          <div className="grid gap-6 md:grid-cols-2">
            <EmployeesOnLeaveList employees={dashboardData.employeesOnLeave} />
            <AbsentEmployeesList employees={dashboardData.absentEmployees} />
          </div>

          <LateEmployeesList employees={dashboardData.lateEmployees} />
        </>
      )}
    </div>
  )
}
