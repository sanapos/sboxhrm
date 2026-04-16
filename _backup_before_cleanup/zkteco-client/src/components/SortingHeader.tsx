import { ArrowDown, ArrowUp, ArrowUpDown } from "lucide-react";
import { Button } from "./ui/button";

export const SortingHeader = ({ column, title }: { column: any; title: string }) => {
    return (
        <Button
            variant="ghost"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
            className="hover:bg-transparent p-0"
        >
            {title}
            {column.getIsSorted() === "asc" ? (
                <ArrowUp className="ml-2 h-4 w-4" />
            ) : column.getIsSorted() === "desc" ? (
                <ArrowDown className="ml-2 h-4 w-4" />
            ) : (
                <ArrowUpDown className="ml-2 h-4 w-4" />
            )}
        </Button>
    );
};