// ==========================================
// src/components/employees/EmployeeInfoTable.tsx
// ==========================================
import { Employee } from "@/types/employee";
import { PaginationTable } from "../PaginationTable";
import { ColumnDef } from "@tanstack/react-table";
import { format } from "date-fns";
import { EmployeeActions } from "./EmployeeActions";
import { EmployeeStatusBadge } from "./EmployeeStatusBadge";
import { DeleteEmployeeDialog } from "./dialogs/DeleteEmployeeDialog";
import { SortingHeader } from "../SortingHeader";
import { useEmployeeContext } from "@/contexts/EmployeeContext";
import { EmploymentTypes } from "@/constants";
import { Button } from "../ui/button";

export const EmployeeTable = () => {
  const {
    employees,
    isLoading,
    isDeletePending,
    deleteDialogOpen,
    employeeToDelete,
    queryParams,
    setQueryParams,
    handleConfirmDelete,
    setDeleteDialogOpen,
  } = useEmployeeContext();

  const columns: ColumnDef<Employee>[] = [
    {
      accessorKey: "employeeCode",
      header: ({ column }) => <SortingHeader column={column} title="Employee Code" />,
      cell: ({ row }) => (
        <span className="font-medium text-center block">{row.getValue("employeeCode")}</span>
      ),
      enableSorting: true,
    },
    {
      accessorKey: "fullName",
      header: ({ column }) => <SortingHeader column={column} title="Full Name" />,
      enableSorting: true,
    },
    {
      accessorKey: "department",
      header: "Department",
      cell: ({ row }) => row.getValue("department") || "-",
    },
    {
      accessorKey: "employmentType",
      header: "Employment Type",
      cell: ({ row }) => (
        <Button variant="default" >{EmploymentTypes[row.getValue("employmentType") as keyof typeof EmploymentTypes]}</Button>
      ),
    },
    {
      accessorKey: "workStatus",
      header: ({ column }) => <SortingHeader column={column} title="Work Status" />,
      cell: ({ row }) => (
        <EmployeeStatusBadge status={row.getValue("workStatus")} />
      ),
      enableSorting: true,
    },
    {
      accessorKey: "companyEmail",
      header: "Company Email",
      cell: ({ row }) => row.getValue("companyEmail") || "-",
    },
    {
      accessorKey: "joinDate",
      header: ({ column }) => <SortingHeader column={column} title="Join Date" />,
      cell: ({ row }) => {
        const joinDate = row.getValue("joinDate") as string | undefined;
        return joinDate ? format(new Date(joinDate), "MMM dd, yyyy") : "-";
      },
      enableSorting: true,
    },
    {
      id: "actions",
      header: "Actions",
      cell: ({ row }) => (
        <EmployeeActions
          employee={row.original}
        />
      ),
      enableSorting: false,
    },
  ];

  const handlePaginationChange = (pageNumber: number, pageSize: number) => {
    setQueryParams({
      ...queryParams,
      pageNumber,
      pageSize,
    });
  };

  if (!employees) {
    return null;
  }

  return (
    <>
      <PaginationTable<Employee>
        columns={columns}
        data={employees.items || []}
        paginationRequest={{
          pageNumber: queryParams.pageNumber || 1,
          pageSize: queryParams.pageSize || 10,
          sortBy: undefined,
          sortOrder: "asc",
        }}
        totalCount={employees.totalCount || 0}
        pageNumber={employees.pageNumber || 1}
        pageSize={employees.pageSize || 10}
        isLoading={isLoading}
        onPaginationChange={handlePaginationChange}
        manualSorting={true}
        manualFiltering={true}
        emptyMessage="No employees found"
        containerHeight="calc(100vh - 320px)"
      />

      <DeleteEmployeeDialog
        open={deleteDialogOpen}
        employee={employeeToDelete}
        isDeleting={isDeletePending}
        onOpenChange={setDeleteDialogOpen}
        onConfirm={handleConfirmDelete}
      />
      {/* <DeviceUserRequestDialog/> */}
    </>
  );
};
