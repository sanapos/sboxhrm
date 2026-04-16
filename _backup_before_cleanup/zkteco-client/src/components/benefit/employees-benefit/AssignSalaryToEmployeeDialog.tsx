import { useState, useEffect } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import { useSalaryProfileContext } from "@/contexts/BenefitContext";
import { useEmployees } from "@/hooks/useEmployee";
import { format } from 'date-fns';
import { useAssignEmployee, useBenefits } from '@/hooks/useBenefits';
import { AssignSalaryProfileRequest } from '@/types/benefit';

const defaultFormData: AssignSalaryProfileRequest = {
  employeeId: '',
  benefitId: '',
  effectiveDate: format(new Date(), 'yyyy-MM-dd'),
  notes: '',
};

export const AssignSalaryToEmployeeDialog = () => {
  const { assignDialogOpen, setAssignDialogOpen, preSelectedEmployeeId } = useSalaryProfileContext();
  const { data: employeesData } = useEmployees({ pageSize: 1000 });
  const [submitting, setSubmitting] = useState(false);
  const [formData, setFormData] = useState<AssignSalaryProfileRequest>(defaultFormData);
  const assignSalaryProfile = useAssignEmployee();
  
  // Get selected employee to determine employment type
  const selectedEmployee = employeesData?.items?.find(e => e.id === formData.employeeId);
  const employmentType = selectedEmployee?.employmentType;
  
  // Fetch salary profiles based on employee's employment type
  const { data: salaryProfilesData } = useBenefits(
    employmentType !== undefined ? employmentType : undefined
  );

  useEffect(() => {
    if (assignDialogOpen && preSelectedEmployeeId) {
      // Pre-select the employee if provided
      setFormData({ ...defaultFormData, employeeId: preSelectedEmployeeId });
    } else if (!assignDialogOpen) {
      setFormData(defaultFormData);
    }
  }, [assignDialogOpen, preSelectedEmployeeId]);

  const handleSubmit = async () => {
    if (!formData.employeeId) {
      toast.error('Please select an employee');
      return;
    }

    if (!formData.benefitId) {
      toast.error('Please select a benefit profile');
      return;
    }

    try {
      setSubmitting(true);
      await assignSalaryProfile.mutateAsync(formData);
      setAssignDialogOpen(false);
      setFormData(defaultFormData);
    } catch (error: any) {
      toast.error(error.message || 'Failed to assign benefit profile');
    } finally {
      setSubmitting(false);
    }
  };

  const handleClose = () => {
    setFormData(defaultFormData);
    setAssignDialogOpen(false);
  };

  const selectedProfile = salaryProfilesData?.find(p => p.id === formData.benefitId);

  return (
    <Dialog open={assignDialogOpen} onOpenChange={handleClose}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Assign Benefit Profile</DialogTitle>
          <DialogDescription>
            Select an employee and assign a benefit profile
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 py-4">
          <div className="grid gap-2">
            <Label htmlFor="employee">Employee *</Label>
            <Select
              value={formData.employeeId}
              onValueChange={(value) => setFormData({ ...formData, employeeId: value, benefitId: '' })}
              disabled={!!preSelectedEmployeeId}
            >
              <SelectTrigger id="employee">
                <SelectValue placeholder="Select an employee" />
              </SelectTrigger>
              <SelectContent>
                {employeesData?.items?.map((employee) => (
                  <SelectItem key={employee.id} value={employee.id}>
                    {employee.fullName} - {employee.employeeCode} ({employee.employmentType === 0 ? 'Hourly' : 'Monthly'})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {preSelectedEmployeeId && (
              <p className="text-xs text-muted-foreground">
                Employee is pre-selected for this assignment
              </p>
            )}
          </div>

          {selectedEmployee && (
            <div className="bg-muted p-3 rounded-md">
              <h4 className="font-medium text-sm mb-2">Employee Details</h4>
              <div className="text-sm space-y-1">
                <div>Name: {selectedEmployee.fullName}</div>
                <div>Code: {selectedEmployee.employeeCode}</div>
                <div>Type: {selectedEmployee.employmentType === 0 ? 'Hourly' : 'Monthly'}</div>
                <div>Department: {selectedEmployee.department || 'N/A'}</div>
              </div>
            </div>
          )}

          <div className="grid gap-2">
            <Label htmlFor="salaryProfile">Benefit Profile *</Label>
            <Select
              value={formData.benefitId}
              onValueChange={(value) => setFormData({ ...formData, benefitId: value })}
              disabled={!formData.employeeId}
            >
              <SelectTrigger id="salaryProfile">
                <SelectValue placeholder={!formData.employeeId ? "Select employee first" : "Select a benefit profile"} />
              </SelectTrigger>
              <SelectContent>
                {salaryProfilesData?.map((profile) => (
                  <SelectItem key={profile.id} value={profile.id}>
                    {profile.name} - {profile.rate.toLocaleString()} {profile.currency}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {selectedProfile && (
            <div className="bg-muted p-3 rounded-md">
              <h4 className="font-medium text-sm mb-2">Profile Details</h4>
              <div className="text-sm space-y-1">
                <div>Name: {selectedProfile.name}</div>
                <div>Rate: {selectedProfile.rate.toLocaleString()} {selectedProfile.currency}</div>
                {selectedProfile.overtimeMultiplier && (
                  <div>Overtime: {selectedProfile.overtimeMultiplier}x</div>
                )}
                {selectedProfile.holidayMultiplier && (
                  <div>Holiday: {selectedProfile.holidayMultiplier}x</div>
                )}
                {selectedProfile.nightShiftMultiplier && (
                  <div>Night Shift: {selectedProfile.nightShiftMultiplier}x</div>
                )}
              </div>
            </div>
          )}

          <div className="grid gap-2">
            <Label htmlFor="effectiveDate">Effective Date *</Label>
            <Input
              id="effectiveDate"
              type="date"
              value={formData.effectiveDate}
              onChange={(e) => setFormData({ ...formData, effectiveDate: e.target.value })}
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="notes">Notes</Label>
            <Textarea
              id="notes"
              value={formData.notes}
              onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
              placeholder="Optional notes about this assignment"
              rows={3}
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={handleClose} disabled={submitting}>
            Cancel
          </Button>
          <Button
            onClick={handleSubmit}
            disabled={!formData.employeeId || !formData.benefitId || submitting}
          >
            {submitting ? 'Assigning...' : 'Assign Profile'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
