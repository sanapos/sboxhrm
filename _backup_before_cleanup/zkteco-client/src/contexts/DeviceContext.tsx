import { createContext, useContext, ReactNode, useState } from 'react'
import {
  useDeleteDevice,
  useToggleActive,
} from '@/hooks/useDevices'

interface DeviceContextType {
  // Delete device
  handleDelete: (id: string) => Promise<void>
  
  // Toggle active status
  handleToggleActive: (id: string) => Promise<void>

  // Loading states
  isDeleting: boolean
  isTogglingActive: boolean
  
  // Dialog states
  createDialogOpen: boolean
  setCreateDialogOpen: (open: boolean) => void
  infoDialogOpen: boolean
  setInfoDialogOpen: (open: boolean) => void
  
  // Selected device
  selectedDeviceId: string | null
  setSelectedDeviceId: (id: string | null) => void
  selectedDeviceName: string | undefined
  setSelectedDeviceName: (name: string | undefined) => void
  
  // Helper functions
  openCreateDialog: () => void
  openInfoDialog: (id: string, name?: string) => void
}

const DeviceContext = createContext<DeviceContextType | undefined>(undefined)

interface DeviceProviderProps {
  children: ReactNode
}

export const DeviceProvider = ({ children }: DeviceProviderProps) => {
  // Dialog states
  const [createDialogOpen, setCreateDialogOpen] = useState(false)
  const [infoDialogOpen, setInfoDialogOpen] = useState(false)
  const [selectedDeviceId, setSelectedDeviceId] = useState<string | null>(null)
  const [selectedDeviceName, setSelectedDeviceName] = useState<string | undefined>(undefined)

  // Mutation hooks
  const deleteDevice = useDeleteDevice()
  const activeDevice = useToggleActive()
  
  // Handler functions
  const handleDelete = async (id: string) => {
    try {
      await deleteDevice.mutateAsync(id)
    } catch (error) {
      console.error('Error deleting device:', error)
    }
  }

  const handleToggleActive = async (id: string) => {
    try {
      await activeDevice.mutateAsync(id)
    } catch (error) {
      console.error('Error toggling device active status:', error)
    }
  }

  // Helper functions for dialogs
  const openCreateDialog = () => {
    setCreateDialogOpen(true)
  }

  const openInfoDialog = (id: string, name?: string) => {
    setSelectedDeviceId(id)
    setSelectedDeviceName(name)
    setInfoDialogOpen(true)
  }

  const value: DeviceContextType = {
    handleDelete,
    handleToggleActive,

    isDeleting: deleteDevice.isPending,
    isTogglingActive: activeDevice.isPending,
    
    createDialogOpen,
    setCreateDialogOpen,
    infoDialogOpen,
    setInfoDialogOpen,
    selectedDeviceId,
    setSelectedDeviceId,
    selectedDeviceName,
    setSelectedDeviceName,
    openCreateDialog,
    openInfoDialog,
  }

  return <DeviceContext.Provider value={value}>{children}</DeviceContext.Provider>
}

export const useDeviceContext = () => {
  const context = useContext(DeviceContext)
  if (context === undefined) {
    throw new Error('useDeviceContext must be used within a DeviceProvider')
  }
  return context
}
