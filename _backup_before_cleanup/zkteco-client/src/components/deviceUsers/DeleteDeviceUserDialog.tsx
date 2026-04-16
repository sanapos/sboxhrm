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
import { useDeviceUserContext } from "@/contexts/DeviceUserContext";

export const DeleteDeviceUserDialog = () => {
  const {
    deleteDialogOpen,
    employeeToDelete,
    isDeletePending,
    setDeleteDialogOpen,
    handleConfirmDelete
  } = useDeviceUserContext()
  return (
    <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Are you sure?</AlertDialogTitle>
          <AlertDialogDescription>
            This will permanently delete the employee{" "}
            <span className="font-semibold text-foreground">
              {employeeToDelete?.name}
            </span>{" "}
            (PIN: {employeeToDelete?.pin}).
            <br />
            <br />
            This action cannot be undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={isDeletePending}>Cancel</AlertDialogCancel>
          <AlertDialogAction
            onClick={handleConfirmDelete}
            disabled={isDeletePending}
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
          >
            {isDeletePending ? "Deleting..." : "Delete"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
};
