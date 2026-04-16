import { useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useShiftTemplates } from '@/hooks/useShiftTemplate';
import { Calendar } from '@/components/ui/calendar';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { cn } from '@/lib/utils';
import { format } from 'date-fns';
import { CalendarIcon, Clock } from 'lucide-react';
import { DateTimeFormat } from '@/constants';
import { CreateShiftRequest } from '@/types/shift';
import { useShiftContext } from '@/contexts/ShiftContext';

interface ShiftDialogState {
    templateId: string;
    dates: Date[];
    description: string;
}

const defaultDialogState: ShiftDialogState = {
    templateId: '',
    dates: [],
    description: '',
};

const getDateString = (time: string, dateStr: Date) => {
    const [hours, minutes] = time.split(':');
    const date = new Date(dateStr);
    date.setHours(parseInt(hours), parseInt(minutes), 0, 0);
    return format(date, DateTimeFormat);
};

export const ShiftRequestDialog = () => {
    const [dialogState, setDialogState] = useState<ShiftDialogState>({ ...defaultDialogState });
    const [isSubmitting, setIsSubmitting] = useState(false);
    
    const {
        dialogMode,
        setDialogMode,
        handleCreate,
    } = useShiftContext();

    const { data: templates = [], isLoading: templatesLoading } = useShiftTemplates();
    const hasTemplates = templates.length > 0;

    const { templateId, dates, description } = dialogState;

    // Get selected template
    const selectedTemplate = templates.find(t => t.id === templateId);

    // Handler to close dialog
    const handleClose = () => {
        setDialogMode(null);
        setDialogState({ ...defaultDialogState });
    };

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setIsSubmitting(true);

        
        // Create mode - use template and create shifts for each selected date
        if (!templateId || !dates.length || !selectedTemplate) return;

        // Create a shift for each selected date
        const workingDays = dates.map(date => ({
            startTime: getDateString(selectedTemplate.startTime, date),
            endTime: getDateString(selectedTemplate.endTime, date),
        }));

        const createData: CreateShiftRequest = {
            workingDays,
            maximumAllowedLateMinutes: selectedTemplate.maximumAllowedLateMinutes,
            maximumAllowedEarlyLeaveMinutes: selectedTemplate.maximumAllowedEarlyLeaveMinutes,
            breakTimeMinutes: selectedTemplate.breakTimeMinutes,
            description: description,
        };
        await handleCreate(createData);
        
        handleClose();
    };

    const updateDialogState = (updates: Partial<ShiftDialogState>) => {
        setDialogState((prev) => ({ ...prev, ...updates }));
    };

    return (
        <Dialog open={dialogMode !== null} onOpenChange={handleClose}>
            <DialogContent className="sm:max-w-[500px] max-h-[90vh] overflow-y-auto">
                <DialogHeader>
                    <DialogTitle className="flex items-center gap-2 text-xl">
                        <Clock className="h-5 w-5" />
                        Request New Shift
                    </DialogTitle>
                    <DialogDescription>
                        Submit a shift request using a template.
                    </DialogDescription>
                </DialogHeader>

                <form onSubmit={e => {
                    handleSubmit(e);
                    setIsSubmitting(false);
                }} className="space-y-6 mt-4">
                    {/* Template Selection */}
                            <div className="space-y-2">
                                <Label htmlFor="template">Select Shift Template</Label>
                                {templatesLoading ? (
                                    <div className="text-sm text-muted-foreground">Loading templates...</div>
                                ) : !hasTemplates ? (
                                    <div className="text-sm text-muted-foreground">
                                        No templates available. Please contact your manager to create templates.
                                    </div>
                                ) : (
                                    <Select
                                        value={templateId}
                                        onValueChange={(value) => updateDialogState({ templateId: value })}
                                    >
                                        <SelectTrigger>
                                            <SelectValue placeholder="Choose a template..." />
                                        </SelectTrigger>
                                        <SelectContent>
                                            {templates.map((template) => (
                                                <SelectItem key={template.id} value={template.id}>
                                                    {template.name} ({template.startTime.substring(0, 5)} - {template.endTime.substring(0, 5)})
                                                </SelectItem>
                                            ))}
                                        </SelectContent>
                                    </Select>
                                )}
                            </div>

                            {/* Date Selection */}
                            <div className="space-y-2">
                                <Label htmlFor="dates">Shift Dates</Label>
                                <Popover>
                                    <PopoverTrigger asChild>
                                        <Button
                                            variant="outline"
                                            className={cn(
                                                "w-full justify-start text-left font-normal",
                                                !dates?.length && "text-muted-foreground"
                                            )}
                                        >
                                            <CalendarIcon className="mr-2 h-4 w-4" />
                                            {dates && dates.length > 0 ? (
                                                `${dates.length} date${dates.length > 1 ? 's' : ''} selected`
                                            ) : (
                                                <span>Pick dates</span>
                                            )}
                                        </Button>
                                    </PopoverTrigger>
                                    <PopoverContent className="w-auto p-0">
                                        <Calendar
                                            mode="multiple"
                                            style={{ minWidth: "250px" }}
                                            selected={dates}
                                            onSelect={(selectedDates) => updateDialogState({ dates: selectedDates || [] })}
                                            disabled={(dateToCheck) => dateToCheck < new Date(new Date().setHours(0, 0, 0, 0))}
                                            initialFocus
                                        />
                                    </PopoverContent>
                                </Popover>
                            </div>

                            {/* Template Details Display */}
                            {selectedTemplate && (
                                <div className="rounded-lg border p-4 space-y-2 bg-muted/50">
                                    <div className="font-medium text-sm">Template Details</div>
                                    <div className="grid grid-cols-2 gap-2 text-sm">
                                        <div>
                                            <span className="text-muted-foreground">Start:</span>{' '}
                                            {selectedTemplate.startTime.substring(0, 5)}
                                        </div>
                                        <div>
                                            <span className="text-muted-foreground">End:</span>{' '}
                                            {selectedTemplate.endTime.substring(0, 5)}
                                        </div>
                                        <div>
                                            <span className="text-muted-foreground">Max Late:</span>{' '}
                                            {selectedTemplate.maximumAllowedLateMinutes} min
                                        </div>
                                        <div>
                                            <span className="text-muted-foreground">Max Early:</span>{' '}
                                            {selectedTemplate.maximumAllowedEarlyLeaveMinutes} min
                                        </div>
                                        <div className="col-span-2">
                                            <span className="text-muted-foreground">Total Hours:</span>{' '}
                                            {selectedTemplate.totalHours}h
                                        </div>
                                    </div>
                                </div>
                            )}

                            {/* Selected Dates Display */}
                            {dates.length > 0 && (
                                <div className="rounded-lg border p-4 space-y-2 bg-muted/50">
                                    <div className="font-medium text-sm">
                                        Selected Dates ({dates.length} {dates.length === 1 ? 'day' : 'days'})
                                    </div>
                                    <div className="max-h-40 overflow-y-auto space-y-1">
                                        {dates
                                            .sort((a, b) => a.getTime() - b.getTime())
                                            .map((date, index) => (
                                                <div key={index} className="text-sm flex items-center gap-2">
                                                    <CalendarIcon className="h-3 w-3 text-muted-foreground" />
                                                    <span>{format(date, 'EEEE, MMMM d, yyyy')}</span>
                                                    {selectedTemplate && (
                                                        <span className="text-muted-foreground text-xs ml-auto">
                                                            {selectedTemplate.startTime.substring(0, 5)} - {selectedTemplate.endTime.substring(0, 5)}
                                                        </span>
                                                    )}
                                                </div>
                                            ))}
                                    </div>
                                    {selectedTemplate && (
                                        <div className="pt-2 border-t text-sm">
                                            <span className="text-muted-foreground">Total Hours:</span>{' '}
                                            <span className="font-medium">{(dates.length * selectedTemplate.totalHours).toFixed(1)}h</span>
                                        </div>
                                    )}
                                </div>
                            )}


                    {/* Description */}
                    <div className="space-y-2">
                        <Label htmlFor="description">Description (Optional)</Label>
                        <Textarea
                            id="description"
                            value={description}
                            onChange={(e) => updateDialogState({ description: e.target.value })}
                            placeholder="Add any notes about this shift..."
                            rows={3}
                            className="resize-none"
                        />
                    </div>

                    <DialogFooter className="gap-3 pt-4">
                        <Button type="button" variant="outline" onClick={handleClose} className="min-w-[100px]">
                            Cancel
                        </Button>
                        <Button 
                            type="submit" 
                            disabled={
                                isSubmitting || 
                                (!templateId || !dates.length || !hasTemplates)
                            }
                            className="min-w-[140px]"
                        >
                            {isSubmitting ? 'Submitting...' : dates.length > 1 ? `Submit ${dates.length} Requests` : 'Submit Request'}
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    );
};
