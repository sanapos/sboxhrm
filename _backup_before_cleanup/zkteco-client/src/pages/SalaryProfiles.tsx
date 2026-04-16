import { useState } from "react";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { SalaryProfileTable } from "@/components/benefit/dialogs/BenefitsTable";
import { EmployeeSalaryProfileTable } from "@/components/benefit/employees-benefit/EmployeeBenefitsTable";
import { CreateSalaryProfileDialog } from "@/components/benefit/dialogs/CreateBenefitDialog";
import { EditSalaryProfileDialog } from "@/components/benefit/dialogs/EditBenefitDialog";
import { AssignSalaryToEmployeeDialog } from "@/components/benefit/employees-benefit/AssignSalaryToEmployeeDialog";
import { SalaryProfileProvider, useSalaryProfileContext } from "@/contexts/BenefitContext";

const BenefitsContent = () => {
  const {
    benefits: profiles,
    showActiveOnly,
    setShowActiveOnly,
    handleOpenCreateDialog,
  } = useSalaryProfileContext();

  const [activeTab, setActiveTab] = useState("profiles");

  return (
    <div className="space-y-6">
      <PageHeader
        title="Benefit Profiles"
        action={
          activeTab === "profiles" && (
            <Button onClick={handleOpenCreateDialog}>
              <Plus className="w-4 h-4 mr-2" />
              Create Benefit Profile
            </Button>
          )
        }
      />

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="profiles">Benefits</TabsTrigger>
          <TabsTrigger value="assignments">Employee Benefits</TabsTrigger>
        </TabsList>

        <TabsContent value="profiles" className="mt-6">
          <Card className="p-4">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center space-x-2">
                <input
                  type="checkbox"
                  checked={showActiveOnly}
                  onChange={(e) => setShowActiveOnly(e.target.checked)}
                  id="active-only"
                  className="h-4 w-4"
                />
                <Label htmlFor="active-only">Show active only</Label>
              </div>
              <Badge variant="outline" className="text-sm">
                {profiles?.length || 0} profile{profiles?.length !== 1 ? 's' : ''}
              </Badge>
            </div>

            <SalaryProfileTable />
          </Card>
        </TabsContent>

        <TabsContent value="assignments" className="mt-6">
          <Card className="p-4">
            <EmployeeSalaryProfileTable />
          </Card>
        </TabsContent>
      </Tabs>

      <CreateSalaryProfileDialog />
      <EditSalaryProfileDialog />
      <AssignSalaryToEmployeeDialog />
    </div>
  );
};

export const Benefits = () => {
  return (
    <SalaryProfileProvider>
      <BenefitsContent />
    </SalaryProfileProvider>
  );
};
