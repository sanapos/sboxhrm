// ==========================================
// src/contexts/MonthlyAttendanceContext.tsx
// ==========================================
import { createContext, useContext, useState, useEffect, ReactNode } from 'react'
import { useMonthlyAttendanceSummary } from '@/hooks/useAttendance'
import { useDeviceUsers } from '@/hooks/useDeviceUsers'
import { useDevices } from '@/hooks/useDevices'
import { MonthlyAttendanceSummary } from '@/types/attendance'
import { DeviceUser } from '@/types/deviceUser'
import { Device } from '@/types'

interface SelectOption {
  value: string
  label: string
}

interface MonthlyAttendanceContextType {
  // Data
  data: MonthlyAttendanceSummary | undefined
  employees: DeviceUser[]
  devices: Device[]
  employeeOptions: SelectOption[]
  deviceOptions: SelectOption[]
  
  // Loading states
  isLoading: boolean
  employeesLoading: boolean
  devicesLoading: boolean
  
  // Error state
  error: unknown
  
  // Selected values
  selectedYear: number
  selectedMonth: number
  selectedEmployeeIds: string[]
  selectedDeviceIds: string[]
  
  // Setters
  setSelectedYear: (year: number) => void
  setSelectedMonth: (month: number) => void
  setSelectedEmployeeIds: (ids: string[]) => void
  setSelectedDeviceIds: (ids: string[]) => void
  
  // Helper functions
  handlePreviousMonth: () => void
  handleNextMonth: () => void
}

const MonthlyAttendanceContext = createContext<MonthlyAttendanceContextType | undefined>(undefined)

interface MonthlyAttendanceProviderProps {
  children: ReactNode
}

export const MonthlyAttendanceProvider = ({ children }: MonthlyAttendanceProviderProps) => {
  const currentDate = new Date()
  
  const [selectedYear, setSelectedYear] = useState(currentDate.getFullYear())
  const [selectedMonth, setSelectedMonth] = useState(currentDate.getMonth() + 1)
  const [selectedEmployeeIds, setSelectedEmployeeIds] = useState<string[]>([])
  const [selectedDeviceIds, setSelectedDeviceIds] = useState<string[]>([])

  // Fetch devices list
  const { data: devices = [], isLoading: devicesLoading } = useDevices()

  // Fetch employees by selected devices
  const { data: employees = [], isLoading: employeesLoading } = useDeviceUsers(selectedDeviceIds)

  // Fetch monthly attendance summary
  const { data, isLoading, error } = useMonthlyAttendanceSummary(
    selectedEmployeeIds,
    selectedYear,
    selectedMonth,
    !!selectedEmployeeIds
  )

  // Initialize with all devices selected
  useEffect(() => {
    if (devices.length > 0 && selectedDeviceIds.length === 0) {
      setSelectedDeviceIds(devices.map(d => d.id))
    }
  }, [devices, selectedDeviceIds.length])

  // Set default employee to current user if not a manager
  useEffect(() => {
    if( employees.length > 0 && selectedEmployeeIds.length === 0) { 
        setSelectedEmployeeIds(employees.map(e => e.id))
    }
  }, [employees, selectedEmployeeIds.length])

  // Prepare employee options
  const employeeOptions = employees
    .filter(emp => emp?.id)
    .map(emp => ({
      value: emp.id,
      label: `${emp.name}-(${emp.pin})`
    }))

const deviceOptions = devices
    .filter(dev => dev?.id)
    .map(dev => ({
      value: dev.id,
      label: dev.deviceName
    }))

  const handlePreviousMonth = () => {
    if (selectedMonth === 1) {
      setSelectedMonth(12)
      setSelectedYear(selectedYear - 1)
    } else {
      setSelectedMonth(selectedMonth - 1)
    }
  }

  const handleNextMonth = () => {
    if (selectedMonth === 12) {
      setSelectedMonth(1)
      setSelectedYear(selectedYear + 1)
    } else {
      setSelectedMonth(selectedMonth + 1)
    }
  }

  const value: MonthlyAttendanceContextType = {
    data,
    employees,
    devices,
    employeeOptions,
    deviceOptions,
    isLoading,
    employeesLoading,
    devicesLoading,
    error,
    selectedYear,
    selectedMonth,
    selectedEmployeeIds,
    selectedDeviceIds,
    setSelectedYear,
    setSelectedMonth,
    setSelectedEmployeeIds,
    setSelectedDeviceIds,
    handlePreviousMonth,
    handleNextMonth,
  }

  return (
    <MonthlyAttendanceContext.Provider value={value}>
      {children}
    </MonthlyAttendanceContext.Provider>
  )
}

export const useMonthlyAttendanceContext = () => {
  const context = useContext(MonthlyAttendanceContext)
  if (context === undefined) {
    throw new Error('useMonthlyAttendanceContext must be used within a MonthlyAttendanceProvider')
  }
  return context
}
