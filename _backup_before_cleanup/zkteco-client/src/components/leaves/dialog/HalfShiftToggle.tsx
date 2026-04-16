import { Label } from '@/components/ui/label';

interface HalfShiftToggleProps {
  isHalfShift: boolean;
  onToggle: (checked: boolean) => void;
}

export const HalfShiftToggle = ({ isHalfShift, onToggle }: HalfShiftToggleProps) => (
  <div className="space-y-3">
    <Label className="text-base font-semibold">Leave Duration</Label>
    <div className="flex items-start space-x-3 p-4 rounded-lg border-2 bg-card hover:bg-accent/50 transition-colors">
      <input
        type="checkbox"
        id="isHalfShift"
        className="h-5 w-5 rounded border-gray-300 text-primary focus:ring-2 focus:ring-primary cursor-pointer mt-0.5"
        checked={isHalfShift}
        onChange={e => onToggle(e.target.checked)}
      />
      <Label htmlFor="isHalfShift" className="cursor-pointer flex-1">
        <span className="font-medium">Is Half Shift</span>
        <span className="block text-sm text-muted-foreground font-normal mt-1">
          Check to request leave for half of your shift
        </span>
      </Label>
    </div>
  </div>
);
