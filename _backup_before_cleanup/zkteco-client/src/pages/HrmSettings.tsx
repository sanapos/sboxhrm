import { PageHeader } from "@/components/PageHeader";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Plus, Edit, Trash2, DollarSign, Shield, Calculator } from "lucide-react";
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
import { Switch } from "@/components/ui/switch";
import { penaltySettingService, insuranceSettingService, taxSettingService } from "@/services/settingsService";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { 
  PenaltySetting, 
  CreatePenaltySettingRequest,
  InsuranceSetting,
  CreateInsuranceSettingRequest,
  TaxSetting,
  CreateTaxSettingRequest,
} from "@/types/settings";

const formatCurrency = (amount: number) => {
  return new Intl.NumberFormat('vi-VN', { 
    style: 'currency', 
    currency: 'VND' 
  }).format(amount);
};

const formatPercent = (value: number) => {
  return `${value}%`;
};

// ============ PENALTY SETTINGS TAB ============
const PenaltySettingsTab = () => {
  const queryClient = useQueryClient();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingItem, setEditingItem] = useState<PenaltySetting | null>(null);
  const [deleteId, setDeleteId] = useState<string | null>(null);

  // Form state
  const [formData, setFormData] = useState<CreatePenaltySettingRequest>({
    name: '',
    description: '',
    isLatePolicy: true,
    level: 1,
    minMinutes: 0,
    maxMinutes: 0,
    penaltyAmount: 0,
    isPercentage: false,
  });

  const { data: penalties, isLoading } = useQuery({
    queryKey: ['penalty-settings'],
    queryFn: () => penaltySettingService.getAll(),
  });

  const createMutation = useMutation({
    mutationFn: penaltySettingService.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['penalty-settings'] });
      toast.success('Đã tạo quy định phạt');
      setIsDialogOpen(false);
      resetForm();
    },
    onError: () => toast.error('Không thể tạo quy định'),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: any }) => penaltySettingService.update(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['penalty-settings'] });
      toast.success('Đã cập nhật quy định');
      setIsDialogOpen(false);
      setEditingItem(null);
      resetForm();
    },
    onError: () => toast.error('Không thể cập nhật quy định'),
  });

  const deleteMutation = useMutation({
    mutationFn: penaltySettingService.delete,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['penalty-settings'] });
      toast.success('Đã xóa quy định');
      setDeleteId(null);
    },
    onError: () => toast.error('Không thể xóa quy định'),
  });

  const toggleMutation = useMutation({
    mutationFn: penaltySettingService.toggleActive,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['penalty-settings'] });
      toast.success('Đã cập nhật trạng thái');
    },
    onError: () => toast.error('Không thể cập nhật trạng thái'),
  });

  const resetForm = () => {
    setFormData({
      name: '',
      description: '',
      isLatePolicy: true,
      level: 1,
      minMinutes: 0,
      maxMinutes: 0,
      penaltyAmount: 0,
      isPercentage: false,
    });
  };

  const handleEdit = (item: PenaltySetting) => {
    setEditingItem(item);
    setFormData({
      name: item.name,
      description: item.description || '',
      isLatePolicy: item.isLatePolicy,
      level: item.level,
      minMinutes: item.minMinutes,
      maxMinutes: item.maxMinutes,
      penaltyAmount: item.penaltyAmount,
      isPercentage: item.isPercentage,
    });
    setIsDialogOpen(true);
  };

  const handleSubmit = () => {
    if (editingItem) {
      updateMutation.mutate({ id: editingItem.id, data: { ...formData, isActive: editingItem.isActive } });
    } else {
      createMutation.mutate(formData);
    }
  };

  return (
    <>
      <div className="flex justify-between items-center mb-4">
        <div>
          <h3 className="text-lg font-medium">Quy định phạt đi muộn / về sớm</h3>
          <p className="text-sm text-muted-foreground">Cấu hình mức phạt theo số phút vi phạm</p>
        </div>
        <Button onClick={() => { setEditingItem(null); resetForm(); setIsDialogOpen(true); }}>
          <Plus className="mr-2 h-4 w-4" />
          Thêm quy định
        </Button>
      </div>

      <div className="rounded-md border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Tên</TableHead>
              <TableHead>Loại</TableHead>
              <TableHead>Mức</TableHead>
              <TableHead>Phút (từ - đến)</TableHead>
              <TableHead>Mức phạt</TableHead>
              <TableHead>Trạng thái</TableHead>
              <TableHead className="text-right">Thao tác</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoading ? (
              <TableRow>
                <TableCell colSpan={7} className="text-center">Đang tải...</TableCell>
              </TableRow>
            ) : penalties && penalties.length > 0 ? (
              penalties.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-medium">{item.name}</TableCell>
                  <TableCell>
                    <Badge variant="outline">
                      {item.isLatePolicy ? 'Đi muộn' : 'Về sớm'}
                    </Badge>
                  </TableCell>
                  <TableCell>{item.level}</TableCell>
                  <TableCell>{item.minMinutes} - {item.maxMinutes} phút</TableCell>
                  <TableCell>
                    {item.isPercentage 
                      ? formatPercent(item.penaltyAmount)
                      : formatCurrency(item.penaltyAmount)
                    }
                  </TableCell>
                  <TableCell>
                    <Switch
                      checked={item.isActive}
                      onCheckedChange={() => toggleMutation.mutate(item.id)}
                    />
                  </TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-2">
                      <Button size="icon" variant="ghost" onClick={() => handleEdit(item)}>
                        <Edit className="h-4 w-4" />
                      </Button>
                      <Button size="icon" variant="ghost" className="text-red-600" onClick={() => setDeleteId(item.id)}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell colSpan={7} className="text-center text-muted-foreground">
                  Chưa có quy định nào
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      {/* Create/Edit Dialog */}
      <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
        <DialogContent className="sm:max-w-[500px]">
          <DialogHeader>
            <DialogTitle>{editingItem ? 'Sửa quy định' : 'Thêm quy định'}</DialogTitle>
            <DialogDescription>Nhập thông tin quy định phạt</DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid gap-2">
              <Label>Tên quy định</Label>
              <Input
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              />
            </div>
            <div className="grid gap-2">
              <Label>Mô tả</Label>
              <Textarea
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              />
            </div>
            <div className="flex items-center gap-4">
              <Label>Loại vi phạm</Label>
              <div className="flex items-center gap-2">
                <Switch
                  checked={formData.isLatePolicy}
                  onCheckedChange={(checked: boolean) => setFormData({ ...formData, isLatePolicy: checked })}
                />
                <span>{formData.isLatePolicy ? 'Đi muộn' : 'Về sớm'}</span>
              </div>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <div className="grid gap-2">
                <Label>Mức</Label>
                <Input
                  type="number"
                  value={formData.level}
                  onChange={(e) => setFormData({ ...formData, level: parseInt(e.target.value) })}
                />
              </div>
              <div className="grid gap-2">
                <Label>Từ (phút)</Label>
                <Input
                  type="number"
                  value={formData.minMinutes}
                  onChange={(e) => setFormData({ ...formData, minMinutes: parseInt(e.target.value) })}
                />
              </div>
              <div className="grid gap-2">
                <Label>Đến (phút)</Label>
                <Input
                  type="number"
                  value={formData.maxMinutes}
                  onChange={(e) => setFormData({ ...formData, maxMinutes: parseInt(e.target.value) })}
                />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="grid gap-2">
                <Label>Mức phạt</Label>
                <Input
                  type="number"
                  value={formData.penaltyAmount}
                  onChange={(e) => setFormData({ ...formData, penaltyAmount: parseFloat(e.target.value) })}
                />
              </div>
              <div className="flex items-end gap-2">
                <Switch
                  checked={formData.isPercentage}
                  onCheckedChange={(checked: boolean) => setFormData({ ...formData, isPercentage: checked })}
                />
                <span>{formData.isPercentage ? 'Phần trăm (%)' : 'Số tiền (VNĐ)'}</span>
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setIsDialogOpen(false)}>Hủy</Button>
            <Button onClick={handleSubmit}>Lưu</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete Dialog */}
      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Xác nhận xóa</AlertDialogTitle>
            <AlertDialogDescription>
              Bạn có chắc chắn muốn xóa quy định này? Hành động này không thể hoàn tác.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Hủy</AlertDialogCancel>
            <AlertDialogAction onClick={() => deleteId && deleteMutation.mutate(deleteId)}>
              Xóa
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
};

