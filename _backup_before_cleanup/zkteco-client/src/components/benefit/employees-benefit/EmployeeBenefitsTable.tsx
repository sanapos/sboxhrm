import { Eye, UserPlus } from "lucide-react";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useEmployeeBenefits } from "@/hooks/useBenefits";
import { useState } from "react";
import { EmployeeSalaryProfileDetailDialog } from "./EmployeeBenefitDetailDialog";
import { useSalaryProfileContext } from "@/contexts/BenefitContext";
import { LoadingSpinner } from "@/components/LoadingSpinner";
import { EmployeeBenefit, SalaryRateType } from "@/types/benefit";
import { formatDate } from "@/lib/utils";

const getRateTypeLabel = (type: SalaryRateType) => {
  switch (type) {
    case SalaryRateType.Hourly: return 'Hourly';
    case SalaryRateType.Monthly: return 'Monthly';
    default: return 'Unknown';
  }
};

export const EmployeeSalaryProfileTable = () => {
  const { data: employeeBenefits, isLoading } = useEmployeeBenefits();
  const [selectedProfile, setSelectedProfile] = useState<EmployeeBenefit | null>(null);
  const [detailDialogOpen, setDetailDialogOpen] = useState(false);
  const { handleOpenAssignDialog } = useSalaryProfileContext();

  const handleViewDetails = (profile: EmployeeBenefit) => {
    setSelectedProfile(profile);
    setDetailDialogOpen(true);
  };

  if (isLoading) {
    return (
      <div className="text-center py-8">
        <LoadingSpinner />
      </div>
    );
  }

  console.log("Employee Benefits:", employeeBenefits);
  return (
    <>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Employee</TableHead>
            <TableHead>Employee Code</TableHead>
            <TableHead>Benefit's Name</TableHead>
            <TableHead>Rate</TableHead>
            <TableHead>Effective Date</TableHead>
            <TableHead>Notes</TableHead>
            <TableHead>Actions</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
         {
          employeeBenefits && employeeBenefits.length > 0 ? (
            employeeBenefits.map((benefit) => (
              <TableRow key={benefit.id}>
                <TableCell>
                  {benefit.employee ? (
                    <div>
                      <div className="font-medium">{benefit.employee.fullName}</div>
                      <div className="text-sm text-muted-foreground">{benefit.employee.department || '-'}</div>
                    </div>
                  ) : (
                    <Badge variant="warning">No Employee Assigned</Badge>
                  )}
                </TableCell>
                <TableCell>{benefit.employee?.employeeCode || '-'}</TableCell>
                <TableCell>{benefit.benefit?.name || '-'}</TableCell>
                <TableCell>{getRateTypeLabel(benefit.employee?.employmentType)}</TableCell>
                <TableCell>{formatDate(benefit.effectiveDate)}</TableCell>
                <TableCell>{benefit.notes || '-'}</TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    {
                      benefit.benefit ? (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => handleViewDetails(benefit)}
                        >
                          <Eye className="mr-2 h-4 w-4" />
                          View Details
                        </Button>
                      ) : (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => handleOpenAssignDialog(benefit.employeeId)}
                        >
                          <UserPlus className="mr-2 h-4 w-4" />
                          Assign Benefit
                        </Button>
                      )
                    }
                    
                  </div>
                </TableCell>
              </TableRow>
            ))
          ) : (
            <TableRow>
              <TableCell colSpan={7} className="text-center py-4">
                No employee salary profiles found.
              </TableCell>
            </TableRow>
          )
         }
        </TableBody>
      </Table>

      <EmployeeSalaryProfileDetailDialog
        open={detailDialogOpen}
        onOpenChange={setDetailDialogOpen}
        profile={selectedProfile}
      />
    </>
  );
};

