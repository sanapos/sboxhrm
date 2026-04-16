import { format } from 'date-fns';
import { Card } from '@/components/ui/card';

interface ShiftDetailsCardProps {
  shift: { 
    startTime: string; 
    endTime: string; 
    totalHours: number 
  };
}

export const ShiftDetailsCard = ({ shift }: ShiftDetailsCardProps) => (
  <Card className="p-4 bg-accent/50 border-2">
    <div className="grid grid-cols-3 gap-4 text-sm">
      <div>
        <p className="text-muted-foreground mb-1">Shift Start</p>
        <p className="font-semibold">{format(new Date(shift.startTime), 'MMM dd, h:mm a')}</p>
      </div>
      <div>
        <p className="text-muted-foreground mb-1">Shift End</p>
        <p className="font-semibold">{format(new Date(shift.endTime), 'MMM dd, h:mm a')}</p>
      </div>
      <div>
        <p className="text-muted-foreground mb-1">Duration</p>
        <p className="font-semibold">{shift.totalHours} hours</p>
      </div>
    </div>
  </Card>
);
