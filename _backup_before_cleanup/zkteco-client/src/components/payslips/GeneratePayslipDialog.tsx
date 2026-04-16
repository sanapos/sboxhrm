import { useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { useGeneratePayslip } from '@/hooks/usePayslips';
import { Loader2 } from 'lucide-react';
import { useEmployeesByManager } from '@/hooks/useAccount';

interface GeneratePayslipDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function GeneratePayslipDialog({ open, onOpenChange }: GeneratePayslipDialogProps) {
  const currentDate = new Date();
  const [employeeUserId, setEmployeeUserId] = useState('');
  const [year, setYear] = useState(currentDate.getFullYear());
  const [month, setMonth] = useState(currentDate.getMonth() + 1);
  const [bonus, setBonus] = useState<number | undefined>();
  const [deductions, setDeductions] = useState<number | undefined>();
  const [notes, setNotes] = useState('');

  const { data: employees = [], isLoading: isLoadingEmployees } = useEmployeesByManager();
  const generateMutation = useGeneratePayslip();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!employeeUserId) {
      return;
    }

    await generateMutation.mutateAsync({
      employeeUserId,
      year,
      month,
      bonus: bonus && bonus > 0 ? bonus : undefined,
      deductions: deductions && deductions > 0 ? deductions : undefined,
      notes: notes.trim() || undefined,
    });

    // Reset form
    setEmployeeUserId('');
    setBonus(undefined);
    setDeductions(undefined);
    setNotes('');
    onOpenChange(false);
  };

  // Filter employees who have applicationUser (linked to an account)
  const employeesWithAccounts = employees.filter(emp => emp);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Generate Payslip</DialogTitle>
          <DialogDescription>
            Generate a payslip for an employee for the current month
          </DialogDescription>
        </DialogHeader>
        
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="employee">Employee *</Label>
            <Select value={employeeUserId} onValueChange={setEmployeeUserId} required disabled={isLoadingEmployees}>
              <SelectTrigger id="employee">
                <SelectValue placeholder={isLoadingEmployees ? "Loading employees..." : "Select an employee"} />
              </SelectTrigger>
              <SelectContent>
                {employeesWithAccounts.map((employee) => (
                  <SelectItem key={employee.id} value={employee!.id}>
                    {employee.fullName}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="year">Year</Label>
              <Input
                id="year"
                type="number"
                value={year}
                onChange={(e) => setYear(parseInt(e.target.value))}
                min={2020}
                max={2100}
                required
                disabled
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="month">Month</Label>
              <Select value={month.toString()} onValueChange={(value) => setMonth(parseInt(value))} disabled>
                <SelectTrigger id="month">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => (
                    <SelectItem key={m} value={m.toString()}>
                      {new Date(2024, m - 1, 1).toLocaleString('default', { month: 'long' })}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="bonus">Bonus</Label>
              <Input
                id="bonus"
                type="number"
                step="0.01"
                min="0"
                value={bonus || ''}
                onChange={(e) => setBonus(e.target.value ? parseFloat(e.target.value) : undefined)}
                placeholder="0.00"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="deductions">Deductions</Label>
              <Input
                id="deductions"
                type="number"
                step="0.01"
                min="0"
                value={deductions || ''}
                onChange={(e) => setDeductions(e.target.value ? parseFloat(e.target.value) : undefined)}
                placeholder="0.00"
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="notes">Notes</Label>
            <Textarea
              id="notes"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Additional notes (optional)"
              rows={3}
            />
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={generateMutation.isPending || !employeeUserId}>
              {generateMutation.isPending && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
              Generate Payslip
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
