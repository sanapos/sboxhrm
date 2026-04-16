import { PageHeader } from "@/components/PageHeader";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Plus, DollarSign, CheckCircle, XCircle, Clock, Banknote } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { AdvanceRequestProvider, useAdvanceRequestContext } from "@/contexts/AdvanceRequestContext";
import { useEffect, useState } from "react";
import { useAuth } from "@/contexts/AuthContext";
import { 
  AdvanceRequest, 
  AdvanceRequestStatus, 
  getAdvanceStatusLabel, 
  getAdvanceStatusColor 
} from "@/types/hrm";
import { format } from "date-fns";
import { vi } from "date-fns/locale";

const formatCurrency = (amount: number) => {
  return new Intl.NumberFormat('vi-VN', { 
    style: 'currency', 
    currency: 'VND' 
  }).format(amount);
};

const AdvanceRequestsHeader = () => {
  const { setDialogMode } = useAdvanceRequestContext();

  return (
    <PageHeader
      title="Quản lý ứng lương"
      description="Xem và quản lý yêu cầu ứng lương"
      action={
        <Button onClick={() => setDialogMode('create')}>
          <Plus className="mr-2 h-4 w-4" />
          Yêu cầu ứng lương
        </Button>
      }
    />
  );
};

const AdvanceRequestsSummary = () => {
  const { paginatedRequests, paginatedPendingRequests } = useAdvanceRequestContext();

  const totalRequests = paginatedRequests?.totalCount || 0;
  const pendingRequests = paginatedPendingRequests?.totalCount || 0;
  const approvedRequests = paginatedRequests?.items?.filter(
    r => r.status === AdvanceRequestStatus.APPROVED
  ).length || 0;
  const totalAmount = paginatedRequests?.items?.reduce(
    (sum, r) => sum + (r.status === AdvanceRequestStatus.APPROVED ? r.amount : 0), 0
  ) || 0;

  return (
    <div className="grid gap-4 md:grid-cols-4 mb-6">
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Tổng yêu cầu</CardTitle>
          <DollarSign className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold">{totalRequests}</div>
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Chờ duyệt</CardTitle>
          <Clock className="h-4 w-4 text-yellow-500" />
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold text-yellow-600">{pendingRequests}</div>
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Đã duyệt</CardTitle>
          <CheckCircle className="h-4 w-4 text-green-500" />
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold text-green-600">{approvedRequests}</div>
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Tổng tiền duyệt</CardTitle>
          <Banknote className="h-4 w-4 text-blue-500" />
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold text-blue-600">{formatCurrency(totalAmount)}</div>
        </CardContent>
      </Card>
    </div>
  );
};

interface AdvanceRequestsTableProps {
  requests: AdvanceRequest[];
  isLoading: boolean;
  showActions: boolean;
}

