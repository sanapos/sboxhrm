import { PageHeader } from "@/components/PageHeader";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Plus, CheckCircle, XCircle, Clock, Edit } from "lucide-react";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { AttendanceCorrectionProvider, useAttendanceCorrectionContext } from "@/contexts/AttendanceCorrectionContext";
import { useEffect, useState } from "react";
import { useAuth } from "@/contexts/AuthContext";
import {
  AttendanceCorrectionRequest,
  CorrectionStatus,
  CorrectionAction,
  getCorrectionStatusLabel,
  getCorrectionStatusColor,
  getCorrectionActionLabel,
} from "@/types/hrm";
import { format } from "date-fns";
import { vi } from "date-fns/locale";

const AttendanceCorrectionsHeader = () => {
  const { setDialogMode } = useAttendanceCorrectionContext();

  return (
    <PageHeader
      title="Sửa chấm công"
      description="Xem và quản lý yêu cầu sửa chấm công"
      action={
        <Button onClick={() => setDialogMode('create')}>
          <Plus className="mr-2 h-4 w-4" />
          Yêu cầu sửa chấm công
        </Button>
      }
    />
  );
};

const AttendanceCorrectionsSummary = () => {
  const { paginatedRequests, paginatedPendingRequests } = useAttendanceCorrectionContext();

  const totalRequests = paginatedRequests?.totalCount || 0;
  const pendingRequests = paginatedPendingRequests?.totalCount || 0;
  const approvedRequests = paginatedRequests?.items?.filter(
    r => r.status === CorrectionStatus.APPROVED
  ).length || 0;
  const rejectedRequests = paginatedRequests?.items?.filter(
    r => r.status === CorrectionStatus.REJECTED
  ).length || 0;

  return (
    <div className="grid gap-4 md:grid-cols-4 mb-6">
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Tổng yêu cầu</CardTitle>
          <Edit className="h-4 w-4 text-muted-foreground" />
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
          <CardTitle className="text-sm font-medium">Từ chối</CardTitle>
          <XCircle className="h-4 w-4 text-red-500" />
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold text-red-600">{rejectedRequests}</div>
        </CardContent>
      </Card>
    </div>
  );
};

interface AttendanceCorrectionsTableProps {
  requests: AttendanceCorrectionRequest[];
  isLoading: boolean;
  showActions: boolean;
}

