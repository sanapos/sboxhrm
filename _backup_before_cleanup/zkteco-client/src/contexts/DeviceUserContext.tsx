// ==========================================
// src/contexts/DeviceUserContext.tsx
// ==========================================
import { createContext, useContext, useState, useEffect, ReactNode } from 'react'
import { toast } from 'sonner'
import {
  useDeviceUsers,
  useDeleteDeviceUser,
  useUpdateDeviceUser,
  useMapDeviceUserToEmployee,
} from '@/hooks/useDeviceUsers'
import { useDevices } from '@/hooks/useDevices'
import { DeviceUser, UpdateDeviceUserRequest } from '@/types/deviceUser'
import { Device } from '@/types'
import { Employee } from '@/types/employee'

interface DeviceUserContextValue {
  // State
  deviceUsers: DeviceUser[] | undefined
  isLoading: boolean
  devices: Device[] | undefined
  selectedDeviceIds: string[]
  linkedEmployee: Employee | null
  
  // Dialog states
  createDialogOpen: boolean
  deleteDialogOpen: boolean
  mapToEmployeeDialogOpen: boolean
  employeeToEdit: DeviceUser | null
  employeeToDelete: DeviceUser | null
  employeeToMap: DeviceUser | null
  
  // Actions
  setCreateDialogOpen: (open: boolean) => void
  setDeleteDialogOpen: (open: boolean) => void
  setMapToEmployeeDialogOpen: (open: boolean) => void
  setSelectedDeviceIds: (deviceIds: string[]) => void
  setLinkedEmployee: (employee: Employee | null) => void

  handleDelete: (employee: DeviceUser) => void
  handleConfirmDelete: () => Promise<void>
  handleUpdateDeviceUser: (data: UpdateDeviceUserRequest) => Promise<void>
  handleEdit: (user: DeviceUser) => void
  handleMapToEmployee: (user: DeviceUser) => void
  handleConfirmMapToEmployee: (deviceUserId: string, employeeId: string) => Promise<void>
  handleFilterSubmit: (deviceIds: string[]) => void
  handleOpenCreateDialog: () => void
  
  // Mutation states
  isDeletePending: boolean
}

const DeviceUserContext = createContext<DeviceUserContextValue | undefined>(undefined)

export const useDeviceUserContext = () => {
  const context = useContext(DeviceUserContext)
  if (!context) {
    throw new Error('useDeviceUserContext must be used within DeviceUserProvider')
  }
  return context
}

interface DeviceUserProviderProps {
  children: ReactNode
}

export const DeviceUserProvider = ({ children }: DeviceUserProviderProps) => {
  // Dialog states
  const [createDialogOpen, setCreateDialogOpen] = useState(false)
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [mapToEmployeeDialogOpen, setMapToEmployeeDialogOpen] = useState(false)
  const [employeeToEdit, setEmployeeToEdit] = useState<DeviceUser | null>(null)
  const [employeeToDelete, setEmployeeToDelete] = useState<DeviceUser | null>(null)
  const [employeeToMap, setEmployeeToMap] = useState<DeviceUser | null>(null)
  const [selectedDeviceIds, setSelectedDeviceIds] = useState<string[]>([])
  const [linkedEmployee, setLinkedEmployee] = useState<Employee | null>(null)
  const [_openLinkedEmployeeDialog, _setOpenLinkedEmployeeDialog] = useState(false)
  
  // Hooks
  const { data: devices } = useDevices()
  const { data: deviceUsers, isLoading } = useDeviceUsers(selectedDeviceIds)
  const deleteDeviceUser = useDeleteDeviceUser()
  const updateDeviceUser = useUpdateDeviceUser()
  const mapDeviceUserToEmployee = useMapDeviceUserToEmployee()
  
  // Initialize selected devices
  useEffect(() => {
    if (devices) {
      setSelectedDeviceIds(devices.map((device) => device.id))
    }
  }, [devices])

  // Wrapper for setCreateDialogOpen to clear user state when closing
  // Handlers
  const handleDelete = (employee: DeviceUser) => {
    setEmployeeToDelete(employee)
    setDeleteDialogOpen(true)
  }

  const handleConfirmDelete = async () => {
    if (!employeeToDelete?.id) return
    await deleteDeviceUser.mutateAsync(employeeToDelete.id)
    setDeleteDialogOpen(false)
    setEmployeeToDelete(null)
  }

  const handleUpdateDeviceUser = async (data: UpdateDeviceUserRequest) => {
    try {
      await updateDeviceUser.mutateAsync(data)
    } catch (error: any) {
      toast.error('Failed to update device user', {
        description: error.message || 'An error occurred',
      })
    }
  }

  const handleEdit = (user: DeviceUser) => {
    setEmployeeToEdit(user)
    setCreateDialogOpen(true)
  }

  const handleOpenCreateDialog = () => {
    setEmployeeToEdit(null) // Clear any previous user data
    setCreateDialogOpen(true)
  }

  const handleFilterSubmit = (deviceIds: string[]) => {
    setSelectedDeviceIds(deviceIds)
  }

  const handleMapToEmployee = (user: DeviceUser) => {
    setEmployeeToMap(user)
    setMapToEmployeeDialogOpen(true)
  }

  const handleConfirmMapToEmployee = async (deviceUserId: string, employeeId: string) => {
    try {
      await mapDeviceUserToEmployee.mutateAsync({ deviceUserId, employeeId })
      setMapToEmployeeDialogOpen(false)
      setEmployeeToMap(null)
    } catch (error: any) {
      toast.error('Failed to map device user to employee', {
        description: error.message || 'An error occurred',
      })
    }
  }

  const value: DeviceUserContextValue = {
    // State
    deviceUsers,
    isLoading,
    devices,
    selectedDeviceIds,
    linkedEmployee,
    setLinkedEmployee,
    
    // Dialog states
    createDialogOpen,
    deleteDialogOpen,
    mapToEmployeeDialogOpen,
    employeeToEdit,
    employeeToDelete,
    employeeToMap,
    
    // Actions
    setCreateDialogOpen,
    setDeleteDialogOpen,
    setMapToEmployeeDialogOpen,
    setSelectedDeviceIds,
    handleDelete,
    handleConfirmDelete,
    handleUpdateDeviceUser,
    handleEdit,
    handleOpenCreateDialog,
    handleFilterSubmit,
    handleMapToEmployee,
    handleConfirmMapToEmployee,
    
    // Mutation states
    isDeletePending: deleteDeviceUser.isPending,
  }

  return (
    <DeviceUserContext.Provider value={value}>
      {children}
    </DeviceUserContext.Provider>
  )
}
