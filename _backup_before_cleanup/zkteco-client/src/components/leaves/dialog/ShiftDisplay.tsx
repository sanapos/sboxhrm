import { format } from 'date-fns';
import { Shift } from '@/types/shift';

interface ShiftDisplayProps {
  shift: Shift | { 
    id: string; 
    startTime: string; 
    endTime: string; 
    totalHours: number; 
    description?: string; 
    employeeName: string 
  };
}

export const ShiftDisplay = ({ shift }: ShiftDisplayProps) => (
  <div className="flex flex-col gap-1">
    <span className="font-medium">
      {format(new Date(shift.startTime), 'MMM dd, yyyy, h:mm a')} - {format(new Date(shift.endTime), 'h:mm a')}
    </span>
    <span className="text-xs text-muted-foreground">
      {shift.totalHours}h{shift.description && ` • ${shift.description}`}
    </span>
  </div>
);
