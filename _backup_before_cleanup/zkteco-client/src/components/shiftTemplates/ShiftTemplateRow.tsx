import { ShiftTemplate } from '@/types/shift';
import { TableCell, TableRow } from '@/components/ui/table';
import { formatDateTime } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Pencil, Trash2 } from 'lucide-react';
import {
    AlertDialog,
    AlertDialogAction,
    AlertDialogCancel,
    AlertDialogContent,
    AlertDialogDescription,
    AlertDialogFooter,
    AlertDialogHeader,
    AlertDialogTitle,
    AlertDialogTrigger,
} from '@/components/ui/alert-dialog';

interface ShiftTemplateRowProps {
    template: ShiftTemplate;
    onEdit?: (template: ShiftTemplate) => void;
    onDelete?: (id: string) => void;
}

export const ShiftTemplateRow = ({
    template,
    onEdit,
    onDelete
}: ShiftTemplateRowProps) => {
    return (
        <TableRow>
            <TableCell className="font-medium">{template.name}</TableCell>
            <TableCell className="whitespace-nowrap">{template.startTime}</TableCell>
            <TableCell className="whitespace-nowrap">{template.endTime}</TableCell>
            <TableCell className="whitespace-nowrap">{template.totalHours}</TableCell>
            <TableCell className="text-center">{template.maximumAllowedLateMinutes}</TableCell>
            <TableCell className="text-center">{template.maximumAllowedEarlyLeaveMinutes}</TableCell>
            <TableCell className="text-center">{template.breakTimeMinutes}</TableCell>
            <TableCell>
                <Badge variant={template.isActive ? "default" : "secondary"}>
                    {template.isActive ? "Active" : "Inactive"}
                </Badge>
            </TableCell>
            <TableCell className="text-sm text-muted-foreground whitespace-nowrap">
                {formatDateTime(template.createdAt)}
            </TableCell>
            <TableCell className="text-right">
                <div className="flex justify-end gap-2">
                    {onEdit && (
                        <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => onEdit(template)}
                        >
                            <Pencil className="h-4 w-4" />
                        </Button>
                    )}
                    {onDelete && (
                        <AlertDialog>
                            <AlertDialogTrigger asChild>
                                <Button
                                    variant="ghost"
                                    size="sm"
                                >
                                    <Trash2 className="h-4 w-4 text-destructive" />
                                </Button>
                            </AlertDialogTrigger>
                            <AlertDialogContent>
                                <AlertDialogHeader>
                                    <AlertDialogTitle>Delete Shift Template</AlertDialogTitle>
                                    <AlertDialogDescription>
                                        Are you sure you want to delete the template "{template.name}"? This action cannot be undone.
                                    </AlertDialogDescription>
                                </AlertDialogHeader>
                                <AlertDialogFooter>
                                    <AlertDialogCancel>Cancel</AlertDialogCancel>
                                    <AlertDialogAction
                                        onClick={() => onDelete(template.id)}
                                        className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
                                    >
                                        Delete
                                    </AlertDialogAction>
                                </AlertDialogFooter>
                            </AlertDialogContent>
                        </AlertDialog>
                    )}
                </div>
            </TableCell>
        </TableRow>
    );
};
