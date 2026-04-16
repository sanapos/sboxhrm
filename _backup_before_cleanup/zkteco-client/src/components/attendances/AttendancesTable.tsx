import { Card, CardContent } from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'
import { format } from 'date-fns'
import { Clock, Calendar } from 'lucide-react'
import type { AttendanceLog } from '@/types'
import { LoadingSpinner } from '../LoadingSpinner'

// VerifyModes enum mapping - based on ZKTeco default mapped values in AttLog
const verifyTypeMap: { [key: number]: string } = {
  0: 'Password',
  1: 'Fingerprint',
  2: 'Card/Badge',
  3: 'PIN',
  4: 'PIN & Fingerprint',
  5: 'Finger & Password',
  6: 'Badge & Finger',
  7: 'Badge & Password',
  8: 'Badge & Password & Finger',
  9: 'PIN & Password & Finger',
}

// AttendanceStates enum mapping
const verifyStateMap: { [key: number]: string } = {
  0: 'Check In',
  1: 'Check Out',
  2: 'Meal In',
  3: 'Meal Out',
  4: 'Break In',
  5: 'Break Out',
}

interface AttendancesTableProps {
  logs: AttendanceLog[] | undefined
  isLoading: boolean
}

export const AttendancesTable = ({ logs, isLoading }: AttendancesTableProps) => {

  if(isLoading){
      return (
          <LoadingSpinner></LoadingSpinner>
      )
  }
  return (
    <Card>
      <CardContent className="p-0">
        {!logs || logs.length === 0 ? (
          <div className="text-center py-12">   
            <Clock className="w-12 h-12 mx-auto text-muted-foreground mb-4" />
            <h3 className="text-lg font-semibold mb-2">No attendance logs</h3>
            <p className="text-muted-foreground">
              Attendance logs will appear here when devices push data
            </p>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Date & Time</TableHead>
                <TableHead>User Name</TableHead>
                <TableHead>Device</TableHead>
                <TableHead>Verify Type</TableHead>
                <TableHead>Attendance State</TableHead>
                <TableHead>Work Code</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {logs.map((log) => (
                <TableRow key={log.id}>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <Calendar className="w-4 h-4 text-muted-foreground" />
                      <span>
                        {format(
                          new Date(log.attendanceTime),
                          'MMM dd, yyyy HH:mm:ss'
                        )}
                      </span>
                    </div>
                  </TableCell>
                  <TableCell className="font-medium">
                    {log.userName|| '-'}
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {log.deviceName || '-'}
                  </TableCell>
                  <TableCell>
                    <Badge variant="outline">
                      {verifyTypeMap[log.verifyType || 0] || 'Unknown'}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <Badge
                      variant={log.attendanceState === 0 ? 'default' : 'secondary'}
                    >
                      {verifyStateMap[log.attendanceState] || 'Unknown'}
                    </Badge>
                  </TableCell>
                  <TableCell className="font-medium">
                    {log.workCode|| '-'}
                  </TableCell>
                  {/* <TableCell>
                    {log.temperature ? `${log.temperature}°C` : '-'}
                  </TableCell>
                  <TableCell>
                    <Badge variant={log.isProcessed ? 'default' : 'outline'}>
                      {log.isProcessed ? 'Processed' : 'Pending'}
                    </Badge>
                  </TableCell> */}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}
