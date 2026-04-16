import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { useForm } from "react-hook-form";
import { useUpdateShiftTimes } from "@/hooks/useShifts";
import { Shift, UpdateShiftTimesRequest } from "@/types/shift";
import { format } from "date-fns";
import { useEffect } from "react";
import { DateTimeFormat } from "@/constants";

interface EditShiftDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  shift: Shift | null;
}

export function EditShiftDialog({ open, onOpenChange, shift }: EditShiftDialogProps) {
  const { register, handleSubmit, reset, formState: { errors } } = useForm<{
    checkInTime: string;
    checkOutTime: string;
  }>();
  
  const updateShiftTimes = useUpdateShiftTimes();

  useEffect(() => {
    if (shift && open) {
      // Format existing times for datetime-local input (YYYY-MM-DDTHH:mm)
      const checkInValue = shift.checkInTime 
        ? format(new Date(shift.checkInTime), "yyyy-MM-dd'T'HH:mm")
        : '';
      const checkOutValue = shift.checkOutTime 
        ? format(new Date(shift.checkOutTime), "yyyy-MM-dd'T'HH:mm")
        : '';
      
      reset({
        checkInTime: checkInValue,
        checkOutTime: checkOutValue,
      });
    }
  }, [shift, open, reset]);

  const onSubmit = async (data: { checkInTime: string; checkOutTime: string }) => {
    if (!shift) return;

    // Convert datetime-local string to ISO string
    const payload: UpdateShiftTimesRequest = {
      checkInTime: data.checkInTime ? format(new Date(data.checkInTime), DateTimeFormat) : undefined,
      checkOutTime: data.checkOutTime ? format(new Date(data.checkOutTime), DateTimeFormat) : undefined,
    };

    await updateShiftTimes.mutateAsync({ id: shift.id, data: payload });
    onOpenChange(false);
  };

  if (!shift) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle>Edit Shift Times</DialogTitle>
          <DialogDescription>
            Update check-in and check-out times for {shift.employeeName}'s shift on{" "}
            {format(new Date(shift.startTime), "MMM dd, yyyy")}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="checkInTime">Check-In Time</Label>
            <Input
              id="checkInTime"
              type="datetime-local"
              {...register("checkInTime", {
                validate: (value, formValues) => {
                  if (value && formValues.checkOutTime) {
                    const checkIn = new Date(value);
                    const checkOut = new Date(formValues.checkOutTime);
                    if (checkOut <= checkIn) {
                      return "Check-out time must be after check-in time";
                    }
                  }
                  return true;
                }
              })}
              className="w-full"
            />
            {errors.checkInTime && (
              <p className="text-sm text-destructive">{errors.checkInTime.message}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label htmlFor="checkOutTime">Check-Out Time</Label>
            <Input
              id="checkOutTime"
              type="datetime-local"
              {...register("checkOutTime", {
                validate: (value, formValues) => {
                  if (value && formValues.checkInTime) {
                    const checkIn = new Date(formValues.checkInTime);
                    const checkOut = new Date(value);
                    if (checkOut <= checkIn) {
                      return "Check-out time must be after check-in time";
                    }
                  }
                  return true;
                }
              })}
              className="w-full"
            />
            {errors.checkOutTime && (
              <p className="text-sm text-destructive">{errors.checkOutTime.message}</p>
            )}
          </div>

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={updateShiftTimes.isPending}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={updateShiftTimes.isPending}>
              {updateShiftTimes.isPending ? "Updating..." : "Update Times"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
