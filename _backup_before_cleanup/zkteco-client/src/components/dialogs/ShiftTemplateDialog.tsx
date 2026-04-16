import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useShiftManagementContext } from '@/contexts/ShiftManagementContext';
import { defaultNewShiftTemplate } from '@/constants/defaultValue';
import { Clock } from 'lucide-react';

const extractTime = (timeString: string): string => {
    if (!timeString) return '09:00';
    // TimeSpan comes as "HH:mm:ss" format, extract HH:mm for the time input
    if (timeString.includes(':')) {
        const parts = timeString.split(':');
        return `${parts[0]}:${parts[1]}`;
    }
    // Fallback for ISO datetime format
    const date = new Date(timeString);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
};

export const ShiftTemplateDialog = () => {
    const {
        createTemplateDialogOpen,
        setCreateTemplateDialogOpen,
        updateTemplateDialogOpen,
        setUpdateTemplateDialogOpen,
        selectedTemplate,
        handleCreateTemplate,
        handleUpdateTemplate,
    } = useShiftManagementContext();

    const isEditMode = updateTemplateDialogOpen;
    const isOpen = createTemplateDialogOpen || updateTemplateDialogOpen;

    const [formData, setFormData] = useState({
        name: '',
        startTime: '09:00',
        endTime: '17:00',
        maximumAllowedLateMinutes: 30,
        maximumAllowedEarlyLeaveMinutes: 30,
        breakTimeMinutes: 60,
        isActive: true,
    });

    useEffect(() => {
        if (isEditMode && selectedTemplate) {
            setFormData({
                name: selectedTemplate.name,
                startTime: extractTime(selectedTemplate.startTime),
                endTime: extractTime(selectedTemplate.endTime),
                maximumAllowedLateMinutes: selectedTemplate.maximumAllowedLateMinutes ?? 30,
                maximumAllowedEarlyLeaveMinutes: selectedTemplate.maximumAllowedEarlyLeaveMinutes ?? 30,
                breakTimeMinutes: selectedTemplate.breakTimeMinutes ?? 60,
                isActive: selectedTemplate.isActive,
            });
        } else if (!isEditMode) {
            // Reset to default for create mode
            setFormData({
                name: defaultNewShiftTemplate.name || '',
                startTime: defaultNewShiftTemplate.startTime || '09:00',
                endTime: defaultNewShiftTemplate.endTime || '17:00',
                maximumAllowedLateMinutes: defaultNewShiftTemplate.maximumAllowedLateMinutes ?? 30,
                maximumAllowedEarlyLeaveMinutes: defaultNewShiftTemplate.maximumAllowedEarlyLeaveMinutes ?? 30,
                breakTimeMinutes: 60,
                isActive: true,
            });
        }
    }, [isEditMode, selectedTemplate, isOpen]);

    const handleClose = () => {
        if (isEditMode) {
            setUpdateTemplateDialogOpen(false);
        } else {
            setCreateTemplateDialogOpen(false);
        }
    };

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        
        if (!formData.name || !formData.startTime || !formData.endTime) {
            return;
        }

        // Convert HH:mm to HH:mm:ss format for TimeSpan if needed, or just pass as is if backend handles it.
        // Based on previous files, it seems we might need to ensure format.
        // CreateShiftTemplateDialog used: time.split(':').length === 2 ? `${time}:00` : time
        // UpdateShiftTemplateDialog used: `${formData.startTime}:00`
        
        const formatTime = (t: string) => t.split(':').length === 2 ? `${t}:00` : t;
        const startTime = formatTime(formData.startTime);
        const endTime = formatTime(formData.endTime);

        if (isEditMode && selectedTemplate) {
            await handleUpdateTemplate(selectedTemplate.id, {
                name: formData.name,
                startTime,
                endTime,
                maximumAllowedLateMinutes: formData.maximumAllowedLateMinutes,
                maximumAllowedEarlyLeaveMinutes: formData.maximumAllowedEarlyLeaveMinutes,
                breakTimeMinutes: formData.breakTimeMinutes,
                isActive: formData.isActive,
            });
        } else {
            await handleCreateTemplate({
                name: formData.name,
                startTime,
                endTime,
                maximumAllowedLateMinutes: formData.maximumAllowedLateMinutes,
                maximumAllowedEarlyLeaveMinutes: formData.maximumAllowedEarlyLeaveMinutes,
                breakTimeMinutes: formData.breakTimeMinutes,
            });
        }
        // Context handles closing? 
        // CreateShiftTemplateDialog: await handleCreateTemplate(template); setTemplate(default);
        // UpdateShiftTemplateDialog: handleUpdateTemplate(...);
        // The context methods might not close the dialog automatically.
        // Let's assume we need to close it manually or the context does it.
        // Looking at CreateShiftTemplateDialog, it calls setTemplate(default) but doesn't explicitly close? 
        // Wait, handleOpenChangeInternal calls setCreateTemplateDialogOpen(open).
        // Let's check ShiftManagementContext implementation if possible, but I don't have the implementation of handleCreateTemplate.
        // Assuming I should close it after success.
        handleClose();
    };

    return (
        <Dialog open={isOpen} onOpenChange={(open) => !open && handleClose()}>
            <DialogContent className="max-w-[95vw] sm:max-w-[500px]">
                <form onSubmit={handleSubmit}>
                    <DialogHeader>
                        <DialogTitle className="flex items-center gap-2">
                            <Clock className="h-5 w-5" />
                            {isEditMode ? 'Update Shift Template' : 'Create Shift Template'}
                        </DialogTitle>
                        <DialogDescription>
                            {isEditMode 
                                ? 'Update the shift template details' 
                                : 'Create a reusable shift template for quick shift scheduling'}
                        </DialogDescription>
                    </DialogHeader>

                    <div className="space-y-4 py-4">
                        <div className="space-y-2">
                            <Label htmlFor="name">Template Name</Label>
                            <Input
                                id="name"
                                value={formData.name}
                                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                                placeholder="e.g., Morning Shift, Night Shift"
                                required
                            />
                        </div>

                        <div className="grid grid-cols-2 gap-4">
                            <div className="space-y-2">
                                <Label htmlFor="startTime">Start Time</Label>
                                <Input
                                    id="startTime"
                                    type="time"
                                    value={formData.startTime}
                                    onChange={(e) => setFormData({ ...formData, startTime: e.target.value })}
                                    required
                                />
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="endTime">End Time</Label>
                                <Input
                                    id="endTime"
                                    type="time"
                                    value={formData.endTime}
                                    onChange={(e) => setFormData({ ...formData, endTime: e.target.value })}
                                    required
                                />
                            </div>
                        </div>

                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                            <div className="space-y-2">
                                <Label htmlFor="maxLate">Max Late (minutes)</Label>
                                <Input
                                    id="maxLate"
                                    type="number"
                                    min="0"
                                    value={formData.maximumAllowedLateMinutes}
                                    onChange={(e) => setFormData({ ...formData, maximumAllowedLateMinutes: parseInt(e.target.value) || 0 })}
                                    placeholder="30"
                                />
                            </div>
                            <div className="space-y-2">
                                <Label htmlFor="maxEarlyLeave">Max Early Leave (minutes)</Label>
                                <Input
                                    id="maxEarlyLeave"
                                    type="number"
                                    min="0"
                                    value={formData.maximumAllowedEarlyLeaveMinutes}
                                    onChange={(e) => setFormData({ ...formData, maximumAllowedEarlyLeaveMinutes: parseInt(e.target.value) || 0 })}
                                    placeholder="30"
                                />
                            </div>
                        </div>

                        <div className="space-y-2">
                            <Label htmlFor="breakTime">Break Time (minutes)</Label>
                            <Input
                                id="breakTime"
                                type="number"
                                min="0"
                                value={formData.breakTimeMinutes}
                                onChange={(e) => setFormData({ ...formData, breakTimeMinutes: parseInt(e.target.value) || 0 })}
                                placeholder="60"
                            />
                        </div>

                        {isEditMode && (
                            <div className="space-y-2">
                                <Label htmlFor="isActive">Status</Label>
                                <Select
                                    value={formData.isActive ? "active" : "inactive"}
                                    onValueChange={(value) => setFormData({ ...formData, isActive: value === "active" })}
                                >
                                    <SelectTrigger>
                                        <SelectValue />
                                    </SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="active">Active</SelectItem>
                                        <SelectItem value="inactive">Inactive</SelectItem>
                                    </SelectContent>
                                </Select>
                            </div>
                        )}
                    </div>

                    <DialogFooter className="flex-col sm:flex-row gap-2">
                        <Button 
                            type="button" 
                            variant="outline" 
                            onClick={handleClose}
                            className="w-full sm:w-auto"
                        >
                            Cancel
                        </Button>
                        <Button type="submit" className="w-full sm:w-auto">
                            {isEditMode ? 'Update Template' : 'Create Template'}
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    );
};