const AdvanceRequestsTable = ({ requests, isLoading, showActions }: AdvanceRequestsTableProps) => {
  const { handleApproveClick, handleRejectClick, handleMarkAsPaid, handleCancel } = useAdvanceRequestContext();
  const { isManager } = useAuth();

  if (isLoading) {
    return <div className="text-center py-4">Đang tải...</div>;
  }

  if (!requests || requests.length === 0) {
    return <div className="text-center py-4 text-muted-foreground">Không có yêu cầu nào</div>;
  }

  return (
    <div className="rounded-md border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Nhân viên</TableHead>
            <TableHead>Số tiền</TableHead>
            <TableHead>Tháng/Năm</TableHead>
            <TableHead>Ngày yêu cầu</TableHead>
            <TableHead>Lý do</TableHead>
            <TableHead>Trạng thái</TableHead>
            <TableHead>Thanh toán</TableHead>
            {showActions && <TableHead className="text-right">Thao tác</TableHead>}
          </TableRow>
        </TableHeader>
        <TableBody>
          {requests.map((request) => (
            <TableRow key={request.id}>
              <TableCell>
                <div className="font-medium">{request.employeeName}</div>
                <div className="text-sm text-muted-foreground">{request.employeeCode}</div>
              </TableCell>
              <TableCell className="font-medium">{formatCurrency(request.amount)}</TableCell>
              <TableCell>{request.month}/{request.year}</TableCell>
              <TableCell>{format(new Date(request.requestDate), 'dd/MM/yyyy', { locale: vi })}</TableCell>
              <TableCell className="max-w-[200px] truncate">{request.reason || '-'}</TableCell>
              <TableCell>
                <Badge className={getAdvanceStatusColor(request.status)}>
                  {getAdvanceStatusLabel(request.status)}
                </Badge>
              </TableCell>
              <TableCell>
                {request.isPaid ? (
                  <Badge className="bg-green-100 text-green-800">Đã thanh toán</Badge>
                ) : (
                  <Badge className="bg-gray-100 text-gray-800">Chưa thanh toán</Badge>
                )}
              </TableCell>
              {showActions && (
                <TableCell className="text-right">
                  <div className="flex justify-end gap-2">
                    {request.status === AdvanceRequestStatus.PENDING && isManager && (
                      <>
                        <Button size="sm" variant="outline" onClick={() => handleApproveClick(request)}>
                          <CheckCircle className="h-4 w-4 mr-1" />
                          Duyệt
                        </Button>
                        <Button size="sm" variant="outline" className="text-red-600" onClick={() => handleRejectClick(request)}>
                          <XCircle className="h-4 w-4 mr-1" />
                          Từ chối
                        </Button>
                      </>
                    )}
                    {request.status === AdvanceRequestStatus.APPROVED && !request.isPaid && isManager && (
                      <Button size="sm" variant="outline" onClick={() => handleMarkAsPaid(request.id)}>
                        <Banknote className="h-4 w-4 mr-1" />
                        Thanh toán
                      </Button>
                    )}
                    {request.status === AdvanceRequestStatus.PENDING && (
                      <Button size="sm" variant="destructive" onClick={() => handleCancel(request.id)}>
                        Hủy
                      </Button>
                    )}
                  </div>
                </TableCell>
              )}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
};

const AdvanceRequestsTabs = () => {
  const { paginatedRequests, paginatedPendingRequests, isLoading } = useAdvanceRequestContext();
  const { isManager } = useAuth();
  const [activeTab, setActiveTab] = useState<string>("all");

  useEffect(() => {
    if (paginatedPendingRequests && paginatedPendingRequests.items.length > 0 && isManager) {
      setActiveTab("pending");
    }
  }, [paginatedPendingRequests, isManager]);

  return (
    <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
      <TabsList>
        {isManager && (
          <TabsTrigger value="pending">
            Chờ duyệt
            {paginatedPendingRequests && paginatedPendingRequests.items.length > 0 && (
              <Badge className="ml-2 bg-yellow-500 text-white">
                {paginatedPendingRequests.items.length}
              </Badge>
            )}
          </TabsTrigger>
        )}
        <TabsTrigger value="all">Tất cả</TabsTrigger>
      </TabsList>

      {isManager && (
        <TabsContent value="pending" className="mt-6">
          <AdvanceRequestsTable
            requests={paginatedPendingRequests?.items || []}
            isLoading={isLoading}
            showActions={true}
          />
        </TabsContent>
      )}

      <TabsContent value="all" className="mt-6">
        <AdvanceRequestsTable
          requests={paginatedRequests?.items || []}
          isLoading={isLoading}
          showActions={true}
        />
      </TabsContent>
    </Tabs>
  );
};

const CreateAdvanceRequestDialog = () => {
  const { dialogMode, setDialogMode, handleCreate } = useAdvanceRequestContext();
  const [amount, setAmount] = useState<string>('');
  const [reason, setReason] = useState<string>('');
  const [month, setMonth] = useState<number>(new Date().getMonth() + 1);
  const [year, setYear] = useState<number>(new Date().getFullYear());

  const isOpen = dialogMode === 'create';

  const handleSubmit = async () => {
    if (!amount || parseFloat(amount) <= 0) return;
    await handleCreate({
      amount: parseFloat(amount),
      reason,
      month,
      year,
    });
    setAmount('');
    setReason('');
  };

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && setDialogMode(null)}>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>Yêu cầu ứng lương</DialogTitle>
          <DialogDescription>Nhập thông tin yêu cầu ứng lương của bạn</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4 py-4">
          <div className="grid gap-2">
            <Label htmlFor="amount">Số tiền (VNĐ)</Label>
            <Input
              id="amount"
              type="number"
              placeholder="Nhập số tiền"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div className="grid gap-2">
              <Label htmlFor="month">Tháng</Label>
              <Input
                id="month"
                type="number"
                min={1}
                max={12}
                value={month}
                onChange={(e) => setMonth(parseInt(e.target.value))}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="year">Năm</Label>
              <Input
                id="year"
                type="number"
                min={2020}
                max={2030}
                value={year}
                onChange={(e) => setYear(parseInt(e.target.value))}
              />
            </div>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="reason">Lý do</Label>
            <Textarea
              id="reason"
              placeholder="Nhập lý do ứng lương"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setDialogMode(null)}>Hủy</Button>
          <Button onClick={handleSubmit}>Gửi yêu cầu</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

const ApproveRejectDialogs = () => {
  const { 
    dialogMode, 
    setDialogMode, 
    selectedRequest, 
    handleApprove, 
    handleReject, 
    rejectReason, 
    setRejectReason 
  } = useAdvanceRequestContext();

  return (
    <>
      {/* Approve Dialog */}
      <AlertDialog open={dialogMode === 'approve'} onOpenChange={(open) => !open && setDialogMode(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Xác nhận duyệt yêu cầu</AlertDialogTitle>
            <AlertDialogDescription>
              Bạn có chắc chắn muốn duyệt yêu cầu ứng lương {formatCurrency(selectedRequest?.amount || 0)} của {selectedRequest?.employeeName}?
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Hủy</AlertDialogCancel>
            <AlertDialogAction onClick={() => selectedRequest && handleApprove(selectedRequest.id)}>
              Duyệt
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Reject Dialog */}
      <Dialog open={dialogMode === 'reject'} onOpenChange={(open) => !open && setDialogMode(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Từ chối yêu cầu</DialogTitle>
            <DialogDescription>
              Vui lòng nhập lý do từ chối yêu cầu ứng lương của {selectedRequest?.employeeName}
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid gap-2">
              <Label htmlFor="rejectReason">Lý do từ chối</Label>
              <Textarea
                id="rejectReason"
                placeholder="Nhập lý do từ chối"
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogMode(null)}>Hủy</Button>
            <Button 
              variant="destructive" 
              onClick={() => selectedRequest && handleReject(selectedRequest.id, rejectReason)}
            >
              Từ chối
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
};

const AdvanceRequestsContent = () => {
  return (
    <div className="container mx-auto py-6">
      <AdvanceRequestsHeader />
      <div className="mt-6">
        <AdvanceRequestsSummary />
        <AdvanceRequestsTabs />
      </div>
      <CreateAdvanceRequestDialog />
      <ApproveRejectDialogs />
    </div>
  );
};

const AdvanceRequests = () => {
  return (
    <AdvanceRequestProvider>
      <AdvanceRequestsContent />
    </AdvanceRequestProvider>
  );
};

export default AdvanceRequests;
