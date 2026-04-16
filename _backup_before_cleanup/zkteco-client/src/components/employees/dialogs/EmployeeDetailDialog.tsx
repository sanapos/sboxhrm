// ==========================================
// src/components/deviceUsers/dialogs/ViewLinkedEmployeeDialog.tsx
// ==========================================
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Employee } from "@/types/employee";
import { 
  User, 
  Mail, 
  Phone, 
  Building2, 
  Briefcase, 
  Calendar,
  MapPin,
  CreditCard,
  Hash
} from "lucide-react";
import { formatDate } from "@/lib/utils";
import { EmploymentTypes } from "@/constants";

interface EmployeeDetailDialogProps {
  open: boolean;
  employee: Employee | null;
  onOpenChange: (open: boolean) => void;
}

export const EmployeeDetailDialog = ({
  open,
  employee,
  onOpenChange,
}: EmployeeDetailDialogProps) => {
  if (!employee) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[700px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <User className="h-5 w-5" />
            {employee.fullName}
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* Identity Information */}
          <div>
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2">
              <User className="h-4 w-4" />
              Identity Information
            </h3>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Employee Code</label>
                <div className="flex items-center gap-2">
                  <Hash className="h-3 w-3 text-muted-foreground" />
                  <p className="text-sm font-medium">{employee.employeeCode}</p>
                </div>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Full Name</label>
                <p className="text-sm font-medium">{employee.fullName || `${employee.firstName} ${employee.lastName}`}</p>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Gender</label>
                <p className="text-sm">{employee.gender || "-"}</p>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Date of Birth</label>
                <div className="flex items-center gap-2">
                  <Calendar className="h-3 w-3 text-muted-foreground" />
                  <p className="text-sm">{formatDate(employee.dateOfBirth)}</p>
                </div>
              </div>
              {employee.nationalIdNumber && (
                <>
                  <div className="space-y-1">
                    <label className="text-xs text-muted-foreground">National ID</label>
                    <div className="flex items-center gap-2">
                      <CreditCard className="h-3 w-3 text-muted-foreground" />
                      <p className="text-sm">{employee.nationalIdNumber}</p>
                    </div>
                  </div>
                  <div className="space-y-1">
                    <label className="text-xs text-muted-foreground">Issue Date</label>
                    <p className="text-sm">{formatDate(employee.nationalIdIssueDate)}</p>
                  </div>
                </>
              )}
            </div>
          </div>

          <Separator />

          {/* Contact Information */}
          <div>
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2">
              <Mail className="h-4 w-4" />
              Contact Information
            </h3>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Phone Number</label>
                <div className="flex items-center gap-2">
                  <Phone className="h-3 w-3 text-muted-foreground" />
                  <p className="text-sm">{employee.phoneNumber || "-"}</p>
                </div>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Company Email</label>
                <div className="flex items-center gap-2">
                  <Mail className="h-3 w-3 text-muted-foreground" />
                  <p className="text-sm">{employee.companyEmail || "-"}</p>
                </div>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Personal Email</label>
                <p className="text-sm">{employee.personalEmail || "-"}</p>
              </div>
              {employee.permanentAddress && (
                <div className="space-y-1 col-span-2">
                  <label className="text-xs text-muted-foreground">Permanent Address</label>
                  <div className="flex items-start gap-2">
                    <MapPin className="h-3 w-3 text-muted-foreground mt-0.5" />
                    <p className="text-sm">{employee.permanentAddress}</p>
                  </div>
                </div>
              )}
            </div>
          </div>

          <Separator />

          {/* Work Information */}
          <div>
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2">
              <Briefcase className="h-4 w-4" />
              Work Information
            </h3>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Department</label>
                <div className="flex items-center gap-2">
                  <Building2 className="h-3 w-3 text-muted-foreground" />
                  <p className="text-sm">{employee.department || "-"}</p>
                </div>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Position</label>
                <p className="text-sm">{employee.position || "-"}</p>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Level</label>
                <p className="text-sm">{employee.level || "-"}</p>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Employment Type</label>
                <p className="text-sm">{EmploymentTypes[employee.employmentType as keyof typeof EmploymentTypes] || "-"}</p>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Join Date</label>
                <div className="flex items-center gap-2">
                  <Calendar className="h-3 w-3 text-muted-foreground" />
                  <p className="text-sm">{formatDate(employee.joinDate)}</p>
                </div>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Work Status</label>
                <Badge variant={employee.workStatus === "Active" ? "default" : "secondary"}>
                  {employee.workStatus || "Active"}
                </Badge>
              </div>
            </div>
          </div>

          {/* ZKTeco Integration Info */}
          {(employee.pin || employee.cardNumber) && (
            <>
              <Separator />
              <div>
                <h3 className="text-sm font-semibold mb-3">Device Integration</h3>
                <div className="grid grid-cols-2 gap-4">
                  {employee.pin && (
                    <div className="space-y-1">
                      <label className="text-xs text-muted-foreground">PIN</label>
                      <p className="text-sm font-mono">{employee.pin}</p>
                    </div>
                  )}
                  {employee.cardNumber && (
                    <div className="space-y-1">
                      <label className="text-xs text-muted-foreground">Card Number</label>
                      <p className="text-sm font-mono">{employee.cardNumber}</p>
                    </div>
                  )}
                </div>
              </div>
            </>
          )}
        </div>

        <div className="flex justify-end pt-4">
          <Button onClick={() => onOpenChange(false)}>
            Close
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};
