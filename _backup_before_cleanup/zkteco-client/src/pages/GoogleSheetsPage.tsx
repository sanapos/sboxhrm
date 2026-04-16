import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import { Loader2, RefreshCw, CheckCircle, XCircle, Sheet, Upload, Users, HardDrive, Calendar } from 'lucide-react';
import { apiService } from '@/services/api';

interface SyncAllResult {
  devicesSynced: boolean;
  devicesCount: number;
  employeesSynced: boolean;
  employeesCount: number;
  attendancesSynced: boolean;
  attendancesCount: number;
}

export default function GoogleSheetsPage() {
  const [spreadsheetId, setSpreadsheetId] = useState('');
  const [credentialsPath, setCredentialsPath] = useState('credentials.json');
  const [isConnected, setIsConnected] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [syncDate, setSyncDate] = useState(new Date().toISOString().split('T')[0]);
  const [lastSyncResult, setLastSyncResult] = useState<SyncAllResult | null>(null);

  const testConnection = async () => {
    setIsLoading(true);
    try {
      const result = await apiService.get<boolean>('/api/GoogleSheets/test-connection');
      setIsConnected(result);
      if (result) {
        toast.success('Kết nối Google Sheets thành công!');
      } else {
        toast.error('Không thể kết nối');
      }
    } catch (error: any) {
      setIsConnected(false);
      toast.error(error.message || 'Không thể kiểm tra kết nối');
    } finally {
      setIsLoading(false);
    }
  };

  const initializeSheet = async () => {
    if (!spreadsheetId) {
      toast.error('Vui lòng nhập Spreadsheet ID');
      return;
    }

    setIsLoading(true);
    try {
      const result = await apiService.post<boolean>('/api/GoogleSheets/initialize', {
        spreadsheetId,
        credentialsPath: credentialsPath || undefined,
      });
      
      if (result) {
        setIsConnected(true);
        toast.success('Đã khởi tạo Google Sheets thành công!');
      } else {
        toast.error('Không thể khởi tạo');
      }
    } catch (error: any) {
      toast.error(error.message || 'Không thể khởi tạo Google Sheets');
    } finally {
      setIsLoading(false);
    }
  };

  const syncDevices = async () => {
    setIsLoading(true);
    try {
      const result = await apiService.post<boolean>('/api/GoogleSheets/sync-devices');
      if (result) {
        toast.success('Đồng bộ thiết bị thành công!');
      } else {
        toast.error('Không thể đồng bộ thiết bị');
      }
    } catch (error: any) {
      toast.error(error.message || 'Không thể đồng bộ thiết bị');
    } finally {
      setIsLoading(false);
    }
  };

  const syncEmployees = async () => {
    setIsLoading(true);
    try {
      const result = await apiService.post<boolean>('/api/GoogleSheets/sync-employees');
      if (result) {
        toast.success('Đồng bộ nhân viên thành công!');
      } else {
        toast.error('Không thể đồng bộ nhân viên');
      }
    } catch (error: any) {
      toast.error(error.message || 'Không thể đồng bộ nhân viên');
    } finally {
      setIsLoading(false);
    }
  };

  const syncAttendances = async () => {
    setIsLoading(true);
    try {
      const result = await apiService.post<boolean>('/api/GoogleSheets/sync-attendances', {
        date: syncDate,
      });
      if (result) {
        toast.success('Đồng bộ chấm công thành công!');
      } else {
        toast.error('Không thể đồng bộ chấm công');
      }
    } catch (error: any) {
      toast.error(error.message || 'Không thể đồng bộ dữ liệu chấm công');
    } finally {
      setIsLoading(false);
    }
  };

  const syncAll = async () => {
    setIsLoading(true);
    try {
      const result = await apiService.post<SyncAllResult>('/api/GoogleSheets/sync-all');
      setLastSyncResult(result);
      toast.success('Đồng bộ tất cả dữ liệu thành công!');
    } catch (error: any) {
      toast.error(error.message || 'Không thể đồng bộ');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="container mx-auto p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">Google Sheets Integration</h1>
          <p className="text-muted-foreground">
            Đồng bộ dữ liệu chấm công realtime lên Google Sheets
          </p>
        </div>
        <div className="flex items-center gap-2">
          {isConnected ? (
            <span className="flex items-center gap-1 text-green-600">
              <CheckCircle className="h-5 w-5" />
              Đã kết nối
            </span>
          ) : (
            <span className="flex items-center gap-1 text-red-600">
              <XCircle className="h-5 w-5" />
              Chưa kết nối
            </span>
          )}
        </div>
      </div>

      {/* Configuration Card */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Sheet className="h-5 w-5" />
            Cấu hình Google Sheets
          </CardTitle>
          <CardDescription>
            Nhập thông tin để kết nối với Google Sheets của bạn
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="spreadsheetId">Spreadsheet ID</Label>
              <Input
                id="spreadsheetId"
                placeholder="1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"
                value={spreadsheetId}
                onChange={(e) => setSpreadsheetId(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                ID lấy từ URL Google Sheet: docs.google.com/spreadsheets/d/<strong>ID_HERE</strong>/edit
              </p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="credentialsPath">Đường dẫn Credentials</Label>
              <Input
                id="credentialsPath"
                placeholder="credentials.json"
                value={credentialsPath}
                onChange={(e) => setCredentialsPath(e.target.value)}
              />
            </div>
          </div>
          <div className="flex gap-2">
            <Button onClick={initializeSheet} disabled={isLoading}>
              {isLoading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <Upload className="mr-2 h-4 w-4" />
              )}
              Khởi tạo
            </Button>
            <Button variant="outline" onClick={testConnection} disabled={isLoading}>
              {isLoading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <RefreshCw className="mr-2 h-4 w-4" />
              )}
              Kiểm tra kết nối
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Sync Actions */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <HardDrive className="h-4 w-4" />
              Thiết bị
            </CardTitle>
          </CardHeader>
          <CardContent>
            <Button 
              className="w-full" 
              onClick={syncDevices} 
              disabled={isLoading || !isConnected}
            >
              {isLoading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <RefreshCw className="mr-2 h-4 w-4" />
              )}
              Đồng bộ thiết bị
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <Users className="h-4 w-4" />
              Nhân viên
            </CardTitle>
          </CardHeader>
          <CardContent>
            <Button 
              className="w-full" 
              onClick={syncEmployees} 
              disabled={isLoading || !isConnected}
            >
              {isLoading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <RefreshCw className="mr-2 h-4 w-4" />
              )}
              Đồng bộ nhân viên
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <Calendar className="h-4 w-4" />
              Chấm công
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <Input
              type="date"
              value={syncDate}
              onChange={(e) => setSyncDate(e.target.value)}
            />
            <Button 
              className="w-full" 
              onClick={syncAttendances} 
              disabled={isLoading || !isConnected}
            >
              {isLoading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <RefreshCw className="mr-2 h-4 w-4" />
              )}
              Đồng bộ chấm công
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <Sheet className="h-4 w-4" />
              Đồng bộ tất cả
            </CardTitle>
          </CardHeader>
          <CardContent>
            <Button 
              className="w-full" 
              variant="default" 
              onClick={syncAll} 
              disabled={isLoading || !isConnected}
            >
              {isLoading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <Upload className="mr-2 h-4 w-4" />
              )}
              Đồng bộ tất cả
            </Button>
          </CardContent>
        </Card>
      </div>

      {/* Last Sync Result */}
      {lastSyncResult && (
        <Card>
          <CardHeader>
            <CardTitle>Kết quả đồng bộ gần nhất</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-3 gap-4 text-center">
              <div className="p-4 bg-muted rounded-lg">
                <div className="flex items-center justify-center gap-2">
                  {lastSyncResult.devicesSynced ? (
                    <CheckCircle className="h-5 w-5 text-green-600" />
                  ) : (
                    <XCircle className="h-5 w-5 text-red-600" />
                  )}
                  <span className="font-bold text-2xl">{lastSyncResult.devicesCount}</span>
                </div>
                <p className="text-muted-foreground">Thiết bị</p>
              </div>
              <div className="p-4 bg-muted rounded-lg">
                <div className="flex items-center justify-center gap-2">
                  {lastSyncResult.employeesSynced ? (
                    <CheckCircle className="h-5 w-5 text-green-600" />
                  ) : (
                    <XCircle className="h-5 w-5 text-red-600" />
                  )}
                  <span className="font-bold text-2xl">{lastSyncResult.employeesCount}</span>
                </div>
                <p className="text-muted-foreground">Nhân viên</p>
              </div>
              <div className="p-4 bg-muted rounded-lg">
                <div className="flex items-center justify-center gap-2">
                  {lastSyncResult.attendancesSynced ? (
                    <CheckCircle className="h-5 w-5 text-green-600" />
                  ) : (
                    <XCircle className="h-5 w-5 text-red-600" />
                  )}
                  <span className="font-bold text-2xl">{lastSyncResult.attendancesCount}</span>
                </div>
                <p className="text-muted-foreground">Bản ghi chấm công</p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Instructions */}
      <Card>
        <CardHeader>
          <CardTitle>Hướng dẫn cài đặt</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <h4 className="font-semibold">1. Tạo Service Account trên Google Cloud Console</h4>
            <ol className="list-decimal list-inside text-sm text-muted-foreground space-y-1 ml-4">
              <li>Truy cập <a href="https://console.cloud.google.com" className="text-primary underline" target="_blank">Google Cloud Console</a></li>
              <li>Tạo project mới hoặc chọn project có sẵn</li>
              <li>Vào APIs & Services → Enable Google Sheets API</li>
              <li>Vào IAM & Admin → Service Accounts → Create Service Account</li>
              <li>Tạo key JSON và download file credentials</li>
            </ol>
          </div>
          <div className="space-y-2">
            <h4 className="font-semibold">2. Chia sẻ Google Sheet với Service Account</h4>
            <ol className="list-decimal list-inside text-sm text-muted-foreground space-y-1 ml-4">
              <li>Mở file credentials.json, copy email của service account</li>
              <li>Mở Google Sheet và chia sẻ (Share) với email đó với quyền Editor</li>
            </ol>
          </div>
          <div className="space-y-2">
            <h4 className="font-semibold">3. Cấu hình trong ứng dụng</h4>
            <ol className="list-decimal list-inside text-sm text-muted-foreground space-y-1 ml-4">
              <li>Copy file credentials.json vào thư mục API</li>
              <li>Nhập Spreadsheet ID từ URL của Google Sheet</li>
              <li>Click "Khởi tạo" để tạo các sheet cần thiết</li>
            </ol>
          </div>
          <div className="space-y-2">
            <h4 className="font-semibold">4. Tính năng Realtime</h4>
            <p className="text-sm text-muted-foreground ml-4">
              Khi máy chấm công gửi dữ liệu lên server, dữ liệu sẽ tự động được đẩy lên Google Sheet trong tab "Attendance".
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
