import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import '../utils/device_setup_guide.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_mini_stat_chip.dart';
import '../widgets/hrm/hrm_settings_mobile_kit.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/device_sync_progress_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
class DeviceManagementSettingsScreen extends StatefulWidget {
  const DeviceManagementSettingsScreen({super.key});

  @override
  State<DeviceManagementSettingsScreen> createState() => _DeviceManagementSettingsScreenState();
}

class _DeviceManagementSettingsScreenState extends State<DeviceManagementSettingsScreen> {
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  final _apiService = ApiService();
  List<Map<String, dynamic>> _devices = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, online, offline
  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      final devices = await _apiService.getDevices(storeOnly: true);
      if (!mounted) return;
      setState(() {
        _devices = devices.map((d) => Map<String, dynamic>.from(d)).toList();
      });
    } catch (e) {
      debugPrint('Error loading devices: $e');
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi tải dữ liệu',
          message: tr('Không thể tải danh sách thiết bị: $e'),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool _isOnline(Map<String, dynamic> device) {
    // Ưu tiên dùng trạng thái do backend tính sẵn
    final status = device['deviceStatus']?.toString().toLowerCase();
    if (status != null && status.isNotEmpty) {
      return status == 'online';
    }
    // Fallback: tính từ lastOnline (server lưu UTC, phải parse đúng)
    final lastOnline = device['lastOnline'];
    if (lastOnline == null) return false;
    try {
      final raw = lastOnline.toString();
      // Nếu không có timezone info → server lưu UTC → thêm Z
      final dateStr = (raw.contains('Z') || raw.contains('+')) ? raw : '${raw}Z';
      final dt = DateTime.parse(dateStr);
      return DateTime.now().toUtc().difference(dt).inMinutes < 5;
    } catch (e) {
      debugPrint('Parse lastOnline error: $e');
      return false;
    }
  }

  List<Map<String, dynamic>> get _filteredDevices {
    var list = _devices;
    if (_statusFilter == 'online') {
      list = list.where(_isOnline).toList();
    } else if (_statusFilter == 'offline') {
      list = list.where((d) => !_isOnline(d)).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((d) {
        final name = (d['deviceName'] ?? '').toString().toLowerCase();
        final sn = (d['serialNumber'] ?? '').toString().toLowerCase();
        final loc = (d['location'] ?? '').toString().toLowerCase();
        final ip = (d['ipAddress'] ?? '').toString().toLowerCase();
        return name.contains(q) || sn.contains(q) || loc.contains(q) || ip.contains(q);
      }).toList();
    }
    return list;
  }

  int    get _totalCount   => _devices.length;
  int    get _onlineCount  => _devices.where(_isOnline).length;
  int    get _offlineCount => _devices.where((d) => !_isOnline(d)).length;

  // ==================== DEVICE COMMANDS ====================
  // DeviceCommandTypes enum (0-indexed):
  // 0=AddDeviceUser, 1=DeleteDeviceUser, 2=UpdateDeviceUser
  // 3=ClearAttendances, 4=ClearDeviceUsers, 5=ClearData
  // 6=RestartDevice, 7=SyncAttendances, 8=SyncDeviceUsers
  // 9=EnrollFingerprint, 10=DeleteFingerprint, 11=SyncFingerprints
  // 12=EnrollFace, 13=DeleteFace, 14=SyncFaces
  // 15=OpenDoor, 16=CloseDoor, 17=GetDeviceInfo

  Future<_DeviceCommandOutcome> _sendCommand(
      Map<String, dynamic> device, int commandType, String label) async {
    final deviceId = device['id'].toString();

    // Lệnh nguy hiểm (ClearData=5, ClearAttendances=3, ClearDeviceUsers=4): yêu cầu xác nhận kép
    final isDangerous = commandType == 5 || commandType == 3 || commandType == 4;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr(isDangerous ? '⚠️ Cảnh báo nguy hiểm' : 'Xác nhận')),
        content: Text(tr(isDangerous
            ? 'CẢNH BÁO: Thao tác "$label" sẽ XÓA VĨNH VIỄN dữ liệu trên thiết bị "${device['deviceName']}"!\n\nHành động này KHÔNG THỂ hoàn tác. Bạn có chắc chắn?'
            : 'Bạn có chắc muốn "$label" trên thiết bị "${device['deviceName']}"?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: isDangerous ? FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)) : null,
            child: Text(tr(isDangerous ? 'Xác nhận XÓA' : 'Xác nhận')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return _DeviceCommandOutcome(
        success: false,
        message: tr('Đã hủy thao tác'),
        cancelled: true,
      );
    }

    final deviceName = device['deviceName']?.toString() ?? deviceId;
    if (commandType == 7 || commandType == 8) {
      final kind = commandType == 7
          ? DeviceSyncKind.attendances
          : DeviceSyncKind.deviceUsers;
      unawaited(DeviceSyncProgressDialog.show(
        apiService: _apiService,
        kind: kind,
        devices: [
          DeviceSyncTarget(deviceId: deviceId, deviceName: deviceName),
        ],
      ));
      return _DeviceCommandOutcome(
        success: true,
        message: commandType == 7
            ? 'Đã bắt đầu đồng bộ chấm công — xem tiến trình ở cạnh dưới màn hình.'
            : 'Đã bắt đầu đồng bộ user — xem tiến trình ở cạnh dưới màn hình.',
        isSync: true,
      );
    }

    final result = await _apiService.sendDeviceCommand(deviceId, commandType);
    if (!mounted) {
      return _DeviceCommandOutcome(
        success: false,
        message: tr('Không thể gửi lệnh'),
      );
    }

    final success = result['isSuccess'] == true;
    final apiMsg = result['message']?.toString().trim();
    if (!success) {
      if (commandType == 15 || commandType == 16) {
        await _loadDevices();
      }
      return _DeviceCommandOutcome(
        success: false,
        message: apiMsg?.isNotEmpty == true
            ? apiMsg!
            : 'Gửi lệnh "$label" thất bại',
        disableDoorControl: commandType == 15 || commandType == 16,
      );
    }

    Map<String, dynamic>? refreshedInfo;
    if (commandType == 17) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        try {
          refreshedInfo = await _apiService.getDeviceInfo(deviceId);
        } catch (_) {}
      }
    }

    final commandId = _extractDeviceCommandId(result);
    final isDoor = commandType == 15 || commandType == 16;
    final pollMessage = commandId != null
        ? await _pollDeviceCommandResult(commandId, isDoor: isDoor)
        : null;

    final pollOk = pollMessage == null ||
        pollMessage.contains('thành công') ||
        pollMessage.contains('xác nhận lệnh cửa');
    final executedOk = pollMessage == null
        ? true
        : (pollOk && !pollMessage.contains('chưa phản hồi'));

    var message = pollMessage ??
        (apiMsg?.isNotEmpty == true
            ? apiMsg!
            : 'Đã gửi lệnh "$label" thành công');
    if (pollMessage == null && commandId != null) {
      message =
          'Đã gửi lệnh "$label". Máy đang xử lý — có thể mất vài giây để hoàn tất.';
    }
    if (refreshedInfo != null && executedOk) {
      message = 'Đã cập nhật thông tin kỹ thuật từ máy.';
    }

    // Sau khi máy từ chối mở/đóng cửa (-1002), backend học capability → ẩn nút.
    if ((commandType == 15 || commandType == 16) && !executedOk) {
      await _loadDevices();
    }

    return _DeviceCommandOutcome(
      success: executedOk,
      message: message,
      refreshedDeviceInfo: refreshedInfo,
      disableDoorControl: (commandType == 15 || commandType == 16) && !executedOk,
    );
  }

  String? _extractDeviceCommandId(Map<String, dynamic> cmdRes) {
    final data = cmdRes['data'];
    if (data is Map) {
      return data['id']?.toString();
    }
    return cmdRes['commandId']?.toString();
  }

  Future<String?> _pollDeviceCommandResult(String commandId, {bool isDoor = false}) async {
    final started = DateTime.now();
    while (DateTime.now().difference(started) < const Duration(seconds: 25)) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return null;
      final status = await _apiService.getCommandStatus(commandId);
      if (status == null) continue;

      final s = status['status']?.toString().toLowerCase() ?? '';
      final ret = status['return']?.toString();
      if (ret == '-1' ||
          ret == '-1002' ||
          s == '3' ||
          s.contains('failed')) {
        final err = status['errorMessage']?.toString();
        return err?.isNotEmpty == true
            ? err!
            : 'Máy báo lỗi khi thực hiện lệnh';
      }
      if (s == '2' || s == 'success' || s.contains('success')) {
        if (isDoor) {
          // Return=0 chỉ nghĩa là máy ACK — chưa chắc đã nhả khóa/bip.
          return 'Máy đã xác nhận lệnh cửa (ACK). '
              'Nếu không bip/không mở khóa: kiểm tra dây Lock trên máy, '
              'và phần mềm kia có thể đang dùng kết nối LAN (TCP 4370) chứ không phải ADMS.';
        }
        return 'Máy đã thực hiện lệnh thành công';
      }
    }
    return isDoor
        ? 'Đã gửi lệnh cửa nhưng máy chưa phản hồi ACK — thử lại khi máy Online.'
        : null;
  }

  Future<void> _showRenameDialog(Map<String, dynamic> device) async {
    final nameCtrl = TextEditingController(text: tr(device['deviceName'] ?? ''));
    final locationCtrl = TextEditingController(text: tr(device['location'] ?? ''));
    final descCtrl = TextEditingController(text: tr(device['description'] ?? ''));

    final isMobileDialog = Responsive.isMobile(context);

    final formBody = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: tr('Tên thiết bị'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            prefixIcon: const Icon(Icons.devices),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: locationCtrl,
          decoration: InputDecoration(
            labelText: tr('Vị trí lắp đặt'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            prefixIcon: const Icon(Icons.location_on),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: descCtrl,
          decoration: InputDecoration(
            labelText: tr('Mô tả'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            prefixIcon: const Icon(Icons.description),
          ),
          maxLines: 2,
        ),
      ],
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        if (isMobileDialog) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(tr('Chỉnh sửa thiết bị')),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx, false)),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
                  ),
                ],
              ),
              body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formBody),
            ),
          );
        }

        return ScrollableAlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.edit, color: HrmPageChrome.primaryNavy),
              SizedBox(width: 8),
              Text(tr('Chỉnh sửa thiết bị')),
            ],
          ),
          content: SizedBox(
            width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(),
            child: formBody,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
          ],
        );
      },
    );

    if (result != true || !mounted) {
      nameCtrl.dispose();
      locationCtrl.dispose();
      descCtrl.dispose();
      return;
    }
    final deviceId = device['id'].toString();
    final newName = nameCtrl.text.trim();
    final newLocation = locationCtrl.text.trim();
    final newDescription = descCtrl.text.trim();
    nameCtrl.dispose();
    locationCtrl.dispose();
    descCtrl.dispose();

    final success = await _apiService.updateDevice(deviceId, {
      'deviceName': newName,
      'location': newLocation,
      'description': newDescription,
    });
    if (!mounted) return;
    if (success) {
      NotificationOverlayManager().showSuccess(title: 'Thành công', message: tr('Đã cập nhật thiết bị'));
      _loadDevices();
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: tr('Cập nhật thất bại'));
    }
  }

  Future<void> _showAddDeviceDialog() async {
    final snCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    String? serialError;
    String? serialSuccess;
    bool isCheckingSerial = false;

    await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> checkSerial() async {
            final sn = snCtrl.text.trim();
            if (sn.isEmpty) {
              setDialogState(() {
                serialError = 'Vui lòng nhập Serial Number';
                serialSuccess = null;
              });
              return;
            }
            setDialogState(() {
              isCheckingSerial = true;
              serialError = null;
              serialSuccess = null;
            });
            try {
              final result = await _apiService.checkSerialNumber(sn);
              if (!ctx.mounted) return;
              if (result['exists'] == true) {
                if (result['isClaimed'] == true) {
                  setDialogState(() {
                    serialError = 'Thiết bị này đã được sử dụng bởi cửa hàng khác';
                    serialSuccess = null;
                    isCheckingSerial = false;
                  });
                } else {
                  setDialogState(() {
                    serialSuccess = 'Thiết bị hợp lệ — đã kết nối server';
                    serialError = null;
                    isCheckingSerial = false;
                  });
                }
              } else {
                setDialogState(() {
                  serialError =
                      'Thiết bị chưa từng kết nối đến server.\n${DeviceSetupGuide.configureBeforeConnect}';
                  serialSuccess = null;
                  isCheckingSerial = false;
                });
              }
            } catch (e) {
              if (!ctx.mounted) return;
              setDialogState(() {
                serialError = 'Lỗi kiểm tra: $e';
                serialSuccess = null;
                isCheckingSerial = false;
              });
            }
          }

          Future<void> scanBarcode() async {
            final result = await showDialog<String>(
              context: ctx,
              builder: (scanCtx) => _BarcodeScannerDialog(),
            );
            if (result != null && result.isNotEmpty) {
              snCtrl.text = result;
              checkSerial();
            }
          }

          Future<void> submitDevice() async {
            if (snCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) {
              setDialogState(() {
                serialError = snCtrl.text.trim().isEmpty ? 'Vui lòng nhập Serial Number' : null;
              });
              if (nameCtrl.text.trim().isEmpty) {
                NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: tr('Vui lòng nhập Tên thiết bị'));
              }
              return;
            }

            // Kiểm tra serial trước khi tạo
            if (serialSuccess == null) {
              setDialogState(() {
                isCheckingSerial = true;
                serialError = null;
              });
              try {
                final result = await _apiService.checkSerialNumber(snCtrl.text.trim());
                if (!ctx.mounted) return;
                if (result['exists'] != true) {
                  setDialogState(() {
                    serialError =
                      'Thiết bị chưa từng kết nối đến server.\n${DeviceSetupGuide.configureBeforeConnect}';
                    isCheckingSerial = false;
                  });
                  return;
                }
                if (result['isClaimed'] == true) {
                  setDialogState(() {
                    serialError = 'Thiết bị này đã được sử dụng bởi cửa hàng khác';
                    isCheckingSerial = false;
                  });
                  return;
                }
              } catch (e) {
                if (!ctx.mounted) return;
                setDialogState(() {
                  serialError = 'Lỗi kiểm tra: $e';
                  isCheckingSerial = false;
                });
                return;
              }
              setDialogState(() => isCheckingSerial = false);
            }

            Navigator.pop(ctx);

            final createResult = await _apiService.createDevice({
              'serialNumber': snCtrl.text.trim(),
              'deviceName': nameCtrl.text.trim(),
              'location': locationCtrl.text.trim(),
              'description': descCtrl.text.trim(),
            });
            if (!mounted) return;
            if (createResult['success'] == true) {
              NotificationOverlayManager().showSuccess(title: 'Thành công', message: tr('Đã thêm thiết bị'));
              _loadDevices();
            } else {
              final msg = createResult['message'] ?? 'Thêm thiết bị thất bại';
              NotificationOverlayManager().showError(title: 'Lỗi', message: msg);
            }
          }

          final isMobileDialog = Responsive.isMobile(ctx);

          final formBody = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Serial Number with scan button
              TextField(
                controller: snCtrl,
                decoration: InputDecoration(
                  labelText: tr('Serial Number *'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.qr_code),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Scan barcode button
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner, color: HrmPageChrome.primaryNavy),
                        tooltip: tr('Quét mã barcode'),
                        onPressed: scanBarcode,
                      ),
                      // Check serial button
                      if (isCheckingSerial)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.search, color: Color(0xFF586064)),
                          tooltip: tr('Kiểm tra Serial'),
                          onPressed: checkSerial,
                        ),
                    ],
                  ),
                  errorText: trN(serialError),
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => checkSerial(),
              ),
              // Success message
              if (serialSuccess != null) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF059669), size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(tr(serialSuccess!), style: const TextStyle(color: Color(0xFF059669), fontSize: 13, fontWeight: FontWeight.w500))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: tr('Tên thiết bị *'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.devices),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: locationCtrl,
                decoration: InputDecoration(
                  labelText: tr('Vị trí lắp đặt'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: tr('Mô tả'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.description),
                ),
              ),
            ],
          );

          if (isMobileDialog) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(tr('Thêm máy chấm công')),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx, false)),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton(
                        onPressed: isCheckingSerial ? null : submitDevice,
                        child: Text(tr('Thêm')),
                      ),
                    ),
                  ],
                ),
                body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formBody),
              ),
            );
          }

          return ScrollableAlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.add_circle, color: HrmPageChrome.primaryNavy),
                SizedBox(width: 8),
                Text(tr('Thêm máy chấm công')),
              ],
            ),
            content: SizedBox(
              width: math.min(420, MediaQuery.of(ctx).size.width - 32).toDouble(),
              child: SingleChildScrollView(child: formBody),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
              FilledButton(
                onPressed: isCheckingSerial ? null : submitDevice,
                child: Text(tr('Thêm')),
              ),
            ],
          );
        },
      ),
    );

    snCtrl.dispose();
    nameCtrl.dispose();
    locationCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _deleteDevice(Map<String, dynamic> device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Xóa thiết bị')),
        content: Text(tr('${tr('Bạn có chắc muốn xóa "')}${device['deviceName']}"?\nHành động này không thể hoàn tác.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await _apiService.deleteDevice(device['id'].toString());
    if (!mounted) return;
    if (result['success'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Thành công', message: tr('Đã xóa thiết bị'));
      _loadDevices();
    } else {
      final msg = result['message'] ?? 'Xóa thất bại';
      NotificationOverlayManager().showError(title: 'Lỗi', message: msg);
    }
  }

  Future<void> _refreshDeviceStatus(Map<String, dynamic> device) async {
    final deviceId = device['id']?.toString();
    if (deviceId == null) return;
    
    NotificationOverlayManager().showInfo(title: 'Cập nhật', message: tr('Đang cập nhật trạng thái...'));
    
    final result = await _apiService.refreshDeviceStatus(deviceId);
    if (!mounted) return;
    
    if (result != null) {
      setState(() {
        device['deviceStatus'] = result['deviceStatus'];
        device['lastOnline'] = result['lastOnline'];
      });
      final isOnline = result['isOnline'] == true;
      if (isOnline) {
        NotificationOverlayManager().showSuccess(title: 'Online', message: tr('Thiết bị đang Online'));
      } else {
        NotificationOverlayManager().showWarning(title: 'Offline', message: tr('Thiết bị đang Offline'));
      }
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: tr('Không thể cập nhật trạng thái'));
    }
  }

  Future<void> _showDeviceDetail(Map<String, dynamic> device) async {
    final deviceId = device['id'].toString();
    Map<String, dynamic>? deviceInfo;
    try {
      deviceInfo = await _apiService.getDeviceInfo(deviceId);
    } catch (e) {
      debugPrint('Load device info error: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => _DeviceDetailDialog(
        device: device,
        deviceInfo: deviceInfo,
        isOnline: _isOnline(device),
        onCommand: (cmdType, label) => _sendCommand(device, cmdType, label),
        onRename: () {
          Navigator.pop(ctx);
          _showRenameDialog(device);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _deleteDevice(device);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDevices,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: HrmSettingsMobileKit.active(context)
                    ? HrmSettingsMobileKit.pagePadding(context)
                    : EdgeInsets.all(Responsive.isMobile(context) ? 12 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildSetupGuideCard(),
                    const SizedBox(height: 20),
                    _buildSummaryCards(),
                    const SizedBox(height: 20),
                    
                    _buildToolbar(),
                    const SizedBox(height: 16),
                    _buildDeviceGrid(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final embedded = HrmPageChrome.isEmbedded;
    final isMobile = Responsive.isMobile(context);
    final embeddedMobile = HrmSettingsMobileKit.active(context);

    if (embedded) {
      if (!_perm.canCreate('Device')) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerRight,
        child: HrmSettingsAddButton(
          label: 'Thêm thiết bị',
          compact: embeddedMobile,
          onPressed: _showAddDeviceDialog,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), HrmPageChrome.primaryNavy, HrmPageChrome.primaryNavy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.router, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Kết nối máy chấm công'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 6),
                Text(tr('Quản lý danh sách máy chấm công, theo dõi trạng thái kết nối và điều khiển từ xa'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.8), height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_perm.canCreate('Device'))
            Responsive.isMobile(context)
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _showAddDeviceDialog,
                        icon: const Icon(Icons.add_circle, size: 28),
                        color: Colors.white,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  )
                : FilledButton.icon(
                    onPressed: _showAddDeviceDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr('Thêm thiết bị')),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                  ),
        ],
      ),
    );
  }

  Widget _buildSetupGuideCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Hướng dẫn cấu hình máy chấm công'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  tr(DeviceSetupGuide.summary),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF1E40AF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final cards = [
      _buildStatCard('Tổng thiết bị', _totalCount, Icons.devices, HrmPageChrome.primaryNavy),
      _buildStatCard('Đang online', _onlineCount, Icons.wifi, HrmPageChrome.primaryNavy),
      _buildStatCard('Offline', _offlineCount, Icons.wifi_off, const Color(0xFFEF4444)),
    ];
    if (Responsive.isMobile(context)) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: Responsive.horizontalScrollPadding,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              SizedBox(width: 140, child: cards[i]),
            ],
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 14),
        Expanded(child: cards[1]),
        const SizedBox(width: 14),
        Expanded(child: cards[2]),
      ],
    );
  }

  Widget _buildStatCard(String label, int count, IconData icon, Color color) {
    return HrmStatSummaryCard(
      icon: icon,
      value: '$count',
      label: label,
      color: color,
      valueFontSize: Responsive.isMobile(context) ? 18 : 22,
    );
  }

  Widget _buildToolbar() {
    final isMobile = Responsive.isMobile(context);
    final searchField = TextField(
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        hintText: tr('Tìm theo tên, SN, vị trí, IP...'),
        prefixIcon: const Icon(Icons.search, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
      ),
    );
    final filterChips = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFilterChip('Tất cả', 'all', _totalCount),
          _buildFilterChip('Online', 'online', _onlineCount),
          _buildFilterChip('Offline', 'offline', _offlineCount),
        ],
      ),
    );
    return isMobile
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            searchField,
            const SizedBox(height: 8),
            filterChips,
          ],
        )
      : Row(
          children: [
            Expanded(flex: 3, child: searchField),
            const SizedBox(width: 12),
            filterChips,
            const SizedBox(width: 12),
          ],
        );
  }

  Widget _buildFilterChip(String label, String value, int count) {
    final isActive = _statusFilter == value;
    final color = value == 'online' ? HrmPageChrome.primaryNavy : value == 'offline' ? const Color(0xFFEF4444) : HrmPageChrome.primaryNavy;
    return InkWell(
      onTap: () => setState(() => _statusFilter = value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr(label), style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500, color: isActive ? color : const Color(0xFF71717A))),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: isActive ? color.withValues(alpha: 0.15) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
              child: Text(tr('$count'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? color : const Color(0xFFA1A1AA))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceGrid() {
    final devices = _filteredDevices;
    if (devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              Icon(Icons.devices_other, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                tr(_devices.isEmpty ? 'Chưa có máy chấm công nào' : 'Không tìm thấy thiết bị phù hợp'),
                style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
              ),
              if (_devices.isEmpty) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _showAddDeviceDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Thêm máy chấm công đầu tiên')),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (HrmSettingsMobileKit.active(context)) {
      return HrmSettingsEntityGrid(
        itemCount: devices.length,
        columns: 2,
        childAspectRatio: 1.35,
        itemBuilder: (context, i) {
          final device = devices[i];
          final online = _isOnline(device);
          final statusColor =
              online ? HrmPageChrome.primaryNavy : const Color(0xFFEF4444);
          return HrmSettingsEntityTile(
            title: device['deviceName'] ?? 'Không tên',
            subtitle: device['serialNumber']?.toString(),
            meta: device['ipAddress']?.toString(),
            icon: Icons.fingerprint,
            iconColor: statusColor,
            badge: online ? 'Online' : 'Offline',
            badgeColor: online ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
            onTap: () => _showDeviceDetail(device),
          );
        },
      );
    }

    if (Responsive.isMobile(context)) {
      return Column(
        children: List.generate(devices.length, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 12, right: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildDeviceDeckItem(devices[i]),
          ),
        )),
      );
    }

    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: devices.map((d) => _buildDeviceCard(d)).toList(),
    );
  }

  Widget _buildDeviceDeckItem(Map<String, dynamic> device) {
    final online = _isOnline(device);
    final statusColor = online ? HrmPageChrome.primaryNavy : const Color(0xFFEF4444);
    final deviceName = device['deviceName'] ?? 'Không tên';
    final serialNumber = device['serialNumber'] ?? '';
    final ipAddress = device['ipAddress'] ?? '—';

    return InkWell(
      onTap: () => _showDeviceDetail(device),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Stack(children: [
              Center(child: Icon(Icons.fingerprint, color: statusColor, size: 18)),
              Positioned(right: 4, top: 4, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: online ? Colors.green : Colors.red, shape: BoxShape.circle))),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(deviceName), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                tr([serialNumber, ipAddress].join(' · ')),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: online ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(tr(online ? 'Online' : 'Offline'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: online ? Colors.green : Colors.red)),
          ),
        ]),
      ),
    );
  }

  Widget _buildDeviceCard(Map<String, dynamic> device) {
    final online = _isOnline(device);
    final statusColor = online ? HrmPageChrome.primaryNavy : const Color(0xFFEF4444);
    final deviceName = device['deviceName'] ?? 'Không tên';
    final serialNumber = device['serialNumber'] ?? '';
    final location = device['location'] ?? 'Chưa thiết lập';
    final ipAddress = device['ipAddress'] ?? '—';

    String lastOnlineText = 'Chưa kết nối';
    final lo = device['lastOnline'];
    if (lo != null) {
      try {
        final raw = lo.toString();
        final dateStr = (raw.contains('Z') || raw.contains('+')) ? raw : '${raw}Z';
        final dt = DateTime.parse(dateStr);
        final diff = DateTime.now().toUtc().difference(dt);
        if (diff.inMinutes < 1) {
          lastOnlineText = 'Vừa xong';
        } else if (diff.inMinutes < 60) {
          lastOnlineText = '${diff.inMinutes} phút trước';
        } else if (diff.inHours < 24) {
          lastOnlineText = '${diff.inHours} giờ trước';
        } else {
          lastOnlineText = '${diff.inDays} ngày trước';
        }
      } catch (_) {}
    }

    final isMobile = Responsive.isMobile(context);

    return SizedBox(
      width: isMobile ? double.infinity : 340,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _showDeviceDetail(device),
          borderRadius: BorderRadius.circular(16),
          hoverColor: const Color(0xFFF8F9FC),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE4E4E7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: icon + name + status
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [statusColor, statusColor.withValues(alpha: 0.7)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.fingerprint, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(deviceName), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(tr('SN: $serialNumber'), style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                        ],
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text(tr(online ? 'Online' : 'Offline'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Info rows
                _buildInfoRow(Icons.location_on_outlined, 'Vị trí', location),
                const SizedBox(height: 6),
                _buildInfoRow(Icons.lan_outlined, 'IP', ipAddress),
                const SizedBox(height: 6),
                _buildInfoRow(Icons.access_time, 'Lần cuối', lastOnlineText),
                const SizedBox(height: 12),
                // Quick action buttons
                Row(
                  children: [
                    Expanded(
                      child: _buildQuickAction(Icons.refresh, 'Cập nhật', const Color(0xFF059669), () => _refreshDeviceStatus(device)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildQuickAction(Icons.info_outline, 'Chi tiết', HrmPageChrome.primaryNavy, () => _showDeviceDetail(device)),
                    ),
                    const SizedBox(width: 8),
                    if (_perm.canEdit('Device'))
                      Expanded(
                        child: _buildQuickAction(
                            Icons.edit_outlined,
                            'Sửa',
                            const Color(0xFFF59E0B),
                            () => _showRenameDialog(device)),
                      ),
                    if (_perm.canEdit('Device') && _perm.canDelete('Device'))
                      const SizedBox(width: 8),
                    if (_perm.canDelete('Device'))
                      Expanded(
                        child: _buildQuickAction(
                            Icons.delete_outline,
                            'Xóa',
                            const Color(0xFFEF4444),
                            () => _deleteDevice(device)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFFA1A1AA)),
        const SizedBox(width: 6),
        Text(tr('$label: '), style: const TextStyle(fontSize: 12, color: Color(0xFFA1A1AA))),
        Expanded(
          child: Text(tr(value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF334155)), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(tr(label), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

// ==================== BARCODE SCANNER DIALOG ====================
class _BarcodeScannerDialog extends StatefulWidget {
  @override
  State<_BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<_BarcodeScannerDialog> {
  MobileScannerController? _scannerController;
  bool _hasScanned = false;
  String? _cameraError;
  bool _showManualInput = false;
  final _manualController = TextEditingController();
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    try {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        formats: [
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.qrCode,
        ],
      );
    } catch (e) {
      _cameraError = 'Không thể khởi tạo camera: $e';
    }
  }

  @override
  void dispose() {
    _scannerController?.stop();
    _scannerController?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Dialog(
      insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 0 : 16)),
      child: SizedBox(
        width: isMobile ? double.infinity : 400,
        height: isMobile ? MediaQuery.of(context).size.height : 460,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: HrmPageChrome.primaryNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tr('Quét mã Barcode / QR'), style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Scanner
            Expanded(
              child: _showManualInput
                  ? _buildManualInput()
                  : (_scannerController != null
                      ? Stack(
                          children: [
                            ClipRRect(
                              child: MobileScanner(
                                controller: _scannerController!,
                                errorBuilder: (context, error) {
                                  return _buildCameraError(
                                    error.errorDetails?.message ?? 'Không thể truy cập camera',
                                  );
                                },
                                onDetect: (capture) {
                                  if (_hasScanned) return;
                                  final barcodes = capture.barcodes;
                                  if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                                    _hasScanned = true;
                                    _scannerController?.stop();
                                    if (mounted) Navigator.pop(context, barcodes.first.rawValue!);
                                  }
                                },
                              ),
                            ),
                            // Scan guide overlay
                            Center(
                              child: Container(
                                width: 260,
                                height: 100,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            // Torch toggle
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  padding: const EdgeInsets.all(10),
                                ),
                                icon: Icon(
                                  _torchOn ? Icons.flash_on : Icons.flash_off,
                                  color: _torchOn ? Colors.amber : Colors.white,
                                  size: 24,
                                ),
                                onPressed: () {
                                  _scannerController?.toggleTorch();
                                  setState(() => _torchOn = !_torchOn);
                                },
                              ),
                            ),
                          ],
                        )
                      : _buildCameraError(_cameraError ?? 'Camera không khả dụng')),
            ),
            // Footer hint
            if (!_showManualInput)
              Container(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Text(tr('Hướng camera vào mã barcode trên máy chấm công'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF586064), fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => setState(() => _showManualInput = true),
                      icon: const Icon(Icons.keyboard, size: 16),
                      label: Text(tr('Nhập thủ công'), style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(tr(message), textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 13)),
            const SizedBox(height: 8),
            Text(tr('Vui lòng kiểm tra:\n• Quyền camera trong trình duyệt\n• Kết nối qua HTTPS hoặc localhost'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF586064), fontSize: 11),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => setState(() => _showManualInput = true),
              icon: const Icon(Icons.keyboard, size: 16),
              label: Text(tr('Nhập mã thủ công')),
              style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualInput() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code, color: HrmPageChrome.primaryNavy, size: 40),
          const SizedBox(height: 12),
          Text(tr('Nhập mã Serial Number'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 16),
          TextField(
            controller: _manualController,
            decoration: InputDecoration(
              hintText: tr('Nhập SN máy chấm công...'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _showManualInput = false),
                child: Text(tr('Quay lại camera')),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  final text = _manualController.text.trim();
                  if (text.isNotEmpty) Navigator.pop(context, text);
                },
                style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy),
                child: Text(tr('Xác nhận')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== DEVICE DETAIL DIALOG ====================
class _DeviceCommandOutcome {
  final bool success;
  final String message;
  final Map<String, dynamic>? refreshedDeviceInfo;
  final bool isSync;
  final bool cancelled;
  final bool disableDoorControl;

  const _DeviceCommandOutcome({
    required this.success,
    required this.message,
    this.refreshedDeviceInfo,
    this.isSync = false,
    this.cancelled = false,
    this.disableDoorControl = false,
  });
}

class _DeviceControlAction {
  final IconData icon;
  final String label;
  final Color color;
  final int commandType;

  const _DeviceControlAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.commandType,
  });
}

class _DeviceDetailDialog extends StatefulWidget {
  final Map<String, dynamic> device;
  final Map<String, dynamic>? deviceInfo;
  final bool isOnline;
  final Future<_DeviceCommandOutcome> Function(int cmdType, String label)
      onCommand;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _DeviceDetailDialog({
    required this.device,
    required this.deviceInfo,
    required this.isOnline,
    required this.onCommand,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_DeviceDetailDialog> createState() => _DeviceDetailDialogState();
}

class _DeviceDetailDialogState extends State<_DeviceDetailDialog> {
  late Map<String, dynamic> _device;
  Map<String, dynamic>? _deviceInfo;
  int? _busyCommandType;
  _DeviceCommandOutcome? _feedback;

  @override
  void initState() {
    super.initState();
    _device = Map<String, dynamic>.from(widget.device);
    _deviceInfo = widget.deviceInfo;
  }

  Future<void> _runCommand(int commandType, String label) async {
    if (_busyCommandType != null) return;
    setState(() {
      _busyCommandType = commandType;
      _feedback = null;
    });

    final outcome = await widget.onCommand(commandType, label);
    if (!mounted) return;

    setState(() {
      _busyCommandType = null;
      if (!outcome.cancelled) {
        _feedback = outcome;
        if (outcome.refreshedDeviceInfo != null) {
          _deviceInfo = outcome.refreshedDeviceInfo;
        }
        if (outcome.disableDoorControl) {
          _device['allowDoorControlUi'] = false;
        }
      }
    });

    if (outcome.cancelled) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(tr(outcome.message)),
        backgroundColor: outcome.success
            ? (outcome.isSync ? const Color(0xFF0284C7) : const Color(0xFF16A34A))
            : const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: outcome.isSync ? 4 : 3),
      ),
    );
  }

  List<_DeviceControlAction> _controlActions(
      bool canEdit, bool canDelete, Map<String, dynamic> device) {
    final allowDoor = device['allowDoorControlUi'] != false;
    final actions = <_DeviceControlAction>[
      if (canEdit)
        const _DeviceControlAction(
          icon: Icons.restart_alt,
          label: 'Khởi động lại',
          color: Color(0xFFF59E0B),
          commandType: 6,
        ),
      if (canDelete)
        const _DeviceControlAction(
          icon: Icons.delete_forever,
          label: 'Xóa toàn bộ dữ liệu',
          color: Color(0xFFEF4444),
          commandType: 5,
        ),
      if (canEdit) ...[
        if (allowDoor) ...[
          const _DeviceControlAction(
            icon: Icons.lock_open,
            label: 'Mở cửa',
            color: HrmPageChrome.primaryNavy,
            commandType: 15,
          ),
          const _DeviceControlAction(
            icon: Icons.lock,
            label: 'Đóng cửa',
            color: Color(0xFFEF4444),
            commandType: 16,
          ),
        ],
        const _DeviceControlAction(
          icon: Icons.sync,
          label: 'Đồng bộ user',
          color: HrmPageChrome.primaryNavy,
          commandType: 8,
        ),
        const _DeviceControlAction(
          icon: Icons.sync_alt,
          label: 'Đồng bộ chấm công',
          color: HrmPageChrome.primaryNavy,
          commandType: 7,
        ),
        const _DeviceControlAction(
          icon: Icons.info_outline,
          label: 'Lấy thông tin',
          color: Color(0xFF71717A),
          commandType: 17,
        ),
      ],
    ];
    return actions;
  }

  Widget _buildFeedbackBanner() {
    final feedback = _feedback;
    if (feedback == null) return const SizedBox.shrink();

    final Color bg;
    final Color fg;
    final IconData icon;
    if (feedback.isSync) {
      bg = const Color(0xFFE0F2FE);
      fg = const Color(0xFF0369A1);
      icon = Icons.cloud_download_outlined;
    } else if (feedback.success) {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
      icon = Icons.check_circle_outline;
    } else {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFB91C1C);
      icon = Icons.error_outline;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(feedback.message),
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(Icons.close, size: 18, color: fg.withValues(alpha: 0.7)),
            onPressed: () => setState(() => _feedback = null),
          ),
        ],
      ),
    );
  }

  Widget _buildControlGrid(List<_DeviceControlAction> actions, bool isMobile) {
    if (actions.isEmpty) return const SizedBox.shrink();

    final crossAxisCount = isMobile ? 2 : 3;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: isMobile ? 1.15 : 1.25,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];
        final isBusy = _busyCommandType == action.commandType;
        final isDisabled = _busyCommandType != null && !isBusy;
        return _buildCommandGridTile(
          icon: action.icon,
          label: action.label,
          color: action.color,
          isBusy: isBusy,
          isDisabled: isDisabled,
          onTap: () => _runCommand(action.commandType, action.label),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canEdit = perm.canEdit('Device');
    final canDelete = perm.canDelete('Device');
    final statusColor =
        widget.isOnline ? HrmPageChrome.primaryNavy : const Color(0xFFEF4444);
    final isMobile = Responsive.isMobile(context);
    final device = _device;
    final deviceInfo = _deviceInfo;
    final controlActions = _controlActions(canEdit, canDelete, device);

    Widget buildContent() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMobile) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [
                          statusColor,
                          statusColor.withValues(alpha: 0.7)
                        ]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.fingerprint,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(device['deviceName'] ?? ''),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A))),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                        color: statusColor,
                                        shape: BoxShape.circle)),
                                const SizedBox(width: 5),
                                Text(
                                    tr(widget.isOnline ? 'Online' : 'Offline'),
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: statusColor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Color(0xFFA1A1AA)),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (isMobile) ...[
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: statusColor, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(tr(widget.isOnline ? 'Online' : 'Offline'),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusColor)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
          ],
          _buildSection('Thông tin thiết bị', Icons.info_outline,
              HrmPageChrome.primaryNavy, [
            _buildDetailRow('Serial Number', device['serialNumber'] ?? '—'),
            _buildDetailRow('Tên thiết bị', device['deviceName'] ?? '—'),
            _buildDetailRow(
                'Vị trí lắp đặt', device['location'] ?? 'Chưa thiết lập'),
            _buildDetailRow('Địa chỉ IP', device['ipAddress'] ?? '—'),
            _buildDetailRow('Mô tả', device['description'] ?? '—'),
            _buildDetailRow('Trạng thái',
                device['isActive'] == true ? 'Hoạt động' : 'Tạm dừng'),
            if (device['engineProfile'] != null)
              _buildDetailRow('Engine profile', '${device['engineProfile']}'),
            if (device['preferStampSync'] == true)
              _buildDetailRow('Đồng bộ',
                  'Stamp/realtime (không QUERY từ máy)'),
            if (device['allowEnrollFingerprintUi'] == false)
              _buildDetailRow('Đăng ký VT từ xa', 'Không hỗ trợ trên máy này'),
            if (device['allowDoorControlUi'] == false)
              _buildDetailRow('Mở/đóng cửa từ xa', 'Không hỗ trợ trên máy này'),
            if (device['capabilityNotes'] != null &&
                '${device['capabilityNotes']}'.trim().isNotEmpty)
              _buildDetailRow('Ghi chú ADMS', '${device['capabilityNotes']}'),
          ]),
          if (deviceInfo != null) ...[
            const SizedBox(height: 16),
            _buildSection('Thông tin kỹ thuật', Icons.memory,
                HrmPageChrome.primaryNavy, [
              _buildDetailRow(
                  'Firmware', deviceInfo['firmwareVersion'] ?? '—'),
              if (deviceInfo['platform'] != null)
                _buildDetailRow('Platform', '${deviceInfo['platform']}'),
              if (deviceInfo['engineProfile'] != null)
                _buildDetailRow(
                    'Engine profile', '${deviceInfo['engineProfile']}'),
              _buildDetailRow('Số user đã đăng ký',
                  '${deviceInfo['enrolledUserCount'] ?? 0}'),
              _buildDetailRow(
                  'Số vân tay', '${deviceInfo['fingerprintCount'] ?? 0}'),
              _buildDetailRow('Số bản chấm công',
                  '${deviceInfo['attendanceCount'] ?? 0}'),
              _buildDetailRow('IP thiết bị', deviceInfo['deviceIp'] ?? '—'),
              if (deviceInfo['faceTemplateCount'] != null)
                _buildDetailRow(
                    'Số khuôn mặt', '${deviceInfo['faceTemplateCount']}'),
              if (deviceInfo['preferStampSync'] == true)
                _buildDetailRow(
                    'Đồng bộ', 'Stamp/realtime (máy pull-deny)'),
              if (deviceInfo['capabilityNotes'] != null)
                _buildDetailRow(
                    'Ghi chú ADMS', '${deviceInfo['capabilityNotes']}'),
            ]),
          ],
          const SizedBox(height: 20),
          _buildSection('Điều khiển thiết bị', Icons.settings_remote,
              const Color(0xFFF59E0B), []),
          const SizedBox(height: 8),
          if (canEdit) _buildControlGrid(controlActions, isMobile),
          _buildFeedbackBanner(),
          if (canEdit || canDelete) const SizedBox(height: 20),
          if (canEdit || canDelete)
            Row(
              children: [
                if (canEdit)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onRename,
                      icon: const Icon(Icons.edit, size: 16),
                      label: Text(tr('Đổi tên / Sửa')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HrmPageChrome.primaryNavy,
                        side: const BorderSide(
                            color: HrmPageChrome.primaryNavy),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                if (canEdit && canDelete) const SizedBox(width: 12),
                if (canDelete)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete, size: 16),
                      label: Text(tr('Xóa thiết bị')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      );
    }

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(tr(device['deviceName'] ?? 'Chi tiết thiết bị')),
            leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: buildContent(),
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: math.min(560, MediaQuery.of(context).size.width - 32).toDouble(),
        constraints: const BoxConstraints(maxHeight: 700),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: buildContent(),
        ),
      ),
    );
  }

  Widget _buildSection(
      String title, IconData icon, Color color, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Text(tr(title),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
        if (children.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
            ),
            child: Column(children: children),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(tr(label),
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF71717A))),
          ),
          Expanded(
            child: Text(tr(value),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF0F172A))),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandGridTile({
    required IconData icon,
    required String label,
    required Color color,
    required bool isBusy,
    required bool isDisabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDisabled
          ? color.withValues(alpha: 0.04)
          : color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isBusy)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: color,
                  ),
                )
              else
                Icon(icon, size: 24, color: isDisabled ? color.withValues(alpha: 0.45) : color),
              const SizedBox(height: 8),
              Text(
                tr(label),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: isDisabled ? color.withValues(alpha: 0.45) : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
