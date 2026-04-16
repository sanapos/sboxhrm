import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { MoneyInput } from "@/components/MoneyInput";
import { BenefitFormData } from "@/types/benefit";

interface HourlyProfileFieldsProps {
  formData: BenefitFormData;
  onChange: (data: BenefitFormData) => void;
}

export const HourlyProfileFields = ({
  formData,
  onChange,
}: HourlyProfileFieldsProps) => {
  return (
    <>
      <div className="grid gap-2">
        <Label htmlFor="rate">Hourly Rate *</Label>
        <MoneyInput
          id="rate"
          value={formData.rate}
          onChange={(rate) => onChange({ ...formData, rate })}
          placeholder="0"
        />
        <p className="text-xs text-muted-foreground">
          The base hourly rate for regular working hours
        </p>
      </div>

      <div className="grid gap-2">
        <Label htmlFor="currency">Currency *</Label>
        <Input
          id="currency"
          value={formData.currency}
          onChange={(e) => onChange({ ...formData, currency: e.target.value })}
          placeholder="USD"
          maxLength={10}
        />
      </div>

      <div className="grid grid-cols-3 gap-4">
        <div className="grid gap-2">
          <Label htmlFor="overtime">Overtime Multiplier</Label>
          <Input
            id="overtime"
            type="number"
            value={formData.overtimeMultiplier || ''}
            onChange={(e) => onChange({ ...formData, overtimeMultiplier: e.target.value ? parseFloat(e.target.value) : undefined })}
            placeholder="1.5"
            step="0.1"
          />
          <p className="text-xs text-muted-foreground">Usually 1.5x</p>
        </div>

        <div className="grid gap-2">
          <Label htmlFor="holiday">Holiday Multiplier</Label>
          <Input
            id="holiday"
            type="number"
            value={formData.holidayMultiplier || ''}
            onChange={(e) => onChange({ ...formData, holidayMultiplier: e.target.value ? parseFloat(e.target.value) : undefined })}
            placeholder="2.0"
            step="0.1"
          />
          <p className="text-xs text-muted-foreground">Usually 2.0x</p>
        </div>

        <div className="grid gap-2">
          <Label htmlFor="nightshift">Night Shift Multiplier</Label>
          <Input
            id="nightshift"
            type="number"
            value={formData.nightShiftMultiplier || ''}
            onChange={(e) => onChange({ ...formData, nightShiftMultiplier: e.target.value ? parseFloat(e.target.value) : undefined })}
            placeholder="1.3"
            step="0.1"
          />
          <p className="text-xs text-muted-foreground">Usually 1.3x</p>
        </div>
      </div>

      <div className="p-4 bg-muted/50 rounded-lg">
        <p className="text-sm text-muted-foreground">
          <strong>Hourly Rate Profile:</strong> Employees are paid based on hours worked. 
          Multipliers apply to overtime, holiday work, and night shifts.
        </p>
      </div>
    </>
  );
};
