"use client"

import * as React from "react"
import { format } from "date-fns"
import { CalendarIcon } from "lucide-react"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Calendar } from "@/components/ui/calendar"
import { Label } from "@/components/ui/label"
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover"

interface DatePickerProps {
  label?: string | React.ReactNode;
  value?: Date | undefined;
  onSelectDate?: (date: Date | undefined) => void;
  placeholder?: string;
  disabled?: boolean;
}

export function DatePicker({ 
  label, 
  value, 
  onSelectDate, 
  placeholder = "Pick a date",
  disabled = false 
}: DatePickerProps) {
  const [date, setDate] = React.useState<Date | undefined>(value)

  // Sync internal state with external value
  React.useEffect(() => {
    setDate(value)
  }, [value])

  return (
    <div className="flex flex-col gap-2">
      {label && (
        <Label className="px-1">
          {label}
        </Label>
      )}
      <Popover>
        <PopoverTrigger asChild>
          <Button
            variant={"outline"}
            disabled={disabled}
            className={cn(
              "w-[280px] justify-start text-left font-normal",
              !date && "text-muted-foreground"
            )}
          >
            <CalendarIcon className="mr-2 h-4 w-4" />
            {date ? format(date, "PPP") : <span>{placeholder}</span>}
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-[250px] p-0" align="start">
          <Calendar
            mode="single"
            className="w-auto"
            selected={date}
            onSelect={(selectedDate) => {
              setDate(selectedDate)
              onSelectDate?.(selectedDate)
            }}
            initialFocus
          />
        </PopoverContent>
      </Popover>
    </div>
  )
}
