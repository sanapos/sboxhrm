import { useState } from 'react';
import { usePayslips } from '@/hooks/usePayslips';
import { useAuth } from '@/contexts/AuthContext';
import { Loader2 } from 'lucide-react';
import { Payslip } from '@/types/payslip';
import { PayslipsHeader } from '@/components/payslips/PayslipsHeader';
import { PayslipEmptyState } from '@/components/payslips/PayslipEmptyState';
import { PayslipTable } from '@/components/payslips/PayslipTable';
import { PayslipDetailsDialog } from '@/components/payslips/PayslipDetailsDialog';
import { GeneratePayslipDialog } from '@/components/payslips/GeneratePayslipDialog';

export function Payslips() {
  const { data: payslips, isLoading } = usePayslips();
  const { isManager } = useAuth();
  const [selectedPayslip, setSelectedPayslip] = useState<Payslip | null>(null);
  const [showGenerateDialog, setShowGenerateDialog] = useState(false);

  const canGeneratePayslips = isManager;

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-screen">
        <Loader2 className="w-8 h-8 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="container mx-auto py-6 space-y-6">
      <PayslipsHeader 
        showGenerateButton={canGeneratePayslips}
        onGenerateClick={() => setShowGenerateDialog(true)}
      />

      {!payslips || payslips.length === 0 ? (
        <PayslipEmptyState />
      ) : (
        <PayslipTable payslips={payslips} onViewPayslip={setSelectedPayslip} />
      )}

      <PayslipDetailsDialog
        payslip={selectedPayslip}
        open={!!selectedPayslip}
        onOpenChange={() => setSelectedPayslip(null)}
      />

      {canGeneratePayslips && (
        <GeneratePayslipDialog
          open={showGenerateDialog}
          onOpenChange={setShowGenerateDialog}
        />
      )}
    </div>
  );
}

