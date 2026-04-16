// ==========================================
// src/components/employees/AddEmployeeToDeviceDialog.tsx
// ==========================================
import { useEffect } from "react";
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
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { UserPrivileges } from "@/constants";
import { Button } from "../../ui/button";
import { useDevices } from "@/hooks/useDevices";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
} from "@/components/ui/form";
import { PasswordInput } from "../../password-input";
import { useEmployeeContext } from "@/contexts/EmployeeContext";
import { useCreateDeviceUser } from "@/hooks/useDeviceUsers";

const formSchema = z.object({
  pin: z.string().min(1, "PIN is required"),
  name: z.string().min(1, "Full name is required"),
  cardNumber: z.string().optional(),
  password: z.string().optional(),
  privilege: z.number(),
  deviceId: z.string().min(1, "Please select a device"),
  employeeId: z.string().min(1, "Employee ID is required"),
});

const defaultValues: z.infer<typeof formSchema> = {
  pin: "",
  name: "",
  cardNumber: "",
  password: "",
  privilege: 0,
  deviceId: "",
  employeeId: "",
};

export const AddEmployeeToDeviceDialog = () => {
  const {
    addToDeviceDialogOpen,
    employeeToAddToDevice,
    setAddToDeviceDialogOpen,
  } = useEmployeeContext();

  const addDeviceUser = useCreateDeviceUser();
  
  const { data: devices } = useDevices();

  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema),
    defaultValues: defaultValues,
  });

  useEffect(() => {
    if (employeeToAddToDevice) {
      form.reset({
        ...defaultValues,
        pin: employeeToAddToDevice.employeeCode ?? '',
        name: employeeToAddToDevice.fullName ?? '',
        employeeId: employeeToAddToDevice.id ?? '',
      });
    }
  }, [employeeToAddToDevice, addToDeviceDialogOpen, form]);

  const onSubmit = async (data: z.infer<typeof formSchema>) => {
    await addDeviceUser.mutateAsync(data);
    setAddToDeviceDialogOpen(false);
    form.reset(defaultValues);
  };

  return (
    <Dialog open={addToDeviceDialogOpen} onOpenChange={setAddToDeviceDialogOpen}>
      <DialogContent className="sm:max-w-[600px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Add Employee to Device</DialogTitle>
          <DialogDescription>
            Add {employeeToAddToDevice?.fullName} to selected devices
          </DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <FormField
                control={form.control}
                name="deviceId"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Device *</FormLabel>
                    <FormControl>
                      <Select
                        value={field.value}
                        onValueChange={field.onChange}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Choose a device..." />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectGroup>
                            {devices?.map((device) => (
                              <SelectItem
                                key={device.id}
                                value={device.id}
                              >
                                {device.deviceName}
                              </SelectItem>
                            ))}
                          </SelectGroup>
                        </SelectContent>
                      </Select>
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="pin"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>PIN (Employee Code) *</FormLabel>
                    <FormControl>
                      <Input
                        {...field}
                        placeholder="1001"
                        required
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <FormField
                control={form.control}
                name="name"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Name *</FormLabel>
                    <FormControl>
                      <Input {...field} placeholder="Nguyen Van A" required />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="password"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Password</FormLabel>
                    <FormControl>
                      <PasswordInput id="password" {...field} />
                    </FormControl>
                    <FormMessage className="absolute left-0 mt-1 text-destructive" />
                  </FormItem>
                )}
              />
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <FormField
                control={form.control}
                name="cardNumber"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Card Number</FormLabel>
                    <FormControl>
                      <Input {...field} placeholder="1234567890" />
                    </FormControl>
                    <FormMessage className="absolute left-0 mt-1 text-destructive" />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="privilege"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Privilege</FormLabel>
                    <FormControl>
                      <Select
                        value={field.value?.toString()}
                        onValueChange={(value) => field.onChange(Number(value))}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Select privilege" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectGroup>
                            {Object.keys(UserPrivileges).map((key) => (
                              <SelectItem key={key} value={key}>
                                {
                                  UserPrivileges[
                                    +key as keyof typeof UserPrivileges
                                  ]
                                }
                              </SelectItem>
                            ))}
                          </SelectGroup>
                        </SelectContent>
                      </Select>
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            <div className="grid gap-4">
              <Button type="submit" className="ml-auto">
                Add to Device
              </Button>
            </div>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
};