// ============ INSURANCE SETTINGS TAB ============
const InsuranceSettingsTab = () => {
  const queryClient = useQueryClient();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingItem, setEditingItem] = useState<InsuranceSetting | null>(null);

  const [formData, setFormData] = useState<CreateInsuranceSettingRequest>({
    code: '',
    name: '',
    description: '',
    employeeRate: 0,
    employerRate: 0,
    maxSalaryBase: undefined,
  });

  const { data: insurances, isLoading } = useQuery({
    queryKey: ['insurance-settings'],
    queryFn: () => insuranceSettingService.getAll(),
  });

  const createMutation = useMutation({
    mutationFn: insuranceSettingService.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['insurance-settings'] });
      toast.success('Đã tạo loại bảo hiểm');
      setIsDialogOpen(false);
      resetForm();
    },
    onError: () => toast.error('Không thể tạo'),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: any }) => insuranceSettingService.update(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['insurance-settings'] });
      toast.success('Đã cập nhật');
      setIsDialogOpen(false);
      setEditingItem(null);
      resetForm();
    },
    onError: () => toast.error('Không thể cập nhật'),
  });

  const toggleMutation = useMutation({
    mutationFn: insuranceSettingService.toggleActive,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['insurance-settings'] });
      toast.success('Đã cập nhật trạng thái');
    },
    onError: () => toast.error('Không thể cập nhật'),
  });

  const resetForm = () => {
    setFormData({
      code: '',
      name: '',
      description: '',
      employeeRate: 0,
      employerRate: 0,
      maxSalaryBase: undefined,
    });
  };

  const handleEdit = (item: InsuranceSetting) => {
    setEditingItem(item);
    setFormData({
      code: item.code,
      name: item.name,
      description: item.description || '',
      employeeRate: item.employeeRate,
      employerRate: item.employerRate,
      maxSalaryBase: item.maxSalaryBase,
    });
    setIsDialogOpen(true);
  };

  const handleSubmit = () => {
    if (editingItem) {
      updateMutation.mutate({ id: editingItem.id, data: { ...formData, isActive: editingItem.isActive } });
    } else {
      createMutation.mutate(formData);
    }
  };

  return (
    <>
      <div className="flex justify-between items-center mb-4">
        <div>
          <h3 className="text-lg font-medium">Cài đặt bảo hiểm</h3>
          <p className="text-sm text-muted-foreground">Cấu hình BHXH, BHYT, BHTN</p>
        </div>
        <Button onClick={() => { setEditingItem(null); resetForm(); setIsDialogOpen(true); }}>
          <Plus className="mr-2 h-4 w-4" />
          Thêm loại bảo hiểm
        </Button>
      </div>

      <div className="rounded-md border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Mã</TableHead>
              <TableHead>Tên</TableHead>
              <TableHead>Nhân viên đóng</TableHead>
              <TableHead>Công ty đóng</TableHead>
              <TableHead>Mức lương tối đa</TableHead>
              <TableHead>Trạng thái</TableHead>
              <TableHead className="text-right">Thao tác</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoading ? (
              <TableRow>
                <TableCell colSpan={7} className="text-center">Đang tải...</TableCell>
              </TableRow>
            ) : insurances && insurances.length > 0 ? (
              insurances.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-medium">{item.code}</TableCell>
                  <TableCell>{item.name}</TableCell>
                  <TableCell>{formatPercent(item.employeeRate)}</TableCell>
                  <TableCell>{formatPercent(item.employerRate)}</TableCell>
                  <TableCell>{item.maxSalaryBase ? formatCurrency(item.maxSalaryBase) : '-'}</TableCell>
                  <TableCell>
                    <Switch
                      checked={item.isActive}
                      onCheckedChange={() => toggleMutation.mutate(item.id)}
                    />
                  </TableCell>
                  <TableCell className="text-right">
                    <Button size="icon" variant="ghost" onClick={() => handleEdit(item)}>
                      <Edit className="h-4 w-4" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell colSpan={7} className="text-center text-muted-foreground">
                  Chưa có loại bảo hiểm nào
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
        <DialogContent className="sm:max-w-[500px]">
          <DialogHeader>
            <DialogTitle>{editingItem ? 'Sửa loại bảo hiểm' : 'Thêm loại bảo hiểm'}</DialogTitle>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="grid gap-2">
                <Label>Mã</Label>
                <Input
                  value={formData.code}
                  onChange={(e) => setFormData({ ...formData, code: e.target.value })}
                  disabled={!!editingItem}
                />
              </div>
              <div className="grid gap-2">
                <Label>Tên</Label>
                <Input
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                />
              </div>
            </div>
            <div className="grid gap-2">
              <Label>Mô tả</Label>
              <Textarea
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="grid gap-2">
                <Label>Nhân viên đóng (%)</Label>
                <Input
                  type="number"
                  step="0.1"
                  value={formData.employeeRate}
                  onChange={(e) => setFormData({ ...formData, employeeRate: parseFloat(e.target.value) })}
                />
              </div>
              <div className="grid gap-2">
                <Label>Công ty đóng (%)</Label>
                <Input
                  type="number"
                  step="0.1"
                  value={formData.employerRate}
                  onChange={(e) => setFormData({ ...formData, employerRate: parseFloat(e.target.value) })}
                />
              </div>
            </div>
            <div className="grid gap-2">
              <Label>Mức lương tối đa (VNĐ)</Label>
              <Input
                type="number"
                value={formData.maxSalaryBase || ''}
                onChange={(e) => setFormData({ ...formData, maxSalaryBase: e.target.value ? parseFloat(e.target.value) : undefined })}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setIsDialogOpen(false)}>Hủy</Button>
            <Button onClick={handleSubmit}>Lưu</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
};

