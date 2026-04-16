import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { MoneyInput } from "@/components/MoneyInput";
import { BenefitFormData } from "@/types/benefit";

interface MonthlyProfileFieldsProps {
  formData: BenefitFormData;
  onChange: (data: BenefitFormData) => void;
}

export const MonthlyProfileFields = ({
  formData,
  onChange,
}: MonthlyProfileFieldsProps) => {
  return (
    <>
      {/* Base Salary Configuration */}
      <div className="space-y-4">
        <h3 className="text-sm font-semibold">Base Salary Configuration</h3>
        
        <div className="grid grid-cols-2 gap-4">
          <div className="grid gap-2">
            <Label htmlFor="rate">Base Monthly Salary *</Label>
            <MoneyInput
              id="rate"
              value={formData.rate}
              onChange={(rate) => onChange({ ...formData, rate })}
              placeholder="0"
            />
            <p className="text-xs text-muted-foreground">
              The fixed monthly salary amount
            </p>
          </div>
            <div className="grid gap-2">
            <Label htmlFor="standardHoursPerDay">Standard Hours per Day *</Label>
            <Input
              id="standardHoursPerDay"
              type="number"
              value={formData.standardHoursPerDay || ''}
              onChange={(e) => onChange({ ...formData, standardHoursPerDay: e.target.value ? parseInt(e.target.value) : undefined })}
              placeholder="8"
              required
            />
            <p className="text-xs text-muted-foreground">
              Standard working hours per day
            </p>
          </div>
         
        </div>

        
      </div>

      <Separator />

      {/* Leave & Attendance Rules */}
      <div className="space-y-4">
        <h3 className="text-sm font-semibold">Leave & Attendance Rules</h3>
        
        <div className="grid gap-2">
          <Label>Weekly Off Days</Label>
          <div className="flex flex-wrap gap-4 p-3 border rounded-md">
            {['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'].map((day) => {
              const selectedDays = formData.weeklyOffDays ? formData.weeklyOffDays.split(',') : [];
              const isChecked = selectedDays.includes(day);
              
              return (
                <label key={day} className="flex items-center space-x-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={isChecked}
                    onChange={(e) => {
                      const currentDays = formData.weeklyOffDays ? formData.weeklyOffDays.split(',').filter((d: string) => d) : [];
                      let newDays: string[];
                      
                      if (e.target.checked) {
                        newDays = [...currentDays, day];
                      } else {
                        newDays = currentDays.filter((d: string) => d !== day);
                      }
                      
                      onChange({ ...formData, weeklyOffDays: newDays.length > 0 ? newDays.join(',') : undefined });
                    }}
                    className="h-4 w-4 rounded border-gray-300"
                  />
                  <span className="text-sm">{day}</span>
                </label>
              );
            })}
          </div>
          <p className="text-xs text-muted-foreground">
            Select which days of the week are off days (e.g., Saturday and Sunday)
          </p>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="grid gap-2">
            <Label htmlFor="paidLeaveDays">Paid Leave Days</Label>
            <Input
              id="paidLeaveDays"
              type="number"
              value={formData.paidLeaveDays || ''}
              onChange={(e) => onChange({ ...formData, paidLeaveDays: e.target.value ? parseInt(e.target.value) : undefined })}
              placeholder="10"
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="unpaidLeaveDays">Unpaid Leave Days</Label>
            <Input
              id="unpaidLeaveDays"
              type="number"
              value={formData.unpaidLeaveDays || ''}
              onChange={(e) => onChange({ ...formData, unpaidLeaveDays: e.target.value ? parseInt(e.target.value) : undefined })}
              placeholder="0"
            />
          </div>

        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="grid gap-2">
            <Label htmlFor="checkIn">Check-In Time</Label>
            <Input
              id="checkIn"
              type="time"
              value={formData.checkIn || ''}
              onChange={(e) => onChange({ ...formData, checkIn: `${e.target.value}:00` })}
              placeholder="08:00"
            />
            <p className="text-xs text-muted-foreground">
              Standard check-in time (e.g., 08:00)
            </p>
          </div>

          <div className="grid gap-2">
            <Label htmlFor="checkOut">Check-Out Time</Label>
            <Input
              id="checkOut"
              type="time"
              value={formData.checkOut || ''}
              onChange={(e) => onChange({ ...formData, checkOut: `${e.target.value}:00` })}
              placeholder="17:00"
            />
            <p className="text-xs text-muted-foreground">
              Standard check-out time (e.g., 17:00)
            </p>
          </div>
        </div>
      </div>

      <Separator />

      {/* Allowances */}
      <div className="space-y-4">
        <h3 className="text-sm font-semibold">Allowances</h3>
        
        <div className="grid grid-cols-3 gap-4">
          <div className="grid gap-2">
            <Label htmlFor="mealAllowance">Meal</Label>
            <MoneyInput
              id="mealAllowance"
              value={formData.mealAllowance}
              onChange={(mealAllowance) => onChange({ ...formData, mealAllowance })}
              placeholder="0"
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="transportAllowance">Transport</Label>
            <MoneyInput
              id="transportAllowance"
              value={formData.transportAllowance}
              onChange={(transportAllowance) => onChange({ ...formData, transportAllowance })}
              placeholder="0"
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="housingAllowance">Housing</Label>
            <MoneyInput
              id="housingAllowance"
              value={formData.housingAllowance}
              onChange={(housingAllowance) => onChange({ ...formData, housingAllowance })}
              placeholder="0"
            />
          </div>
        </div>

        <div className="grid grid-cols-3 gap-4">
          <div className="grid gap-2">
            <Label htmlFor="responsibilityAllowance">Responsibility</Label>
            <MoneyInput
              id="responsibilityAllowance"
              value={formData.responsibilityAllowance}
              onChange={(responsibilityAllowance) => onChange({ ...formData, responsibilityAllowance })}
              placeholder="0"
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="attendanceBonus">Attendance Bonus</Label>
            <MoneyInput
              id="attendanceBonus"
              value={formData.attendanceBonus}
              onChange={(attendanceBonus) => onChange({ ...formData, attendanceBonus })}
              placeholder="0"
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="phoneSkillShiftAllowance">Phone/Skill</Label>
            <MoneyInput
              id="phoneSkillShiftAllowance"
              value={formData.phoneSkillShiftAllowance}
              onChange={(phoneSkillShiftAllowance) => onChange({ ...formData, phoneSkillShiftAllowance })}
              placeholder="0"
            />
          </div>
        </div>
      </div>

      <Separator />

      {/* Health Insurance */}
      <div className="space-y-4">
        <div className="flex items-center space-x-2">
          <input
            type="checkbox"
            id="hasHealthInsurance"
            checked={formData.hasHealthInsurance || false}
            onChange={(e) => onChange({ ...formData, hasHealthInsurance: e.target.checked })}
            className="h-4 w-4 rounded border-gray-300"
          />
          <Label htmlFor="hasHealthInsurance" className="text-sm font-semibold cursor-pointer">
            Include Health Insurance Deduction
          </Label>
        </div>

        {formData.hasHealthInsurance && (
          <div className="pl-6 space-y-4">
            <div className="grid gap-2">
              <Label htmlFor="healthInsuranceRate">Health Insurance Rate (%)</Label>
              <Input
                id="healthInsuranceRate"
                type="number"
                value={formData.healthInsuranceRate || ''}
                onChange={(e) => onChange({ ...formData, healthInsuranceRate: e.target.value ? parseFloat(e.target.value) : undefined })}
                placeholder="0.00"
                step="0.01"
                min="0"
                max="100"
              />
              <p className="text-xs text-muted-foreground">
                Percentage of base salary to deduct for health insurance (0-100%)
              </p>
            </div>
          </div>
        )}
      </div>

      <Separator />

      {/* Overtime Configuration */}
      <div className="space-y-4">
        <h3 className="text-sm font-semibold">Overtime Configuration</h3>
        
        <div className="grid grid-cols-2 gap-4">
          <div className="grid gap-2">
            <Label htmlFor="oTRateWeekday">OT Rate - Weekday (150%)</Label>
            <Input
              id="oTRateWeekday"
              type="number"
              value={formData.otRateWeekday || ''}
              onChange={(e) => onChange({ ...formData, otRateWeekday: e.target.value ? parseFloat(e.target.value) : undefined })}
              placeholder="1.5"
              step="0.1"
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="oTRateWeekend">OT Rate - Weekend (200%)</Label>
            <Input
              id="oTRateWeekend"
              type="number"
              value={formData.otRateWeekend || ''}
              onChange={(e) => onChange({ ...formData, otRateWeekend: e.target.value ? parseFloat(e.target.value) : undefined })}
              placeholder="2.0"
              step="0.1"
            />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="grid gap-2">
            <Label htmlFor="oTRateHoliday">OT Rate - Holiday (300%)</Label>
            <Input
              id="oTRateHoliday"
              type="number"
              value={formData.otRateHoliday || ''}
              onChange={(e) => onChange({ ...formData, otRateHoliday: e.target.value ? parseFloat(e.target.value) : undefined })}
              placeholder="3.0"
              step="0.1"
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="nightShiftRate">Night Shift Rate</Label>
            <Input
              id="nightShiftRate"
              type="number"
              value={formData.nightShiftRate || ''}
              onChange={(e) => onChange({ ...formData, nightShiftRate: e.target.value ? parseFloat(e.target.value) : undefined })}
              placeholder="1.3"
              step="0.1"
            />
          </div>

        </div>
      </div>

      <div className="p-4 bg-muted/50 rounded-lg">
        <p className="text-sm text-muted-foreground">
          <strong>Monthly Salary Profile:</strong> Configure base salary, weekly off days, leave policies, 
          allowances, and overtime rates. All fields are optional except base salary and currency.
        </p>
      </div>
    </>
  );
};
