// ==========================================
// src/components/employeeInfo/EmployeeFormDialog.tsx
// ==========================================
import { useEffect } from "react";
import { useForm } from "react-hook-form";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Loader2 } from "lucide-react";
import { Employee, UpdateEmployeeRequest } from "@/types/employee";
import { useEmployeeContext } from "@/contexts/EmployeeContext";

export const NewEmployeeDialog = () => {
  const {
    createDialogOpen,
    setCreateDialogOpen,
    employeeToEdit,
    handleAddEmployee,
    handleUpdateEmployee,
    isCreatePending,
    isUpdatePending,
  } = useEmployeeContext();

  const isEditMode = !!employeeToEdit;
  const isPending = isCreatePending || isUpdatePending;

  const { register, handleSubmit, reset, setValue, watch } = useForm<UpdateEmployeeRequest>({
    defaultValues: {
      employeeCode: "",
      firstName: "",
      lastName: "",
      gender: "Male",
      dateOfBirth: null,
      photoUrl: "",
      nationalIdNumber: "",
      nationalIdIssueDate: null,
      nationalIdIssuePlace: "",
      personalEmail: "",
      companyEmail: "",
      phoneNumber: "",
      permanentAddress: "",
      temporaryAddress: "",
      emergencyContactName: "",
      emergencyContactPhone: "",
      department: "",
      position: "",
      level: "",
      employmentType: 0,
      joinDate: null,
      probationEndDate: null,
      workStatus: 0,
      resignationDate: null,
      resignationReason: null,
      pin: "",
      cardNumber: "",
      deviceId: undefined,
      applicationUserId: undefined,
    },
  });

  useEffect(() => {
    if (isEditMode && employeeToEdit) {
      // Populate form with employee data for editing
      Object.keys(employeeToEdit).forEach((key) => {
        const value = employeeToEdit[key as keyof Employee];
        if (value !== undefined && value !== null) {
          // Convert dates to YYYY-MM-DD format for input[type="date"]
          if (key.includes('Date') && value) {
            setValue(key as any, new Date(value as string).toISOString().split('T')[0]);
          } else {
            setValue(key as any, value as any);
          }
        }
      });
    } else {
      reset();
    }
  }, [employeeToEdit, isEditMode, reset, setValue]);

  const onSubmit = async (data: any) => {
    if (isEditMode) {
      await handleUpdateEmployee({ ...data, id: employeeToEdit!.id });
    } else {
      await handleAddEmployee(data);
    }
  };

  return (
    <Dialog open={createDialogOpen} onOpenChange={setCreateDialogOpen}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEditMode ? "Edit Employee" : "Add New Employee"}</DialogTitle>
          <DialogDescription>
            {isEditMode
              ? "Update employee information below"
              : "Fill in the employee information below"}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit(onSubmit)}>
          <Tabs defaultValue="identity" className="w-full">
            <TabsList className="grid w-full grid-cols-3">
              <TabsTrigger value="identity">Identity</TabsTrigger>
              <TabsTrigger value="contact">Contact</TabsTrigger>
              <TabsTrigger value="work">Work Info</TabsTrigger>
            </TabsList>

            <TabsContent value="identity" className="space-y-4 mt-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="employeeCode">
                    Employee Code <span className="text-destructive">*</span>
                  </Label>
                  <Input id="employeeCode" {...register("employeeCode", { required: true })} />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="gender">Gender</Label>
                  <Select
                    value={watch("gender")}
                    onValueChange={(value) => setValue("gender", value)}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Male">Male</SelectItem>
                      <SelectItem value="Female">Female</SelectItem>
                      <SelectItem value="Other">Other</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="firstName">
                    First Name <span className="text-destructive">*</span>
                  </Label>
                  <Input id="firstName" {...register("firstName", { required: true })} />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="lastName">
                    Last Name <span className="text-destructive">*</span>
                  </Label>
                  <Input id="lastName" {...register("lastName", { required: true })} />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="dateOfBirth">Date of Birth</Label>
                  <Input id="dateOfBirth" type="date" {...register("dateOfBirth")} />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="nationalIdNumber">National ID</Label>
                  <Input id="nationalIdNumber" {...register("nationalIdNumber")} />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="nationalIdIssueDate">ID Issue Date</Label>
                  <Input id="nationalIdIssueDate" type="date" {...register("nationalIdIssueDate")} />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="nationalIdIssuePlace">ID Issue Place</Label>
                  <Input id="nationalIdIssuePlace" {...register("nationalIdIssuePlace")} />
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="companyEmail">
                  Company Email <span className="text-destructive">*</span>
                </Label>
                <Input id="companyEmail" type="email" {...register("companyEmail", { required: true })} />
              </div>

              <div className="space-y-2">
                <Label htmlFor="employmentType">Employment Type</Label>
                <Select
                  value={watch("employmentType")?.toString()}
                  onValueChange={(value) => setValue("employmentType", parseInt(value))}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="0">Hourly</SelectItem>
                    <SelectItem value="1">Monthly</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </TabsContent>

            <TabsContent value="contact" className="space-y-4 mt-4">
              <div className="space-y-2">
                <Label htmlFor="personalEmail">Personal Email</Label>
                <Input id="personalEmail" type="email" {...register("personalEmail")} />
              </div>

              <div className="space-y-2">
                <Label htmlFor="phoneNumber">Phone Number</Label>
                <Input id="phoneNumber" {...register("phoneNumber")} />
              </div>

              <div className="space-y-2">
                <Label htmlFor="permanentAddress">Permanent Address</Label>
                <Input id="permanentAddress" {...register("permanentAddress")} />
              </div>

              <div className="space-y-2">
                <Label htmlFor="temporaryAddress">Temporary Address</Label>
                <Input id="temporaryAddress" {...register("temporaryAddress")} />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="emergencyContactName">Emergency Contact Name</Label>
                  <Input id="emergencyContactName" {...register("emergencyContactName")} />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="emergencyContactPhone">Emergency Contact Phone</Label>
                  <Input id="emergencyContactPhone" {...register("emergencyContactPhone")} />
                </div>
              </div>
            </TabsContent>

            <TabsContent value="work" className="space-y-4 mt-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="department">Department</Label>
                  <Input id="department" {...register("department")} />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="position">Position</Label>
                  <Input id="position" {...register("position")} />
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="level">Level</Label>
                <Input id="level" {...register("level")} />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="joinDate">Join Date</Label>
                  <Input id="joinDate" type="date" {...register("joinDate")} />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="probationEndDate">Probation End Date</Label>
                  <Input id="probationEndDate" type="date" {...register("probationEndDate")} />
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="workStatus">Work Status</Label>
                <Select
                  value={watch("workStatus")?.toString()}
                  onValueChange={(value) => setValue("workStatus", parseInt(value))}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="0">Active</SelectItem>
                    <SelectItem value="1">Resigned</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              {watch("workStatus") === 1 && (
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="resignationDate">Resignation Date</Label>
                    <Input id="resignationDate" type="date" {...register("resignationDate")} />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="resignationReason">Resignation Reason</Label>
                    <Input id="resignationReason" {...register("resignationReason")} />
                  </div>
                </div>
              )}

            </TabsContent>
          </Tabs>

          <DialogFooter className="mt-6">
            <Button
              type="button"
              variant="outline"
              onClick={() => setCreateDialogOpen(false)}
              disabled={isPending}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={isPending}>
              {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              {isEditMode ? "Update" : "Create"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};
