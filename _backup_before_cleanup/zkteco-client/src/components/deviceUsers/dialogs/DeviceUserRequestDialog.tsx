// ==========================================
// src/components/dialogs/CreateUserDialog.tsx
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
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
} from "@/components/ui/form";
import { PasswordInput } from "../../password-input";
import { UpdateDeviceUserRequest } from "@/types/deviceUser";
import { useDeviceUserContext } from "@/contexts/DeviceUserContext";

const updateFormSchema = z.object({
  pin: z.string().min(1, "PIN is required"),
  name: z.string().min(1, "Full name is required"),
  cardNumber: z.string().optional(),
  password: z.string().optional(),
  privilege: z.number(),
  deviceName: z.string().optional(),
});

const defaultValues: z.infer<typeof updateFormSchema> = {
  pin: "",
  name: "",
  cardNumber: "",
  password: "",
  privilege: 0,
  deviceName: "", 
};

export const DeviceUserRequestDialog = () => {
  const {
    createDialogOpen,
    employeeToEdit,
    setCreateDialogOpen,
    handleUpdateDeviceUser,
  } = useDeviceUserContext()

  const form = useForm<z.infer<typeof updateFormSchema>>({
    resolver: zodResolver(updateFormSchema),
    defaultValues: defaultValues,
  });

  useEffect(() => {
    if (employeeToEdit) {
      form.reset({ ...defaultValues, ...employeeToEdit });
    } 
  }, [employeeToEdit, createDialogOpen, form]);

  const onSubmit = async (data: z.infer<typeof updateFormSchema>) => {
    if (!employeeToEdit) return;
    
    const updateParams: UpdateDeviceUserRequest = {
      userId: employeeToEdit.id ?? "",
      deviceId: employeeToEdit.deviceId,
      pin: data.pin,
      name: data.name,
      cardNumber: data.cardNumber,
      password: data.password,
      privilege: data.privilege,
    };

    await handleUpdateDeviceUser(updateParams);
    setCreateDialogOpen(false);
    form.reset({
      pin: '',
      name: '',
      cardNumber: '',
      password: '',
      privilege: 0,
    });
  };

  return (
    <Dialog open={createDialogOpen} onOpenChange={setCreateDialogOpen}>
      <DialogContent className="sm:max-w-[600px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Edit Device User</DialogTitle>
          <DialogDescription>
            Update device user information
          </DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <FormField
                control={form.control}
                name="deviceName"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Device Name</FormLabel>
                    <FormControl>
                      <Input
                        {...field}
                        required
                        disabled
                      />
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
                    <FormLabel>PIN *</FormLabel>
                    <FormControl>
                      <Input
                        {...field}
                        placeholder="1001"
                        required
                        disabled
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
                Update User
              </Button>
            </div>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
};

