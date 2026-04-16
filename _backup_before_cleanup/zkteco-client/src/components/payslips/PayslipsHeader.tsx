import { Button } from '@/components/ui/button';
import { Plus } from 'lucide-react';

interface PayslipsHeaderProps {
  onGenerateClick?: () => void;
  showGenerateButton?: boolean;
}

export function PayslipsHeader({ onGenerateClick, showGenerateButton = false }: PayslipsHeaderProps) {
  return (
    <div className="flex items-center justify-between">
      <div>
        <h1 className="text-3xl font-bold">My Payslips</h1>
        <p className="text-muted-foreground">View your salary payslips and payment history</p>
      </div>
      {showGenerateButton && (
        <Button onClick={onGenerateClick}>
          <Plus className="w-4 h-4 mr-2" />
          Generate Payslip
        </Button>
      )}
    </div>
  );
}
