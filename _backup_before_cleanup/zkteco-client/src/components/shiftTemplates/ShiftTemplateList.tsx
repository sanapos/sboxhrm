import { ShiftTemplate } from '@/types/shift';
import {
    Table,
    TableBody,
    TableHead,
    TableHeader,
    TableRow,
} from '@/components/ui/table';
import { ShiftTemplateRow } from './ShiftTemplateRow';

interface ShiftTemplateListProps {
    templates: ShiftTemplate[];
    isLoading: boolean;
    onEdit?: (template: ShiftTemplate) => void;
    onDelete?: (id: string) => void;
}

export const ShiftTemplateList = ({
    templates,
    isLoading,
    onEdit,
    onDelete
}: ShiftTemplateListProps) => {
    if (isLoading) {
        return <div className="text-center py-8">Loading templates...</div>;
    }

    if (templates.length === 0) {
        return <div className="text-center py-8 text-muted-foreground">No templates found</div>;
    }

    return (
        <div className="rounded-md border">
            <Table>
                <TableHeader>
                    <TableRow>
                        <TableHead>Name</TableHead>
                        <TableHead>Start Time</TableHead>
                        <TableHead>End Time</TableHead>
                        <TableHead>Total Hours</TableHead>
                        <TableHead className="text-center">Max Late (min)</TableHead>
                        <TableHead className="text-center">Max Early Leave (min)</TableHead>
                        <TableHead className="text-center">Break Time (min)</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead>Created At</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                </TableHeader>
                <TableBody>
                    {templates.map((template) => (
                        <ShiftTemplateRow
                            key={template.id}
                            template={template}
                            onEdit={onEdit}
                            onDelete={onDelete}
                        />
                    ))}
                </TableBody>
            </Table>
        </div>
    );
};
