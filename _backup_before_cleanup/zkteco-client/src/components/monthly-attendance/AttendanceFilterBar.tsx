// ==========================================
// src/components/monthly-attendance/AttendanceFilterBar.tsx
// ==========================================
import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Label } from '@/components/ui/label'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { useMonthlyAttendanceContext } from '@/contexts/MonthlyAttendanceContext'
import { MultiSelect, MultiSelectContent, MultiSelectGroup, MultiSelectItem, MultiSelectTrigger, MultiSelectValue } from '../ui/multi-select'

const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
]

export const AttendanceFilterBar = () => {
  const {
    employeeOptions,
    selectedYear,
    selectedMonth,
    selectedEmployeeIds,
    selectedDeviceIds,
    deviceOptions,
    setSelectedYear,
    setSelectedMonth,
    setSelectedEmployeeIds,
    setSelectedDeviceIds,
    handlePreviousMonth,
    handleNextMonth,
  } = useMonthlyAttendanceContext()
  console.log('employeeDevices', selectedDeviceIds);
  console.log('selectedEmployees', selectedEmployeeIds);

  const years = useMemo(() => {
    const currentYear = new Date().getFullYear()
    return Array.from({ length: 3 }, (_, i) => currentYear - i)
  }, [])

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-lg">Filters</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          {/* Device Filter - Multi Select */}
          <div className="space-y-2">
            <Label htmlFor="devices">Devices</Label>
            <MultiSelect
                values={selectedDeviceIds}
                onValuesChange={values => setSelectedDeviceIds(values)}
                
            >
                <MultiSelectTrigger className="w-full max-w-[400px]">
                <MultiSelectValue placeholder="Select devices..." />
                </MultiSelectTrigger>
                <MultiSelectContent>
                <MultiSelectGroup>
                    {deviceOptions.map((option) => (
                    <MultiSelectItem key={option.value} value={option.value}>
                        {option.label}
                    </MultiSelectItem>
                    ))}
                </MultiSelectGroup>
                </MultiSelectContent>
            </MultiSelect>
          </div>

          {/* Employee Filter */}
          <div className="space-y-2">
            <Label htmlFor="employee">Employees</Label>
            <MultiSelect
                values={selectedEmployeeIds}
                onValuesChange={values => setSelectedEmployeeIds(values)}
            >
                <MultiSelectTrigger className="w-full max-w-[400px]">
                <MultiSelectValue placeholder="Select devices..." />
                </MultiSelectTrigger>
                <MultiSelectContent>
                <MultiSelectGroup>
                    {employeeOptions.map((option) => (
                    <MultiSelectItem key={option.value} value={option.value}>
                        {option.label}
                    </MultiSelectItem>
                    ))}
                </MultiSelectGroup>
                </MultiSelectContent>
            </MultiSelect>
          </div>

          {/* Month Filter */}
          <div className="space-y-2">
            <Label htmlFor="month">Month</Label>
            <Select
              value={selectedMonth.toString()}
              onValueChange={(value) => setSelectedMonth(parseInt(value))}
            >
              <SelectTrigger id="month">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {MONTHS.map((month, index) => (
                  <SelectItem key={month} value={(index + 1).toString()}>
                    {month}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Year Filter */}
          <div className="space-y-2">
            <Label htmlFor="year">Year</Label>
            <Select
              value={selectedYear.toString()}
              onValueChange={(value) => setSelectedYear(parseInt(value))}
            >
              <SelectTrigger id="year">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {years.map((year) => (
                  <SelectItem key={year} value={year.toString()}>
                    {year}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>

        {/* Month Navigation */}
        <div className="flex items-center justify-center gap-4 mt-4">
          <Button
            variant="outline"
            size="sm"
            onClick={handlePreviousMonth}
          >
            <ChevronLeft className="h-4 w-4 mr-1" />
            Previous Month
          </Button>
          
          <div className="text-sm font-medium">
            {MONTHS[selectedMonth - 1]} {selectedYear}
          </div>

          <Button
            variant="outline"
            size="sm"
            onClick={handleNextMonth}
          >
            Next Month
            <ChevronRight className="h-4 w-4 ml-1" />
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}
