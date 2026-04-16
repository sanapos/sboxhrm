// ==========================================
// src/components/device-commands/CommandCenter.tsx
// ==========================================
import { Device } from '@/types'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { RefreshCw, Users, Download, Trash2, RefreshCcwDot } from 'lucide-react'
import { useDeviceCommands } from '@/hooks/useDeviceCommands'

interface CommandCenterProps {
  devices: Device[]
  selectedDeviceId: string
  onDeviceChange: (deviceId: string) => void
  onRefresh: () => void
  isDeviceInactive?: boolean
}

export const CommandCenter = ({
  devices,
  selectedDeviceId,
  onDeviceChange,
  onRefresh,
  isDeviceInactive = false,
}: CommandCenterProps) => {
  const {
    handleSyncUsers,
    handleClearAttendances,
    handleClearUsers,
    handleSyncAttendances,
    handleRestartDevice,
  } = useDeviceCommands({
    onSuccess: onRefresh,
  })

  return (
    <Card>
      <CardHeader>
        <CardTitle>Command Center</CardTitle>
        <CardDescription>
          Select a device and execute commands to manage users, attendance, and device operations
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Device Selector */}
        <div className="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-4">
          <label className="text-sm font-medium sm:min-w-20">Device:</label>
          <div className="flex gap-2 flex-1">
            <Select value={selectedDeviceId} onValueChange={onDeviceChange}>
              <SelectTrigger className="flex-1">
                <SelectValue placeholder="Select a device" />
              </SelectTrigger>
              <SelectContent>
                {devices.map((device) => (
                  <SelectItem key={device.id} value={device.id}>
                    {device.deviceName} - {device.serialNumber}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button
              variant="outline"
              size="icon"
              onClick={onRefresh}
              disabled={!selectedDeviceId || isDeviceInactive}
              className="shrink-0"
            >
              <RefreshCw className="w-4 h-4" />
            </Button>
          </div>
        </div>

        {/* Command Buttons */}
        {selectedDeviceId && (
          <div className="space-y-3">
            <div className="text-sm font-medium">Available Commands:</div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-3">
              <Button
                variant="outline"
                className="flex items-center justify-center gap-2 h-auto py-3"
                onClick={() => handleSyncUsers(selectedDeviceId)}
                disabled={isDeviceInactive}
              >
                <Users className="w-4 h-4" />
                <span>Sync Users</span>
              </Button>
              <Button
                variant="outline"
                className="flex items-center justify-center gap-2 h-auto py-3"
                onClick={() => handleSyncAttendances(selectedDeviceId)}
                disabled={isDeviceInactive}
              >
                <Download className="w-4 h-4" />
                <span>Sync Attendance</span>
              </Button>
              <Button
                variant="outline"
                className="flex items-center justify-center gap-2 h-auto py-3"
                onClick={() => handleClearAttendances(selectedDeviceId)}
                disabled={isDeviceInactive}
              >
                <Trash2 className="w-4 h-4 text-red-500" />
                <span>Clear Attendance</span>
              </Button>
              <Button
                variant="outline"
                className="flex items-center justify-center gap-2 h-auto py-3"
                onClick={() => handleClearUsers(selectedDeviceId)}
                disabled={isDeviceInactive}
              >
                <Trash2 className="w-4 h-4 text-red-500" />
                <span>Clear Users</span>
              </Button>
              <Button
                variant="outline"
                className="flex items-center justify-center gap-2 h-auto py-3"
                onClick={() => handleRestartDevice(selectedDeviceId)}
                disabled={isDeviceInactive}
              >
                <RefreshCcwDot className="w-4 h-4 text-red-500" />
                <span>Restart</span>
              </Button>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
