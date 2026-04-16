// ==========================================
// src/components/deviceUsers/dialogs/MapToEmployeeDialog.tsx
// ==========================================
import { useState, useEffect } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
  FormDescription,
} from "@/components/ui/form";
import { DeviceUser } from "@/types/deviceUser";
import { useEmployees } from "@/hooks/useEmployee";
import { Search, UserPlus } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";

const formSchema = z.object({
  employeeId: z.string().min(1, "Please select an employee"),
});

interface MapToEmployeeDialogProps {
  open: boolean;
  deviceUser: DeviceUser | null;
  onOpenChange: (open: boolean) => void;
  onConfirm: (deviceUserId: string, employeeId: string) => Promise<void>;
}

export const MapToEmployeeDialog = ({
  open,
  deviceUser,
  onOpenChange,
  onConfirm,
}: MapToEmployeeDialogProps) => {
  const [searchTerm, setSearchTerm] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  const { data: employeesData, isLoading } = useEmployees({
    pageNumber: 1,
    pageSize: 100,
    searchTerm: searchTerm || undefined,
  });

  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      employeeId: "",
    },
  });

  useEffect(() => {
    if (!open) {
      form.reset();
      setSearchTerm("");
    }
  }, [open, form]);

  const onSubmit = async (data: z.infer<typeof formSchema>) => {
    if (!deviceUser) return;
    
    setIsSubmitting(true);
    try {
      await onConfirm(deviceUser.id, data.employeeId);
      onOpenChange(false);
    } catch (error) {
      console.error("Failed to map device user to employee:", error);
    } finally {
      setIsSubmitting(false);
    }
  };

  const employees = employeesData?.items || [];
  const selectedEmployee = employees.find(
    (emp) => emp.id === form.watch("employeeId")
  );

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[600px] max-h-[90vh]">
        <DialogHeader>
          <DialogTitle>Map Device User to Employee</DialogTitle>
          <DialogDescription>
            Link {deviceUser?.name} (PIN: {deviceUser?.pin}) to an employee record
          </DialogDescription>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
            {/* Device User Info */}
            <div className="rounded-lg border p-4 bg-muted/50">
              <h4 className="text-sm font-semibold mb-2">Device User Information</h4>
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div>
                  <span className="text-muted-foreground">Name:</span>
                  <span className="ml-2 font-medium">{deviceUser?.name}</span>
                </div>
                <div>
                  <span className="text-muted-foreground">PIN:</span>
                  <span className="ml-2 font-medium">{deviceUser?.pin}</span>
                </div>
                <div>
                  <span className="text-muted-foreground">Device:</span>
                  <span className="ml-2 font-medium">{deviceUser?.deviceName}</span>
                </div>
                <div>
                  <span className="text-muted-foreground">Card:</span>
                  <span className="ml-2 font-medium">{deviceUser?.cardNumber || "-"}</span>
                </div>
              </div>
            </div>

            <Separator />

            {/* Search Employees */}
            <div className="space-y-2">
              <label className="text-sm font-medium">Search Employees</label>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Search by name or employee code..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-10"
                />
              </div>
            </div>

            {/* Employee Selection */}
            <FormField
              control={form.control}
              name="employeeId"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Select Employee *</FormLabel>
                  <FormControl>
                    <Select
                      value={field.value}
                      onValueChange={field.onChange}
                      disabled={isLoading}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Choose an employee..." />
                      </SelectTrigger>
                      <SelectContent>
                        <div className="max-h-[200px] overflow-y-auto">
                          {employees.length === 0 ? (
                            <div className="p-4 text-center text-sm text-muted-foreground">
                              {isLoading ? "Loading..." : "No employees found"}
                            </div>
                          ) : (
                            employees.map((employee) => (
                              <SelectItem key={employee.id} value={employee.id}>
                                <div className="flex items-center gap-2">
                                  <span className="font-medium">
                                    {employee.fullName}
                                  </span>
                                  <Badge variant="outline" className="text-xs">
                                    {employee.employeeCode}
                                  </Badge>
                                </div>
                              </SelectItem>
                            ))
                          )}
                        </div>
                      </SelectContent>
                    </Select>
                  </FormControl>
                  <FormDescription>
                    Select the employee to link with this device user
                  </FormDescription>
                  <FormMessage />
                </FormItem>
              )}
            />

            {/* Selected Employee Preview */}
            {selectedEmployee && (
              <div className="rounded-lg border p-4 bg-primary/5">
                <h4 className="text-sm font-semibold mb-2 flex items-center gap-2">
                  <UserPlus className="h-4 w-4" />
                  Selected Employee
                </h4>
                <div className="grid grid-cols-2 gap-2 text-sm">
                  <div>
                    <span className="text-muted-foreground">Full Name:</span>
                    <span className="ml-2 font-medium">{selectedEmployee.fullName}</span>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Code:</span>
                    <span className="ml-2 font-medium">{selectedEmployee.employeeCode}</span>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Department:</span>
                    <span className="ml-2 font-medium">{selectedEmployee.department || "-"}</span>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Position:</span>
                    <span className="ml-2 font-medium">{selectedEmployee.position || "-"}</span>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Email:</span>
                    <span className="ml-2 font-medium text-xs">{selectedEmployee.companyEmail || "-"}</span>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Status:</span>
                    <Badge variant="outline" className="ml-2">
                      {selectedEmployee.workStatus || "Active"}
                    </Badge>
                  </div>
                </div>
              </div>
            )}

            {/* Actions */}
            <div className="flex justify-end gap-2 pt-4">
              <Button
                type="button"
                variant="outline"
                onClick={() => onOpenChange(false)}
                disabled={isSubmitting}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={isSubmitting}>
                {isSubmitting ? "Mapping..." : "Map to Employee"}
              </Button>
            </div>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
};
