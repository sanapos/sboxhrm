import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Badge } from '@/components/ui/badge'
import { LoadingSpinner } from '@/components/LoadingSpinner'
import { useDeviceInfo } from '@/hooks/useDevices'
import { Info, Server, Users, Fingerprint, Calendar, Wifi, Cpu, Eye } from 'lucide-react'
import { useDeviceContext } from '@/contexts/DeviceContext'

export const DeviceInfoDialog = () => {

  const {
    infoDialogOpen,
    setInfoDialogOpen,
    selectedDeviceId,
    selectedDeviceName
  } = useDeviceContext()
  const { data: deviceInfo, isLoading, isError } = useDeviceInfo(selectedDeviceId)
  
  const parseDevSupportData = (data?: string) => {
    if (!data || data.length < 3) return { fingerprint: false, face: false, userPicture: false }
    
    return {
      fingerprint: data[0] === '1',
      face: data[1] === '1',
      userPicture: data[2] === '1',
    }
  }

  const supportData = parseDevSupportData(deviceInfo?.devSupportData)

  return (
    <Dialog open={infoDialogOpen} onOpenChange={setInfoDialogOpen}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Info className="w-5 h-5" />
            Device Information
          </DialogTitle>
          <DialogDescription>
            {selectedDeviceName ? `Details for ${selectedDeviceName}` : 'Detailed information about the device'}
          </DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <LoadingSpinner />
          </div>
        ) : isError ? (
          <div className="text-center py-8 text-muted-foreground">
            <p>Failed to load device information</p>
            <p className="text-sm mt-2">Please try again later</p>
          </div>
        ) : deviceInfo ? (
          <div className="space-y-6">
            {/* System Information */}
            <div className="space-y-3">
              <h3 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">
                System Information
              </h3>
              <div className="grid grid-cols-2 gap-4">
                <InfoItem
                  icon={<Server className="w-4 h-4" />}
                  label="Firmware Version"
                  value={deviceInfo.firmwareVersion || 'N/A'}
                />
                <InfoItem
                  icon={<Wifi className="w-4 h-4" />}
                  label="Device IP"
                  value={deviceInfo.deviceIp || 'N/A'}
                />
                <InfoItem
                  icon={<Fingerprint className="w-4 h-4" />}
                  label="Fingerprint Version"
                  value={deviceInfo.fingerprintVersion || 'N/A'}
                />
                <InfoItem
                  icon={<Eye className="w-4 h-4" />}
                  label="Face Version"
                  value={deviceInfo.faceVersion || 'N/A'}
                />
              </div>
            </div>

            {/* Enrollment Statistics */}
            <div className="space-y-3">
              <h3 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">
                Enrollment Statistics
              </h3>
              <div className="grid grid-cols-2 gap-4">
                <StatCard
                  icon={<Users className="w-5 h-5 text-blue-500" />}
                  label="Enrolled Users"
                  value={deviceInfo.enrolledUserCount}
                  color="blue"
                />
                <StatCard
                  icon={<Fingerprint className="w-5 h-5 text-purple-500" />}
                  label="Fingerprints"
                  value={deviceInfo.fingerprintCount}
                  color="purple"
                />
                <StatCard
                  icon={<Calendar className="w-5 h-5 text-green-500" />}
                  label="Attendance Records"
                  value={deviceInfo.attendanceCount}
                  color="green"
                />
                <StatCard
                  icon={<Eye className="w-5 h-5 text-orange-500" />}
                  label="Face Templates"
                  value={deviceInfo.faceTemplateCount || '0'}
                  color="orange"
                />
              </div>
            </div>

            {/* Device Capabilities */}
            <div className="space-y-3">
              <h3 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">
                Device Capabilities
              </h3>
              <div className="flex flex-wrap gap-2">
                <Badge variant={supportData.fingerprint ? 'default' : 'secondary'}>
                  <Fingerprint className="w-3 h-3 mr-1" />
                  Fingerprint {supportData.fingerprint ? 'Supported' : 'Not Supported'}
                </Badge>
                <Badge variant={supportData.face ? 'default' : 'secondary'}>
                  <Eye className="w-3 h-3 mr-1" />
                  Face Recognition {supportData.face ? 'Supported' : 'Not Supported'}
                </Badge>
                <Badge variant={supportData.userPicture ? 'default' : 'secondary'}>
                  <Users className="w-3 h-3 mr-1" />
                  User Picture {supportData.userPicture ? 'Supported' : 'Not Supported'}
                </Badge>
              </div>
              {deviceInfo.devSupportData && (
                <div className="mt-2 text-xs text-muted-foreground">
                  <Cpu className="w-3 h-3 inline mr-1" />
                  Support Data: {deviceInfo.devSupportData}
                </div>
              )}
            </div>
          </div>
        ) : (
          <div className="text-center py-8 text-muted-foreground">
            No device information available
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}

interface InfoItemProps {
  icon: React.ReactNode
  label: string
  value: string
}

const InfoItem = ({ icon, label, value }: InfoItemProps) => (
  <div className="flex items-start gap-3 p-3 rounded-lg border bg-card">
    <div className="mt-0.5 text-muted-foreground">{icon}</div>
    <div className="flex-1 min-w-0">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="text-sm font-medium truncate">{value}</p>
    </div>
  </div>
)

interface StatCardProps {
  icon: React.ReactNode
  label: string
  value: number | string
  color: 'blue' | 'purple' | 'green' | 'orange'
}

const StatCard = ({ icon, label, value, color }: StatCardProps) => {
  const bgColors = {
    blue: 'bg-blue-50 dark:bg-blue-950',
    purple: 'bg-purple-50 dark:bg-purple-950',
    green: 'bg-green-50 dark:bg-green-950',
    orange: 'bg-orange-50 dark:bg-orange-950',
  }

  return (
    <div className={`flex items-start gap-3 p-4 rounded-lg border ${bgColors[color]}`}>
      <div className="mt-1">{icon}</div>
      <div className="flex-1">
        <p className="text-xs text-muted-foreground">{label}</p>
        <p className="text-2xl font-bold mt-1">{value.toLocaleString()}</p>
      </div>
    </div>
  )
}
