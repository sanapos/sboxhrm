import { useState, useEffect } from 'react';
import { Calendar } from '@/components/ui/calendar';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { 
    MultiSelect,
    MultiSelectTrigger,
    MultiSelectValue,
    MultiSelectContent,
    MultiSelectItem
} from '@/components/ui/multi-select';
import { CalendarIcon, FilterX, Search } from 'lucide-react';
import { format, startOfMonth } from 'date-fns';
import { cn } from '@/lib/utils';
import { DateRange } from 'react-day-picker';
import { useShiftManagementContext } from '@/contexts/ShiftManagementContext';

export interface ShiftFilters {
    dateRange?: DateRange;
    employeeIds: string[];
}

interface ShiftFilterBarProps {
    employees: Array<{ id: string; firstName: string; lastName: string; email: string }>;
    isLoading?: boolean;
}

export const ShiftFilterBar = ({ 
    employees,
    isLoading = false 
}: ShiftFilterBarProps) => {
    const {
        filters,
        setFilters
    } = useShiftManagementContext()
    // Get default date range (start of month to now)
    const getDefaultDateRange = (): DateRange => ({
        from: startOfMonth(new Date()),
        to: new Date(),
    });

    // Get all employee IDs
    const getAllEmployeeIds = () => employees.map(emp => emp.id);

    const [localDateRange, setLocalDateRange] = useState<DateRange | undefined>(
        filters.dateRange || getDefaultDateRange()
    );
    const [localEmployeeIds, setLocalEmployeeIds] = useState<string[]>(
        filters.employeeIds.length > 0 ? filters.employeeIds : getAllEmployeeIds()
    );

    const employeeOptions = employees.map(emp => ({
        value: emp.id,
        label: `${emp.firstName} ${emp.lastName}`,
    }));

    // Update local state when employees list changes
    useEffect(() => {
        if (employees.length > 0 && localEmployeeIds.length === 0) {
            setLocalEmployeeIds(getAllEmployeeIds());
            setFilters(prev => ({
                ...prev,
                employeeIds: getAllEmployeeIds(),
            }) );
        }
    }, [employees]);

    const handleApplyFilters = () => {
        setFilters({
            dateRange: localDateRange,
            employeeIds: localEmployeeIds,
        });
    };

    const handleClearFilters = () => {
        setLocalDateRange(getDefaultDateRange());
        setLocalEmployeeIds(getAllEmployeeIds());
    };

    const hasActiveFilters = filters.dateRange || filters.employeeIds.length > 0;
    const hasChanges = 
        JSON.stringify(localDateRange) !== JSON.stringify(filters.dateRange) ||
        JSON.stringify(localEmployeeIds) !== JSON.stringify(filters.employeeIds);

    return (
        <div className="space-y-4">
            <div className="flex flex-col gap-4 p-4 sm:p-6 border rounded-lg bg-card/50 backdrop-blur-sm">
                <div className="flex flex-col lg:flex-row items-start gap-4">
                    <div className="flex-1 w-full space-y-2">
                        <label className="text-sm font-medium text-foreground">Date Range</label>
                        <Popover>
                            <PopoverTrigger asChild>
                                <Button
                                    id="date"
                                    variant="outline"
                                    className={cn(
                                        'w-full justify-start text-left font-normal h-10',
                                        !localDateRange && 'text-muted-foreground'
                                    )}
                                    disabled={isLoading}
                                >
                                    <CalendarIcon className="mr-2 h-4 w-4" />
                                    {localDateRange?.from ? (
                                        localDateRange.to ? (
                                            <>
                                                {format(localDateRange.from, 'MMM dd, yyyy')} - {format(localDateRange.to, 'MMM dd, yyyy')}
                                            </>
                                        ) : (
                                            format(localDateRange.from, 'MMM dd, yyyy')
                                        )
                                    ) : (
                                        <span>Pick a date range</span>
                                    )}
                                </Button>
                            </PopoverTrigger>
                            <PopoverContent className="w-auto p-0" align="start">
                                <Calendar
                                    initialFocus
                                    mode="range"
                                    defaultMonth={localDateRange?.from}
                                    selected={localDateRange}
                                    onSelect={setLocalDateRange}
                                    numberOfMonths={2}
                                />
                            </PopoverContent>
                        </Popover>
                    </div>

                    <div className="flex-1 w-full space-y-2">
                        <label className="text-sm font-medium text-foreground">Employees</label>
                        <MultiSelect
                            values={localEmployeeIds}
                            onValuesChange={setLocalEmployeeIds}
                        >
                            <MultiSelectTrigger className="w-full h-10">
                                <MultiSelectValue placeholder="Select employees" />
                            </MultiSelectTrigger>
                            <MultiSelectContent>
                                {employeeOptions.map((employee) => (
                                    <MultiSelectItem
                                        key={employee.value}
                                        value={employee.value}
                                    >
                                        {employee.label}
                                    </MultiSelectItem>
                                ))}
                            </MultiSelectContent>
                        </MultiSelect>
                    </div>
                </div>

                <div className="flex flex-col sm:flex-row items-center gap-2 w-full lg:ml-auto">
                    <Button
                        onClick={handleApplyFilters}
                        disabled={isLoading || !hasChanges}
                        className="w-full sm:w-auto h-10"
                        size="default"
                    >
                        <Search className="h-4 w-4 mr-2" />
                        Apply Filters
                    </Button>
                    
                    {hasActiveFilters && (
                        <Button
                            variant="outline"
                            onClick={handleClearFilters}
                            disabled={isLoading}
                            className="w-full sm:w-auto h-10"
                            size="default"
                        >
                            <FilterX className="h-4 w-4 mr-2" />
                            Clear
                        </Button>
                    )}
                </div>
            </div>

        </div>
    );
};
