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
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { AlertTriangle } from "lucide-react";
import { SalaryProfileForm } from './BenefitForm';
import { useSalaryProfileContext } from "@/contexts/BenefitContext";
import { UpdateBenefitRequest } from '@/types/benefit';

export const EditSalaryProfileDialog = () => {
  const { editDialogOpen, setEditDialogOpen, profileToEdit, handleUpdateProfile, isUpdatePending } = useSalaryProfileContext();
  const [formData, setFormData] = useState<UpdateBenefitRequest>({ ...profileToEdit } as UpdateBenefitRequest);
  const [showConfirmation, setShowConfirmation] = useState(false);

  useEffect(() => {
    if (profileToEdit) {
      setFormData({ ...profileToEdit });
    }
  }, [profileToEdit]);

  const handleSubmitClick = () => {
    // Show confirmation dialog
    setShowConfirmation(true);
  };

  const handleConfirmedSubmit = async () => {
    setShowConfirmation(false);
    await handleUpdateProfile(formData);
  };

  const employeeCount = profileToEdit?.employees?.length || 0;

  return (
    <>
      <Dialog open={editDialogOpen} onOpenChange={setEditDialogOpen}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Edit Benefit Profile</DialogTitle>
            <DialogDescription>
              Update benefit profile information
            </DialogDescription>
          </DialogHeader>

          {employeeCount > 0 && (
            <Alert variant="destructive">
              <AlertTriangle className="h-4 w-4" />
              <AlertDescription>
                Warning: This benefit is currently assigned to {employeeCount} employee{employeeCount !== 1 ? 's' : ''}. 
                Changes will affect all current assignments.
              </AlertDescription>
            </Alert>
          )}

          <SalaryProfileForm
            formData={formData as any}
            onChange={(data) => setFormData({ ...formData, ...data })}
            showActiveToggle
          />

          <DialogFooter>
            <Button variant="outline" onClick={() => setEditDialogOpen(false)} disabled={isUpdatePending}>
              Cancel
            </Button>
            <Button
              onClick={handleSubmitClick}
              disabled={!formData.name || !formData.rate || isUpdatePending}
            >
              {isUpdatePending ? 'Updating...' : 'Update Profile'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <AlertDialog open={showConfirmation} onOpenChange={setShowConfirmation}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Confirm Benefit Update</AlertDialogTitle>
            <AlertDialogDescription className="space-y-2">
              <p>
                You are about to update the benefit profile "<strong>{formData.name}</strong>".
              </p>
              {employeeCount > 0 && (
                <p className="text-destructive font-medium">
                  This change will immediately affect {employeeCount} employee{employeeCount !== 1 ? 's' : ''} who {employeeCount !== 1 ? 'are' : 'is'} currently using this benefit profile.
                </p>
              )}
              <p>
                Are you sure you want to continue?
              </p>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleConfirmedSubmit} disabled={isUpdatePending}>
              {isUpdatePending ? 'Updating...' : 'Yes, Update Profile'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
};
