import * as React from "react";
import { format } from "date-fns";
import { Calendar as CalendarIcon, Clock } from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Calendar } from "@/components/ui/calendar";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Input } from "@/components/ui/input";

interface DateTimePickerProps {
  date?: Date;
  setDate: (date: Date) => void;
  minDate?: Date;
  maxDate?: Date;
  disabled?: boolean;
  timeOnly?: boolean; // Only show time picker, not date
}

export function DateTimePicker({
  date,
  setDate,
  minDate,
  maxDate,
  disabled = false,
  timeOnly = false,
}: DateTimePickerProps) {
  const [selectedDateTime, setSelectedDateTime] = React.useState<Date | undefined>(date);

  const handleDateSelect = (selectedDate: Date | undefined) => {
    if (selectedDate) {
      // Preserve the time when selecting a new date
      const newDateTime = new Date(selectedDate);
      if (selectedDateTime) {
        newDateTime.setHours(selectedDateTime.getHours());
        newDateTime.setMinutes(selectedDateTime.getMinutes());
        newDateTime.setSeconds(selectedDateTime.getSeconds());
      } else {
        newDateTime.setHours(0);
        newDateTime.setMinutes(0);
        newDateTime.setSeconds(0);
      }
      setSelectedDateTime(newDateTime);
      setDate(newDateTime);
    }
  };

  const handleTimeChange = (value: string) => {
    const [hours, minutes] = value.split(':').map(v => parseInt(v) || 0);
    const newDateTime = selectedDateTime ? new Date(selectedDateTime) : new Date();
    newDateTime.setHours(hours);
    newDateTime.setMinutes(minutes);
    newDateTime.setSeconds(0);
    setSelectedDateTime(newDateTime);
    setDate(newDateTime);
  };

  React.useEffect(() => {
    setSelectedDateTime(date);
  }, [date]);

  const formatTime = (date: Date | undefined) => {
    if (!date) return "00:00";
    return format(date, "HH:mm");
  };

  return (
    <div className="flex flex-col sm:flex-row items-start gap-2 sm:gap-3">
      {!timeOnly && (
        <div className="flex-1 w-full">
          <Popover>
            <PopoverTrigger asChild>
              <Button
                variant={"outline"}
                className={cn(
                  "w-full justify-start text-left font-normal h-11",
                  !selectedDateTime && "text-muted-foreground"
                )}
                disabled={disabled}
              >
                <CalendarIcon className="mr-2 h-4 w-4" />
                {selectedDateTime ? (
                  format(selectedDateTime, "MMMM do, yyyy")
                ) : (
                  <span>Select date</span>
                )}
              </Button>
            </PopoverTrigger>
            <PopoverContent className="w-auto p-0" align="start">
              <Calendar
                mode="single"
                selected={selectedDateTime}
                style={{ minWidth: '250px' }}
                onSelect={handleDateSelect}
                disabled={(date) => {
                  if (minDate && date < minDate) return true;
                  if (maxDate && date > maxDate) return true;
                  return false;
                }}
                initialFocus
              />
            </PopoverContent>
          </Popover>
        </div>
      )}

      <div className={cn("flex-1 w-full", timeOnly && "max-w-full")}>
        <div className="relative cursor-pointer" onClick={(e) => {
          const input = e.currentTarget.querySelector('input');
          if (input && !disabled) {
            input.showPicker?.();
          }
        }}>
          <Clock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
          <Input
            type="time"
            value={formatTime(selectedDateTime)}
            onChange={(e) => handleTimeChange(e.target.value)}
            className="w-full pl-10 h-11 cursor-pointer"
            disabled={disabled}
          />
        </div>
      </div>
    </div>
  );
}
