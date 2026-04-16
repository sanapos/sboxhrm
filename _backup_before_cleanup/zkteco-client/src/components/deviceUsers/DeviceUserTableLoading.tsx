import { TableCell, TableRow } from "@/components/ui/table";
import { LoadingSpinner } from "../LoadingSpinner";

export const DeviceUserTableLoading = () => {
  return (
    <TableRow>
      <TableCell colSpan={9} className="h-48">
        <div className="flex items-center justify-center">
          <div className="flex flex-col items-center gap-2">
            <span className="text-muted-foreground">
              <LoadingSpinner />
            </span>
          </div>
        </div>
      </TableCell>
    </TableRow>
  );
};
