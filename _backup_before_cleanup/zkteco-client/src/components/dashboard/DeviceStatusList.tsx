import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { Monitor } from 'lucide-react'
import { format } from 'date-fns'
import { DeviceStatus } from '@/types/dashboard'

interface DeviceStatusListProps {
  devices?: DeviceStatus[]
  isLoading?: boolean
}

export const DeviceStatusList = ({
  devices,
  isLoading,
}: DeviceStatusListProps) => {
  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Device Status</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {[...Array(5)].map((_, i) => (
              <div key={i} className="flex items-center justify-between">
                <Skeleton className="h-12 w-full" />
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    )
  }

  if (!devices || devices.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Device Status</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center h-[200px] text-muted-foreground">
            No devices found
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Device Status</CardTitle>
        <p className="text-sm text-muted-foreground">
          Real-time status of all devices
        </p>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          {devices.map((device) => (
            <div
              key={device.deviceId}
              className="flex items-center justify-between p-3 rounded-lg border hover:bg-accent/50 transition-colors"
            >
              <div className="flex items-center gap-3">
                <div className="relative">
                  <Monitor className="w-8 h-8 text-muted-foreground" />
                  <div
                    className={`absolute -bottom-1 -right-1 w-3 h-3 rounded-full border-2 border-background ${
                      device.status === 'Online'
                        ? 'bg-green-500'
                        : 'bg-gray-400'
                    }`}
                  />
                </div>
                <div>
                  <p className="font-medium">{device.deviceName}</p>
                  <p className="text-xs text-muted-foreground">
                    {device.location || 'No location'}
                  </p>
                  {device.lastOnline && (
                    <p className="text-xs text-muted-foreground">
                      Last seen: {format(new Date(device.lastOnline), 'PPp')}
                    </p>
                  )}
                </div>
              </div>
              <div className="flex flex-col items-end gap-2">
                <Badge
                  variant={device.status === 'Online' ? 'success' : 'secondary'}
                >
                  {device.status}
                </Badge>
                <div className="text-xs text-muted-foreground">
                  {device.registeredUsers} users · {device.todayAttendances}{' '}
                  today
                </div>
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}
