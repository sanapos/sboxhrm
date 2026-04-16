
// ==========================================
// src/components/dialogs/CreateDeviceDialog.tsx
// ==========================================
import { useState } from 'react'
import { useCreateDevice } from '@/hooks/useDevices'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Hash, Monitor, MapPin } from 'lucide-react'
import type { CreateDeviceRequest } from '@/types'
import { defaultNewDevice } from '@/constants/defaultValue'
import { useDeviceContext } from '@/contexts/DeviceContext'

export const CreateDeviceDialog = () => {
  const {
    createDialogOpen,
    setCreateDialogOpen
  } = useDeviceContext()

  const createDevice = useCreateDevice()
  const [formData, setFormData] = useState<CreateDeviceRequest>(defaultNewDevice)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    await createDevice.mutateAsync({ ...formData })
    setCreateDialogOpen(false)
    setFormData(defaultNewDevice)
  }

  return (
    <Dialog open={createDialogOpen} onOpenChange={setCreateDialogOpen}>
      <DialogContent className="sm:max-w-[550px]">
        <DialogHeader>
          <DialogTitle className="text-xl">Add New Device</DialogTitle>
          <DialogDescription>
            Register a new ZKTeco device to the system. Fields marked with * are required.
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-5 mt-2">
          {/* Serial Number */}
          <div className="space-y-2">
            <Label htmlFor="serialNumber" className="text-sm font-medium flex items-center gap-2">
              <Hash className="w-4 h-4 text-muted-foreground" />
              Serial Number <span className="text-destructive">*</span>
            </Label>
            <Input
              id="serialNumber"
              value={formData.serialNumber}
              onChange={(e) =>
                setFormData({ ...formData, serialNumber: e.target.value })
              }
              placeholder="e.g., XXXXXXXXXX"
              required
              className="transition-all"
            />
          </div>

          {/* Device Name */}
          <div className="space-y-2">
            <Label htmlFor="deviceName" className="text-sm font-medium flex items-center gap-2">
              <Monitor className="w-4 h-4 text-muted-foreground" />
              Device Name <span className="text-destructive">*</span>
            </Label>
            <Input
              id="deviceName"
              value={formData.deviceName}
              onChange={(e) =>
                setFormData({ ...formData, deviceName: e.target.value })
              }
              placeholder="e.g., Main Entrance Device"
              required
              className="transition-all"
            />
          </div>

          {/* Location */}
          <div className="space-y-2">
            <Label htmlFor="location" className="text-sm font-medium flex items-center gap-2">
              <MapPin className="w-4 h-4 text-muted-foreground" />
              Location
            </Label>
            <Input
              id="location"
              value={formData.location}
              onChange={(e) =>
                setFormData({ ...formData, location: e.target.value })
              }
              placeholder="e.g., Building A - Main Door"
            />
          </div>

          {/* Description */}
          <div className="space-y-2">
            <Label htmlFor="description" className="text-sm font-medium">
              Description
            </Label>
            <Input
              id="description"
              value={formData.description || ''}
              onChange={(e) =>
                setFormData({ ...formData, description: e.target.value })
              }
              placeholder="e.g., Primary access control device for main entrance"
            />
          </div>

          {/* Action Buttons */}
          <div className="flex justify-end gap-3 pt-4 border-t">
            <Button
              type="button"
              variant="outline"
              onClick={() => {
                setCreateDialogOpen(false)
                setFormData(defaultNewDevice)
              }}
              disabled={createDevice.isPending}
            >
              Cancel
            </Button>
            <Button 
              type="submit" 
              disabled={createDevice.isPending}
              className="min-w-[120px]"
            >
              {createDevice.isPending ? (
                <>
                  <span className="mr-2">Creating...</span>
                  <span className="animate-spin">⏳</span>
                </>
              ) : (
                'Create Device'
              )}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}