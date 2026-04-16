// ==========================================
// src/pages/Attendance.tsx
// ==========================================
import { useEffect, useState } from 'react'
import { PageHeader } from '@/components/PageHeader'
import { AttendanceFilterBar, AttendancesTable } from '@/components/attendances'
import { useAttendancesByDevices } from '@/hooks/useAttendance'
import { useDevices } from '@/hooks/useDevices'
import { AttendancesFilterParams } from '@/types/attendance'
import { defaultAttendanceFilter, defaultAttendancePaginationRequest } from '@/constants/defaultValue'

export const Attendance = () => {

  const [filter, setFilter] = useState<AttendancesFilterParams>(defaultAttendanceFilter)
  const { data: userDevices } = useDevices()
  const [appliedFilters, setAppliedFilters] = useState<AttendancesFilterParams>(filter)

  const { data, isFetching: isFetchingData, refetch } = useAttendancesByDevices(
    defaultAttendancePaginationRequest,
    appliedFilters
  )

  const deviceOptions = userDevices?.map(device => ({
    value: device.id,
    label: device.deviceName
  })) || []

  const handleApplyFilters = () => {
    setAppliedFilters({...filter})
    // Trigger server refetch with new filters
    refetch()
  }

  const onDateChange = (date: Date | undefined, type: 'fromDate' | 'toDate') => {
    setFilter(prev => ({
      ...prev,
      [type]: date
    }))
  }
  
  const handleClearFilters = () => {
    setFilter({ ...defaultAttendanceFilter, deviceIds: userDevices?.map(device => device.id) })
  }

  const onSelectChange = (values: string[]) => {
    setFilter(prev => ({
      ...prev,
      deviceIds: values
    }))
  }

  useEffect(() => {
    const newFilter = { ...defaultAttendanceFilter, deviceIds: userDevices?.map(device => device.id) }  
    setFilter(newFilter)
    setAppliedFilters(newFilter)
  }, [userDevices])

  return (
    <div className="space-y-4">
      <PageHeader
        title="Attendance Logs"
        description="View and manage attendance records"
      />

      {/* Filter Bar */}
      <AttendanceFilterBar
        deviceOptions={deviceOptions}
        onApplyFilters={handleApplyFilters}
        onClearFilters={handleClearFilters}
        filter={filter}
        onDateChange={onDateChange}
        onSelectChange={onSelectChange}
      />

      {/* Attendance Table */}
      <AttendancesTable logs={data?.items} isLoading={isFetchingData}/>
    </div>
  )
}