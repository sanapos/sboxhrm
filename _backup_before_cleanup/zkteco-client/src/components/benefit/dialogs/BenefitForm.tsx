import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { HourlyProfileFields } from "./HourlyProfileFields";
import { MonthlyProfileFields } from "./MonthlyProfileFields";
import { BenefitFormData, SalaryRateType } from "@/types/benefit";

interface SalaryProfileFormProps {
  formData: BenefitFormData;
  onChange: (data: BenefitFormData) => void;
  showActiveToggle?: boolean;
}

export const SalaryProfileForm = ({
  formData,
  onChange,
  showActiveToggle = false,
}: SalaryProfileFormProps) => {
  const isMonthlyProfile = formData.rateType === SalaryRateType.Monthly;
  const isHourlyProfile = formData.rateType === SalaryRateType.Hourly;

  return (
    <div className="grid gap-4 py-4">
      <div className="grid gap-2">
        <Label htmlFor="name">Profile Name *</Label>
        <Input
          id="name"
          value={formData.name}
          onChange={(e) => onChange({ ...formData, name: e.target.value })}
          placeholder="e.g., Senior Developer Rate"
        />
      </div>

      <div className="grid gap-2">
        <Label htmlFor="description">Description</Label>
        <Textarea
          id="description"
          value={formData.description || ''}
          onChange={(e) => onChange({ ...formData, description: e.target.value })}
          placeholder="Optional description"
        />
      </div>

      <div className="grid gap-2">
        <Label htmlFor="rateType">Profile Type *</Label>
        <Select
          value={formData.rateType.toString()}
          disabled={showActiveToggle}
          onValueChange={(value) => {
            const newRateType = parseInt(value) as SalaryRateType;
            // Reset multipliers when switching types
            onChange({
              ...formData,
              rateType: newRateType,
              overtimeMultiplier: newRateType === SalaryRateType.Hourly ? 1.5 : undefined,
              holidayMultiplier: newRateType === SalaryRateType.Hourly ? 2.0 : undefined,
              nightShiftMultiplier: newRateType === SalaryRateType.Hourly ? 1.3 : undefined,
            });
          }}
        >
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={SalaryRateType.Hourly.toString()}>Hourly</SelectItem>
            <SelectItem value={SalaryRateType.Monthly.toString()}>Monthly</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {/* Monthly Profile Fields */}
      {isMonthlyProfile && (
        <MonthlyProfileFields
          formData={formData}
          onChange={onChange}
        />
      )}

      {/* Hourly Profile Fields */}
      {isHourlyProfile && (
        <HourlyProfileFields
          formData={formData}
          onChange={onChange}
        />
      )}

    </div>
  );
};
