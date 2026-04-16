import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { EmployeeBenefit, SalaryRateType } from "@/types/benefit";
import { formatDate } from "@/lib/utils";

interface EmployeeSalaryProfileDetailDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  profile: EmployeeBenefit | null;
}

export const EmployeeSalaryProfileDetailDialog = ({
  open,
  onOpenChange,
  profile,
}: EmployeeSalaryProfileDetailDialogProps) => {
  if (!profile || !profile.benefit) return null;

  const benefit = profile.benefit;
  const isHourly = benefit.rateType === SalaryRateType.Hourly;
  const isMonthly = benefit.rateType === SalaryRateType.Monthly;
  const isActive = !profile.endDate || new Date(profile.endDate) > new Date();

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{profile.employee.fullName} - Benefit Details</DialogTitle>
          <DialogDescription>
            {benefit.name}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-6">
          {/* Basic Information */}
          <div>
            <h3 className="text-lg font-semibold mb-3">Benefit Information</h3>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground">Employee</p>
                <p className="font-medium">{profile.employee.fullName}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Benefit Profile</p>
                <p className="font-medium">{benefit.name}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Effective Date</p>
                <p className="font-medium">{formatDate(new Date(profile.effectiveDate))}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">End Date</p>
                <p className="font-medium">
                  {profile.endDate ? formatDate(new Date(profile.endDate)) : '-'}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Status</p>
                <Badge variant={isActive ? "default" : "secondary"}>
                  {isActive ? 'Active' : 'Inactive'}
                </Badge>
              </div>
              {profile.notes && (
                <div className="col-span-2">
                  <p className="text-sm text-muted-foreground">Notes</p>
                  <p className="font-medium">{profile.notes}</p>
                </div>
              )}
            </div>
          </div>

          <Separator />

          {/* Salary Configuration */}
          <div>
            <h3 className="text-lg font-semibold mb-3">Salary Configuration</h3>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground">Rate Type</p>
                <Badge variant="outline">
                  {isHourly ? 'Hourly' : isMonthly ? 'Monthly' : 'Unknown'}
                </Badge>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Base Rate</p>
                <p className="font-medium text-lg">
                  {benefit.rate.toLocaleString()} {benefit.currency}
                </p>
              </div>
              {isMonthly && benefit.standardHoursPerDay && (
                <div>
                  <p className="text-sm text-muted-foreground">Standard Hours/Day</p>
                  <p className="font-medium">{benefit.standardHoursPerDay} hours</p>
                </div>
              )}
            </div>
          </div>

          <Separator />

          {/* Multipliers - Show for both Hourly and Monthly */}
          <div>
            <h3 className="text-lg font-semibold mb-3">Rate Multipliers</h3>
            <div className="grid grid-cols-3 gap-4">
              {benefit.overtimeMultiplier && (
                <div>
                  <p className="text-sm text-muted-foreground">Overtime</p>
                  <p className="font-medium">{benefit.overtimeMultiplier}x</p>
                </div>
              )}
              {benefit.holidayMultiplier && (
                <div>
                  <p className="text-sm text-muted-foreground">Holiday</p>
                  <p className="font-medium">{benefit.holidayMultiplier}x</p>
                </div>
              )}
              {benefit.nightShiftMultiplier && (
                <div>
                  <p className="text-sm text-muted-foreground">Night Shift</p>
                  <p className="font-medium">{benefit.nightShiftMultiplier}x</p>
                </div>
              )}
            </div>
          </div>

          {/* Monthly-specific information */}
          {isMonthly && (
            <>
              <Separator />

              {/* Leave & Attendance Rules */}
              <div>
                <h3 className="text-lg font-semibold mb-3">Leave & Attendance Rules</h3>
                <div className="grid grid-cols-2 gap-4">

                  {benefit.paidLeaveDays !== null && benefit.paidLeaveDays !== undefined && (
                    <div>
                      <p className="text-sm text-muted-foreground">Paid Leave Days (Allocated)</p>
                      <p className="font-medium">{benefit.paidLeaveDays} days</p>
                    </div>
                  )}
                  {profile.balancedPaidLeaveDays !== null && profile.balancedPaidLeaveDays !== undefined && (
                    <div>
                      <p className="text-sm text-muted-foreground">Paid Leave Days (Balance)</p>
                      <p className="font-medium">{profile.balancedPaidLeaveDays} days</p>
                    </div>
                  )}
                  {benefit.unpaidLeaveDays !== null && benefit.unpaidLeaveDays !== undefined && (
                    <div>
                      <p className="text-sm text-muted-foreground">Unpaid Leave Days (Allocated)</p>
                      <p className="font-medium">{benefit.unpaidLeaveDays} days</p>
                    </div>
                  )}
                  {profile.balancedUnpaidLeaveDays !== null && profile.balancedUnpaidLeaveDays !== undefined && (
                    <div>
                      <p className="text-sm text-muted-foreground">Unpaid Leave Days (Balance)</p>
                      <p className="font-medium">{profile.balancedUnpaidLeaveDays} days</p>
                    </div>
                  )}
                    {benefit.weeklyOffDays && (
                    <div>
                      <p className="text-sm text-muted-foreground">Weekly Off Days</p>
                      <p className="font-medium">{benefit.weeklyOffDays}</p>
                    </div>
                  )}
                </div>
              </div>

              <Separator />

              {/* Allowances */}
              {(benefit.mealAllowance || benefit.transportAllowance || benefit.housingAllowance || 
                benefit.responsibilityAllowance || benefit.attendanceBonus || benefit.phoneSkillShiftAllowance) && (
                <>
                  <div>
                    <h3 className="text-lg font-semibold mb-3">Allowances</h3>
                    <div className="grid grid-cols-2 gap-4">
                      {benefit.mealAllowance && (
                        <div>
                          <p className="text-sm text-muted-foreground">Meal Allowance</p>
                          <p className="font-medium">{benefit.mealAllowance.toLocaleString()} {benefit.currency}</p>
                        </div>
                      )}
                      {benefit.transportAllowance && (
                        <div>
                          <p className="text-sm text-muted-foreground">Transport Allowance</p>
                          <p className="font-medium">{benefit.transportAllowance.toLocaleString()} {benefit.currency}</p>
                        </div>
                      )}
                      {benefit.housingAllowance && (
                        <div>
                          <p className="text-sm text-muted-foreground">Housing Allowance</p>
                          <p className="font-medium">{benefit.housingAllowance.toLocaleString()} {benefit.currency}</p>
                        </div>
                      )}
                      {benefit.responsibilityAllowance && (
                        <div>
                          <p className="text-sm text-muted-foreground">Responsibility Allowance</p>
                          <p className="font-medium">{benefit.responsibilityAllowance.toLocaleString()} {benefit.currency}</p>
                        </div>
                      )}
                      {benefit.attendanceBonus && (
                        <div>
                          <p className="text-sm text-muted-foreground">Attendance Bonus</p>
                          <p className="font-medium">{benefit.attendanceBonus.toLocaleString()} {benefit.currency}</p>
                        </div>
                      )}
                      {benefit.phoneSkillShiftAllowance && (
                        <div>
                          <p className="text-sm text-muted-foreground">Phone/Skill/Shift Allowance</p>
                          <p className="font-medium">{benefit.phoneSkillShiftAllowance.toLocaleString()} {benefit.currency}</p>
                        </div>
                      )}
                    </div>
                  </div>
                  <Separator />
                </>
              )}

              {/* Overtime Configuration */}
              {(benefit.otRateWeekday || benefit.otRateWeekend || benefit.otRateHoliday || benefit.nightShiftRate) && (
                <>
                  <div>
                    <h3 className="text-lg font-semibold mb-3">Overtime Configuration</h3>
                    <div className="grid grid-cols-2 gap-4">
                      {benefit.otRateWeekday && (
                        <div>
                          <p className="text-sm text-muted-foreground">OT Rate (Weekday)</p>
                          <p className="font-medium">{benefit.otRateWeekday}x</p>
                        </div>
                      )}
                      {benefit.otRateWeekend && (
                        <div>
                          <p className="text-sm text-muted-foreground">OT Rate (Weekend)</p>
                          <p className="font-medium">{benefit.otRateWeekend}x</p>
                        </div>
                      )}
                      {benefit.otRateHoliday && (
                        <div>
                          <p className="text-sm text-muted-foreground">OT Rate (Holiday)</p>
                          <p className="font-medium">{benefit.otRateHoliday}x</p>
                        </div>
                      )}
                      {benefit.nightShiftRate && (
                        <div>
                          <p className="text-sm text-muted-foreground">Night Shift Rate</p>
                          <p className="font-medium">{benefit.nightShiftRate}x</p>
                        </div>
                      )}
                    </div>
                  </div>
                  <Separator />
                </>
              )}

              {/* Health Insurance */}
              {benefit.hasHealthInsurance && (
                <div>
                  <h3 className="text-lg font-semibold mb-3">Health Insurance</h3>
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <p className="text-sm text-muted-foreground">Coverage</p>
                      <Badge variant="default">Included</Badge>
                    </div>
                    {benefit.healthInsuranceRate && (
                      <div>
                        <p className="text-sm text-muted-foreground">Insurance Rate</p>
                        <p className="font-medium">{(benefit.healthInsuranceRate * 100).toFixed(2)}%</p>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
};
