import { Card } from '@/components/ui/card';

interface DurationDisplayProps {
  duration: number;
  isHalfShift: boolean;
  totalHours?: number;
}

export const DurationDisplay = ({ duration, isHalfShift, totalHours }: DurationDisplayProps) => (
  <Card className="p-4 bg-primary/5 border-primary/30">
    <div className="flex items-center justify-between">
      <div>
        <p className="text-sm text-muted-foreground mb-1">Leave Duration</p>
        <p className="text-2xl font-bold text-primary">
          {duration} hour{duration !== 1 ? 's' : ''}
        </p>
      </div>
      {!isHalfShift && totalHours && (
        <div className="text-right">
          <p className="text-sm text-muted-foreground mb-1">Percentage</p>
          <p className="text-2xl font-bold">
            {((duration / totalHours) * 100).toFixed(0)}%
          </p>
        </div>
      )}
    </div>
  </Card>
);
