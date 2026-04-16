// ==========================================
// src/components/employeeInfo/EmployeeFilterBar.tsx
// ==========================================
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Search, X } from "lucide-react";
import { useState } from "react";
import { useEmployeeContext } from "@/contexts/EmployeeContext";

export const EmployeeFilterBar = () => {
  const { queryParams, setQueryParams } = useEmployeeContext();
  const [searchTerm, setSearchTerm] = useState(queryParams.searchTerm || "");

  const handleSearch = () => {
    setQueryParams({
      ...queryParams,
      searchTerm,
      pageNumber: 1, // Reset to first page on search
    });
  };

  const handleClearFilters = () => {
    setSearchTerm("");
    setQueryParams({
      pageNumber: 1,
      pageSize: 10,
      searchTerm: "",
      workStatus: "",
    });
  };

  const handleKeyPress = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Enter") {
      handleSearch();
    }
  };

  return (
    <div className="flex flex-col sm:flex-row gap-4 mb-6">
      <div className="flex-1 flex gap-2">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search by code, name, or email..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            onKeyPress={handleKeyPress}
            className="pl-9"
          />
        </div>
        <Button onClick={handleSearch}>Search</Button>
      </div>

      <div className="flex gap-2">
        <Select
          value={queryParams.employmentType || "all"}
          onValueChange={(value) =>
            setQueryParams({
              ...queryParams,
              employmentType: value === "all" ? "" : value,
              pageNumber: 1,
            })
          }
        >
          <SelectTrigger className="w-[150px]">
            <SelectValue placeholder="Employment Type" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Employment Type</SelectItem>
            <SelectItem value="0">Hourly</SelectItem>
            <SelectItem value="1">Monthly</SelectItem>
          </SelectContent>
        </Select>
        <Select
          value={queryParams.workStatus || "all"}
          onValueChange={(value) =>
            setQueryParams({
              ...queryParams,
              workStatus: value === "all" ? "" : value,
              pageNumber: 1,
            })
          }
        >
          <SelectTrigger className="w-[130px]">
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="0">Active</SelectItem>
            <SelectItem value="1">Resigned</SelectItem>
          </SelectContent>
        </Select>

        <Button variant="outline" size="icon" onClick={handleClearFilters}>
          <X className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
};
