import { Button } from "@/components/ui/button";
import { Edit, Trash2 } from "lucide-react";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import {
  HoverCard,
  HoverCardContent,
  HoverCardTrigger,
} from "@/components/ui/hover-card";
import { useSalaryProfileContext } from "@/contexts/BenefitContext";
import { LoadingSpinner } from "../../LoadingSpinner";
import { SalaryRateType } from "@/types/benefit";

const getRateTypeLabel = (type: SalaryRateType) => {
  switch (type) {
    case SalaryRateType.Hourly: return 'Hourly';
    case SalaryRateType.Monthly: return 'Monthly';
    default: return 'Unknown';
  }
};

export const SalaryProfileTable = () => {
  const { benefits: profiles, isLoading, handleEdit, handleDelete } = useSalaryProfileContext();

  if (isLoading) {
    return (
      <div className="text-center py-8">
        <LoadingSpinner />  
      </div>
    );
  }

  console.log('profiles', profiles);

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Name</TableHead>
          <TableHead>Benefit Type</TableHead>
          <TableHead>Rate/Salary</TableHead>
          <TableHead>OT Multiplier</TableHead>
          <TableHead>Employees</TableHead>
          <TableHead className="text-right">Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {!profiles || profiles.length === 0 ? (
          <TableRow>
            <TableCell colSpan={7} className="text-center py-8 text-muted-foreground">
              No benefit profiles found
            </TableCell>
          </TableRow>
        ) : (
          profiles.map((profile) => (
            <TableRow key={profile.id}>
              <TableCell className="font-medium">{profile.name}</TableCell>
              <TableCell>
                <Badge variant="outline">{getRateTypeLabel(profile.rateType)}</Badge>
              </TableCell>
              <TableCell>
                {profile.rateType === SalaryRateType.Monthly 
                  ? `${profile.rate.toLocaleString()}`
                  : `${profile.rate.toLocaleString()}`
                }
              </TableCell>
              <TableCell>
                {profile.rateType === SalaryRateType.Hourly && profile.overtimeMultiplier
                  ? `${profile.overtimeMultiplier}x`
                  : 'N/A'}
              </TableCell>
              <TableCell>
                <HoverCard>
                  <HoverCardTrigger asChild>
                    <Button 
                      variant="ghost" 
                      size="sm"
                    >
                      <Badge variant="outline">
                        {profile.employees?.length || 0} Employees
                      </Badge>
                    </Button>
                  </HoverCardTrigger>
                  <HoverCardContent className="w-80">
                    <div className="space-y-2">
                      <h4 className="text-sm font-semibold">Employees using this benefit:</h4>
                      {profile.employees && profile.employees.length > 0 ? (
                        <div className="space-y-1">
                          {profile.employees.slice(0, 5).map((employee) => (
                            <div key={employee.id} className="text-sm">
                              • {employee.fullName} ({employee.employeeCode})
                            </div>
                          ))}
                          {profile.employees.length > 5 && (
                            <div className="text-sm text-muted-foreground italic">
                              + {profile.employees.length - 5} more...
                            </div>
                          )}
                        </div>
                      ) : (
                        <p className="text-sm text-muted-foreground">No employees assigned</p>
                      )}
                    </div>
                  </HoverCardContent>
                </HoverCard>
              </TableCell>
              <TableCell className="text-right">
                <div className="flex justify-end gap-2">
                  
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => handleEdit(profile)}
                  >
                    <Edit className="w-4 h-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => handleDelete(profile.id)}
                  >
                    <Trash2 className="w-4 h-4" />
                  </Button>
                </div>
              </TableCell>
            </TableRow>
          ))
        )}
      </TableBody>
    </Table>


  );
};
