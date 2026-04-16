import { TableHead, TableHeader, TableRow } from "@/components/ui/table";

export const DeviceUserTableHeader = () => {
  return (
    <TableHeader>
      <TableRow>
        <TableHead>Device</TableHead>
        <TableHead>Employee Name</TableHead>
        <TableHead>Employee Code</TableHead>
        <TableHead>PIN</TableHead>
        <TableHead>Device User Name</TableHead>
        <TableHead>Privilege</TableHead>
        <TableHead>Card Number</TableHead>
        <TableHead className="text-right">Actions</TableHead>
      </TableRow>
    </TableHeader>
  );
};