const AttendanceCorrectionsTable = ({ requests, isLoading, showActions }: AttendanceCorrectionsTableProps) => {
  const { handleApproveClick, handleRejectClick, handleCancel } = useAttendanceCorrectionContext();
  const { isManager } = useAuth();

  const formatTime = (time: string | undefined) => {
    if (!time) return '-';
    return time;
  };

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
            <TableHead>Loại</TableHead>
            <TableHead>Ngày chấm công</TableHead>
            <TableHead>Giờ cũ (Vào/Ra)</TableHead>
            <TableHead>Giờ mới (Vào/Ra)</TableHead>
            <TableHead>Lý do</TableHead>
            <TableHead>Trạng thái</TableHead>
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
              <TableCell>
                <Badge variant="outline">{getCorrectionActionLabel(request.action)}</Badge>
              </TableCell>
              <TableCell>{format(new Date(request.correctionDate), 'dd/MM/yyyy', { locale: vi })}</TableCell>
              <TableCell>
                <div className="text-sm">
                  {formatTime(request.originalCheckIn)} / {formatTime(request.originalCheckOut)}
                </div>
              </TableCell>
              <TableCell>
                <div className="text-sm font-medium text-green-600">
                  {formatTime(request.newCheckIn)} / {formatTime(request.newCheckOut)}
                </div>
              </TableCell>
              <TableCell className="max-w-[200px] truncate">{request.reason || '-'}</TableCell>
              <TableCell>
                <Badge className={getCorrectionStatusColor(request.status)}>
                  {getCorrectionStatusLabel(request.status)}
                </Badge>
              </TableCell>
              {showActions && (
                <TableCell className="text-right">
                  <div className="flex justify-end gap-2">
                    {request.status === CorrectionStatus.PENDING && isManager && (
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
                    {request.status === CorrectionStatus.PENDING && (
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

const AttendanceCorrectionsTabs = () => {
  const { paginatedRequests, paginatedPendingRequests, isLoading } = useAttendanceCorrectionContext();
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
          <AttendanceCorrectionsTable
            requests={paginatedPendingRequests?.items || []}
            isLoading={isLoading}
            showActions={true}
          />
        </TabsContent>
      )}

      <TabsContent value="all" className="mt-6">
        <AttendanceCorrectionsTable
          requests={paginatedRequests?.items || []}
          isLoading={isLoading}
          showActions={true}
        />
      </TabsContent>
    </Tabs>
  );
};

const CreateAttendanceCorrectionDialog = () => {
  const { dialogMode, setDialogMode, handleCreate } = useAttendanceCorrectionContext();
  const [action, setAction] = useState<CorrectionAction>(CorrectionAction.EDIT);
  const [correctionDate, setCorrectionDate] = useState<string>(format(new Date(), 'yyyy-MM-dd'));
  const [newCheckIn, setNewCheckIn] = useState<string>('');
  const [newCheckOut, setNewCheckOut] = useState<string>('');
  const [reason, setReason] = useState<string>('');

  const isOpen = dialogMode === 'create';

  const handleSubmit = async () => {
    if (!correctionDate) return;
    await handleCreate({
      action,
      correctionDate,
      newCheckIn: newCheckIn || undefined,
      newCheckOut: newCheckOut || undefined,
      reason,
    });
    resetForm();
  };

  const resetForm = () => {
    setAction(CorrectionAction.EDIT);
    setCorrectionDate(format(new Date(), 'yyyy-MM-dd'));
    setNewCheckIn('');
    setNewCheckOut('');
    setReason('');
  };

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && setDialogMode(null)}>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle>Yêu cầu sửa chấm công</DialogTitle>
          <DialogDescription>Nhập thông tin sửa chấm công của bạn</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4 py-4">
          <div className="grid gap-2">
            <Label htmlFor="action">Loại yêu cầu</Label>
            <Select value={action.toString()} onValueChange={(val) => setAction(parseInt(val))}>
              <SelectTrigger>
                <SelectValue placeholder="Chọn loại yêu cầu" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="0">Thêm mới</SelectItem>
                <SelectItem value="1">Chỉnh sửa</SelectItem>
                <SelectItem value="2">Xóa</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="correctionDate">Ngày chấm công</Label>
            <Input
              id="correctionDate"
              type="date"
              value={correctionDate}
              onChange={(e) => setCorrectionDate(e.target.value)}
            />
          </div>
          {action !== CorrectionAction.DELETE && (
            <>
              <div className="grid grid-cols-2 gap-4">
                <div className="grid gap-2">
                  <Label htmlFor="newCheckIn">Giờ vào mới</Label>
                  <Input
                    id="newCheckIn"
                    type="time"
                    value={newCheckIn}
                    onChange={(e) => setNewCheckIn(e.target.value)}
                  />
                </div>
                <div className="grid gap-2">
                  <Label htmlFor="newCheckOut">Giờ ra mới</Label>
                  <Input
                    id="newCheckOut"
                    type="time"
                    value={newCheckOut}
                    onChange={(e) => setNewCheckOut(e.target.value)}
                  />
                </div>
              </div>
            </>
          )}
          <div className="grid gap-2">
            <Label htmlFor="reason">Lý do</Label>
            <Textarea
              id="reason"
              placeholder="Nhập lý do sửa chấm công"
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
    setRejectReason,
  } = useAttendanceCorrectionContext();

  return (
    <>
      {/* Approve Dialog */}
      <AlertDialog open={dialogMode === 'approve'} onOpenChange={(open) => !open && setDialogMode(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Xác nhận duyệt yêu cầu</AlertDialogTitle>
            <AlertDialogDescription>
              Bạn có chắc chắn muốn duyệt yêu cầu sửa chấm công của {selectedRequest?.employeeName}?
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
              Vui lòng nhập lý do từ chối yêu cầu sửa chấm công của {selectedRequest?.employeeName}
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

const AttendanceCorrectionsContent = () => {
  return (
    <div className="container mx-auto py-6">
      <AttendanceCorrectionsHeader />
      <div className="mt-6">
        <AttendanceCorrectionsSummary />
        <AttendanceCorrectionsTabs />
      </div>
      <CreateAttendanceCorrectionDialog />
      <ApproveRejectDialogs />
    </div>
  );
};

const AttendanceCorrections = () => {
  return (
    <AttendanceCorrectionProvider>
      <AttendanceCorrectionsContent />
    </AttendanceCorrectionProvider>
  );
};

export default AttendanceCorrections;
