import { ShiftStatus } from '@/types/shift';
import { Badge } from '@/components/ui/badge';
import {
    Tooltip,
    TooltipContent,
    TooltipProvider,
    TooltipTrigger,
} from '@/components/ui/tooltip';
import { AlertCircle } from 'lucide-react';

interface StatusBadgeProps {
    status: ShiftStatus;
    rejectionReason?: string;
}

export const StatusBadge = ({ status, rejectionReason }: StatusBadgeProps) => {
    const getBadgeContent = () => {
        switch (status) {
            case ShiftStatus.Pending:
                return <Badge variant="outline" className="bg-yellow-50 text-yellow-700 border-yellow-200">Pending</Badge>;
            case ShiftStatus.Approved:
                return <Badge variant="outline" className="bg-green-50 text-green-700 border-green-200">Approved</Badge>;
            case ShiftStatus.Rejected:
                return <Badge variant="outline" className="bg-red-50 text-red-700 border-red-200">Rejected</Badge>;
            case ShiftStatus.Cancelled:
                return <Badge variant="outline" className="bg-gray-50 text-gray-700 border-gray-200">Cancelled</Badge>;
            case ShiftStatus.ApprovedLeave:
                return <Badge variant="outline" className="bg-blue-50 text-green-700 border-red-200">Approved Leave</Badge>;
            default:
                return <Badge variant="outline">Unknown</Badge>;
        }
    };

    if (status === ShiftStatus.Rejected && rejectionReason) {
        return (
            <div className="flex items-center gap-2">
                {getBadgeContent()}
                <TooltipProvider>
                    <Tooltip>
                        <TooltipTrigger asChild>
                            <AlertCircle className="w-4 h-4 text-red-600 cursor-help" />
                        </TooltipTrigger>
                        <TooltipContent>
                            <p className="max-w-xs">{rejectionReason}</p>
                        </TooltipContent>
                    </Tooltip>
                </TooltipProvider>
            </div>
        );
    }

    return getBadgeContent();
};
