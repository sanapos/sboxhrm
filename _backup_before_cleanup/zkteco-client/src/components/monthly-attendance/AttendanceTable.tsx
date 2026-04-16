// ==========================================
// src/components/monthly-attendance/AttendanceTable.tsx
// ==========================================
import { Card, CardContent } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { Calendar, Clock, CheckCircle, XCircle } from 'lucide-react'
import { format, parseISO } from 'date-fns'
import { useMonthlyAttendanceContext } from '@/contexts/MonthlyAttendanceContext'
import { DailyAttendance, LeaveType, LeaveStatus } from '@/types/attendance'

const getLeaveTypeLabel = (type: number): string => {
  switch (type) {
    case LeaveType.Sick: return 'Sick Leave'
    case LeaveType.Vacation: return 'Vacation'
    case LeaveType.Personal: return 'Personal'
    case LeaveType.Other: return 'Other'
    default: return 'Unknown'
  }
}

const getLeaveStatusBadge = (status: number) => {
  switch (status) {
    case LeaveStatus.Approved:
      return <Badge className="bg-green-500">Approved</Badge>
    case LeaveStatus.Pending:
      return <Badge className="bg-yellow-500">Pending</Badge>
    case LeaveStatus.Rejected:
      return <Badge className="bg-red-500">Rejected</Badge>
    case LeaveStatus.Cancelled:
      return <Badge className="bg-gray-500">Cancelled</Badge>
    default:
      return <Badge>Unknown</Badge>
  }
}

const formatTime = (dateString?: string) => {
  if (!dateString) return '-'
  try {
    return format(parseISO(dateString), 'HH:mm')
  } catch {
    return '-'
  }
}

const formatDate = (dateString: string) => {
  try {
    return format(parseISO(dateString), 'EEE, dd MMM')
  } catch {
    return dateString
  }
}

const calculateWorkHours = (checkIn?: string, checkOut?: string) => {
  if (!checkIn || !checkOut) return '-'
  try {
    const start = parseISO(checkIn)
    const end = parseISO(checkOut)
    const hours = (end.getTime() - start.getTime()) / (1000 * 60 * 60)
    return `${hours.toFixed(1)}h`
  } catch {
    return '-'
  }
}

export const AttendanceTable = () => {
  const { data, isLoading, error } = useMonthlyAttendanceContext()

  return (
    <Card>
      <CardContent className="pt-6">
        {isLoading ? (
          <div className="space-y-2">
            {[...Array(5)].map((_, i) => (
              <Skeleton key={i} className="h-16 w-full" />
            ))}
          </div>
        ) : error ? (
          <div className="text-center py-8 text-red-500">
            Error loading attendance data
          </div>
        ) : !data?.dailyRecords?.length ? (
          <div className="text-center py-8 text-muted-foreground">
            No attendance records found for this period
          </div>
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[120px]">Date</TableHead>
                  <TableHead className="w-[100px]">Check In</TableHead>
                  <TableHead className="w-[100px]">Check Out</TableHead>
                  <TableHead className="w-[80px]">Hours</TableHead>
                  <TableHead className="w-[150px]">Device</TableHead>
                  <TableHead className="w-[200px]">Shift</TableHead>
                  <TableHead className="w-[200px]">Leave</TableHead>
                  <TableHead className="w-[80px]">Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.dailyRecords.map((day: DailyAttendance) => {
                  const hasRecords = day.attendances.length > 0
                  const firstRecord = day.attendances[0]
                  
                  return (
                    <TableRow key={day.date} className={day.isLeave ? 'bg-orange-50' : ''}>
                      <TableCell className="font-medium">
                        <div className="flex items-center gap-2">
                          <Calendar className="h-4 w-4 text-muted-foreground" />
                          {formatDate(day.date)}
                        </div>
                      </TableCell>
                      <TableCell>
                        {hasRecords ? (
                          <div className="flex items-center gap-1">
                            <Clock className="h-3 w-3 text-green-500" />
                            {formatTime(firstRecord.checkInTime)}
                          </div>
                        ) : (
                          <span className="text-muted-foreground">-</span>
                        )}
                      </TableCell>
                      <TableCell>
                        {hasRecords ? (
                          <div className="flex items-center gap-1">
                            <Clock className="h-3 w-3 text-red-500" />
                            {formatTime(firstRecord.checkOutTime)}
                          </div>
                        ) : (
                          <span className="text-muted-foreground">-</span>
                        )}
                      </TableCell>
                      <TableCell>
                        {hasRecords ? (
                          calculateWorkHours(firstRecord.checkInTime, firstRecord.checkOutTime)
                        ) : (
                          <span className="text-muted-foreground">-</span>
                        )}
                      </TableCell>
                      <TableCell className="text-sm">
                        {hasRecords ? (
                          firstRecord.deviceName
                        ) : (
                          <span className="text-muted-foreground">-</span>
                        )}
                      </TableCell>
                      <TableCell>
                        {day.shift ? (
                          <div className="space-y-1">
                            <div className="text-sm">
                              {formatTime(day.shift.startTime)} - {formatTime(day.shift.endTime)}
                            </div>
                            {day.shift.description && (
                              <div className="text-xs text-muted-foreground">
                                {day.shift.description}
                              </div>
                            )}
                          </div>
                        ) : (
                          <span className="text-muted-foreground">No shift</span>
                        )}
                      </TableCell>
                      <TableCell>
                        {day.leave ? (
                          <div className="space-y-1">
                            <div className="text-sm font-medium">
                              {getLeaveTypeLabel(day.leave.type)}
                              {day.leave.isHalfShift && (
                                <span className="text-xs ml-1">(Half)</span>
                              )}
                            </div>
                            <div className="text-xs text-muted-foreground">
                              {day.leave.reason}
                            </div>
                            {getLeaveStatusBadge(day.leave.status)}
                          </div>
                        ) : (
                          <span className="text-muted-foreground">-</span>
                        )}
                      </TableCell>
                      <TableCell>
                        {day.isLeave ? (
                          <XCircle className="h-5 w-5 text-orange-500" />
                        ) : hasRecords ? (
                          <CheckCircle className="h-5 w-5 text-green-500" />
                        ) : (
                          <XCircle className="h-5 w-5 text-gray-300" />
                        )}
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
