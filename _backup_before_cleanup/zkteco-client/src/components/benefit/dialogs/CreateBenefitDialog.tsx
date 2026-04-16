import { useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { SalaryProfileForm } from './BenefitForm';
import { useSalaryProfileContext } from "@/contexts/BenefitContext";
import { CreateBenefitRequest, SalaryRateType } from '@/types/benefit';

const defaultFormData: CreateBenefitRequest = {
  name: '',
  description: '',
  rateType: SalaryRateType.Hourly,
  rate: 0,
  currency: 'VND',
  overtimeMultiplier: 1.5,
  holidayMultiplier: 2.0,
  nightShiftMultiplier: 1.3,
  checkIn: "09:00:00",
  checkOut: "18:00:00",
  standardHoursPerDay: 8,
  weeklyOffDays: 'Saturday,Sunday',
  otRateHoliday: 3,
  otRateWeekday: 1.5,
  otRateWeekend: 2,
  nightShiftRate: 1.3
};

export const CreateSalaryProfileDialog = () => {
  const { createDialogOpen, setCreateDialogOpen, handleCreateProfile, isCreatePending } = useSalaryProfileContext();
  const [formData, setFormData] = useState<CreateBenefitRequest>(defaultFormData);

  const handleSubmit = async () => {
    await handleCreateProfile(formData);
    setFormData(defaultFormData);
  };

  const handleClose = () => {
    setFormData(defaultFormData);
    setCreateDialogOpen(false);
  };

  return (
    <Dialog open={createDialogOpen} onOpenChange={handleClose}>
      <DialogContent className="max-w-6xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Create Benefit Profile</DialogTitle>
          <DialogDescription>
            Create a new benefit profile for employees
          </DialogDescription>
        </DialogHeader>

        <SalaryProfileForm
          formData={formData}
          onChange={setFormData}
        />

        <DialogFooter>
          <Button variant="outline" onClick={handleClose} disabled={isCreatePending}>
            Cancel
          </Button>
          <Button
            onClick={handleSubmit}
            disabled={!formData.name || !formData.rate || isCreatePending}
          >
            {isCreatePending ? 'Creating...' : 'Create Profile'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
