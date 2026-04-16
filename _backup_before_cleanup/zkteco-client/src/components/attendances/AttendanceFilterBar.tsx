import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { DatePicker } from '@/components/date-picker'
import { 
  MultiSelect,
  MultiSelectContent,
  MultiSelectGroup,
  MultiSelectItem,
  MultiSelectTrigger,
  MultiSelectValue,
} from '@/components/ui/multi-select'
import { Filter } from 'lucide-react'
import { AttendancesFilterParams } from '@/types/attendance'
import { Label } from '../ui/label'

export interface Option {
  value: string
  label: string
}

interface AttendanceFilterBarProps {
  deviceOptions: Option[]
  onApplyFilters: () => void
  onClearFilters: () => void
  filter: AttendancesFilterParams
  onDateChange: (date: Date | undefined, type: 'fromDate' | 'toDate') => void
  onSelectChange: (values: string[]) => void
}

export const AttendanceFilterBar = ({
  deviceOptions,
  onApplyFilters,
  onClearFilters,
  filter,
  onDateChange,
  onSelectChange
}: AttendanceFilterBarProps) => {
  return (
    <Card className="shadow-sm">
      <CardContent className="p-6">
        <div className="space-y-6">
          {/* Header */}
          <div className="flex items-center gap-2 pb-2 border-b">
            <Filter className="w-5 h-5 text-primary" />
            <h3 className="text-base font-semibold">Filter Attendance</h3>
          </div>

          {/* Filter Inputs */}
          <div className="flex flex-col md:flex-row gap-4">
            <div className="flex-1">
              <div className="flex flex-col gap-3">
                <Label className="text-sm font-medium px-1">Devices</Label>
                <MultiSelect
                  values={filter.deviceIds}
                  onValuesChange={values => onSelectChange(values)}
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
            </div>

            <div className="flex-1">
              <div className="flex flex-col gap-3">
                <Label className="text-sm font-medium px-1">From Date</Label>
                <DatePicker
                  value={new Date(filter.fromDate)}
                  onSelectDate={date => onDateChange(date, 'fromDate')}
                  placeholder="Select start date"
                />
              </div>
            </div>

            <div className="flex-1">
              <div className="flex flex-col gap-3">
                <Label className="text-sm font-medium px-1">To Date</Label>
                <DatePicker
                  value={new Date(filter.toDate)}
                  onSelectDate={date => onDateChange(date, 'toDate')}
                  placeholder="Select end date"
                />
              </div>
            </div>
          </div>

          {/* Action Buttons */}
          <div className="flex items-center gap-3 pt-2">
            <Button
              onClick={onApplyFilters}
              className="px-6"
            >
              Apply Filters
            </Button>
            <Button
              variant="outline"
              onClick={onClearFilters}
              className="px-6"
            >
              Clear Filters
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