// ============ TAX SETTINGS TAB ============
const TaxSettingsTab = () => {
  const queryClient = useQueryClient();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingItem, setEditingItem] = useState<TaxSetting | null>(null);

  const [formData, setFormData] = useState<CreateTaxSettingRequest>({
    name: '',
    description: '',
    level: 1,
    minIncome: 0,
    maxIncome: undefined,
    taxRate: 0,
    deductionAmount: 0,
  });

  const { data: taxes, isLoading } = useQuery({
    queryKey: ['tax-settings'],
    queryFn: () => taxSettingService.getAll(),
  });

  const createMutation = useMutation({
    mutationFn: taxSettingService.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tax-settings'] });
      toast.success('Đã tạo bậc thuế');
      setIsDialogOpen(false);
      resetForm();
    },
    onError: () => toast.error('Không thể tạo'),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: any }) => taxSettingService.update(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tax-settings'] });
      toast.success('Đã cập nhật');
      setIsDialogOpen(false);
      setEditingItem(null);
      resetForm();
    },
    onError: () => toast.error('Không thể cập nhật'),
  });

  const toggleMutation = useMutation({
    mutationFn: taxSettingService.toggleActive,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tax-settings'] });
      toast.success('Đã cập nhật trạng thái');
    },
    onError: () => toast.error('Không thể cập nhật'),
  });

  const resetForm = () => {
    setFormData({
      name: '',
      description: '',
      level: 1,
      minIncome: 0,
      maxIncome: undefined,
      taxRate: 0,
      deductionAmount: 0,
    });
  };

  const handleEdit = (item: TaxSetting) => {
    setEditingItem(item);
    setFormData({
      name: item.name,
      description: item.description || '',
      level: item.level,
      minIncome: item.minIncome,
      maxIncome: item.maxIncome,
      taxRate: item.taxRate,
      deductionAmount: item.deductionAmount,
    });
    setIsDialogOpen(true);
  };

  const handleSubmit = () => {
    if (editingItem) {
      updateMutation.mutate({ id: editingItem.id, data: { ...formData, isActive: editingItem.isActive } });
    } else {
      createMutation.mutate(formData);
    }
  };

  return (
    <>
      <div className="flex justify-between items-center mb-4">
        <div>
          <h3 className="text-lg font-medium">Biểu thuế thu nhập cá nhân</h3>
          <p className="text-sm text-muted-foreground">Cấu hình các bậc thuế TNCN theo quy định</p>
        </div>
        <Button onClick={() => { setEditingItem(null); resetForm(); setIsDialogOpen(true); }}>
          <Plus className="mr-2 h-4 w-4" />
          Thêm bậc thuế
        </Button>
      </div>

      <div className="rounded-md border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Bậc</TableHead>
              <TableHead>Tên</TableHead>
              <TableHead>Thu nhập (từ - đến)</TableHead>
              <TableHead>Thuế suất</TableHead>
              <TableHead>Số tiền trừ</TableHead>
              <TableHead>Trạng thái</TableHead>
              <TableHead className="text-right">Thao tác</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoading ? (
              <TableRow>
                <TableCell colSpan={7} className="text-center">Đang tải...</TableCell>
              </TableRow>
            ) : taxes && taxes.length > 0 ? (
              taxes.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-medium">{item.level}</TableCell>
                  <TableCell>{item.name}</TableCell>
                  <TableCell>
                    {formatCurrency(item.minIncome)} - {item.maxIncome ? formatCurrency(item.maxIncome) : '∞'}
                  </TableCell>
                  <TableCell>{formatPercent(item.taxRate)}</TableCell>
                  <TableCell>{formatCurrency(item.deductionAmount)}</TableCell>
                  <TableCell>
                    <Switch
                      checked={item.isActive}
                      onCheckedChange={() => toggleMutation.mutate(item.id)}
                    />
                  </TableCell>
                  <TableCell className="text-right">
                    <Button size="icon" variant="ghost" onClick={() => handleEdit(item)}>
                      <Edit className="h-4 w-4" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell colSpan={7} className="text-center text-muted-foreground">
                  Chưa có bậc thuế nào
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
        <DialogContent className="sm:max-w-[500px]">
          <DialogHeader>
            <DialogTitle>{editingItem ? 'Sửa bậc thuế' : 'Thêm bậc thuế'}</DialogTitle>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="grid gap-2">
                <Label>Bậc</Label>
                <Input
                  type="number"
                  value={formData.level}
                  onChange={(e) => setFormData({ ...formData, level: parseInt(e.target.value) })}
                />
              </div>
              <div className="grid gap-2">
                <Label>Tên</Label>
                <Input
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="grid gap-2">
                <Label>Thu nhập từ (VNĐ)</Label>
                <Input
                  type="number"
                  value={formData.minIncome}
                  onChange={(e) => setFormData({ ...formData, minIncome: parseFloat(e.target.value) })}
                />
              </div>
              <div className="grid gap-2">
                <Label>Thu nhập đến (VNĐ)</Label>
                <Input
                  type="number"
                  value={formData.maxIncome || ''}
                  onChange={(e) => setFormData({ ...formData, maxIncome: e.target.value ? parseFloat(e.target.value) : undefined })}
                />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="grid gap-2">
                <Label>Thuế suất (%)</Label>
                <Input
                  type="number"
                  step="0.1"
                  value={formData.taxRate}
                  onChange={(e) => setFormData({ ...formData, taxRate: parseFloat(e.target.value) })}
                />
              </div>
              <div className="grid gap-2">
                <Label>Số tiền trừ (VNĐ)</Label>
                <Input
                  type="number"
                  value={formData.deductionAmount}
                  onChange={(e) => setFormData({ ...formData, deductionAmount: parseFloat(e.target.value) })}
                />
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setIsDialogOpen(false)}>Hủy</Button>
            <Button onClick={handleSubmit}>Lưu</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
};

// ============ MAIN COMPONENT ============
const HrmSettings = () => {
  return (
    <div className="container mx-auto py-6">
      <PageHeader
        title="Cài đặt HRM"
        description="Quản lý cấu hình quy định phạt, bảo hiểm và thuế"
      />

      <div className="mt-6">
        <Tabs defaultValue="penalties" className="w-full">
          <TabsList className="grid w-full grid-cols-3">
            <TabsTrigger value="penalties">
              <DollarSign className="mr-2 h-4 w-4" />
              Quy định phạt
            </TabsTrigger>
            <TabsTrigger value="insurance">
              <Shield className="mr-2 h-4 w-4" />
              Bảo hiểm
            </TabsTrigger>
            <TabsTrigger value="tax">
              <Calculator className="mr-2 h-4 w-4" />
              Thuế TNCN
            </TabsTrigger>
          </TabsList>

          <TabsContent value="penalties" className="mt-6">
            <PenaltySettingsTab />
          </TabsContent>

          <TabsContent value="insurance" className="mt-6">
            <InsuranceSettingsTab />
          </TabsContent>

          <TabsContent value="tax" className="mt-6">
            <TaxSettingsTab />
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
};

export default HrmSettings;
