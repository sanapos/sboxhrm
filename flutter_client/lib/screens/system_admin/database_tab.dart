import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'system_admin_helpers.dart';

class DatabaseTab extends StatefulWidget {
  final List<Map<String, dynamic>> stores;

  const DatabaseTab({super.key, this.stores = const []});

  @override
  State<DatabaseTab> createState() => DatabaseTabState();
}

class DatabaseTabState extends State<DatabaseTab> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _dbInfo;
  List<Map<String, dynamic>> _backupFiles = [];
  bool _isLoading = false;
  bool _isBackingUp = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getDatabaseInfo(),
        _apiService.getBackupFiles(),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0]['isSuccess'] == true) _dbInfo = results[0]['data'];
        if (results[1]['isSuccess'] == true) {
          _backupFiles =
              List<Map<String, dynamic>>.from(results[1]['data'] ?? []);
        }
      });
    } catch (e) {
      debugPrint('DatabaseTab error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDbInfoCard(),
          const SizedBox(height: 16),
          _buildBackupSection(),
          const SizedBox(height: 16),
          _buildBackupFilesList(),
          const SizedBox(height: 16),
          _buildDangerZone(),
        ],
      ),
    );
  }

  Widget _buildDbInfoCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration:
          AdminHelpers.cardDecoration(borderColor: AdminHelpers.primary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AdminHelpers.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.storage,
                  color: AdminHelpers.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Thông tin Database',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey[800])),
            const Spacer(),
          ]),
          const SizedBox(height: 16),
          if (_dbInfo != null) ...[
            Wrap(spacing: 20, runSpacing: 12, children: [
              _dbInfoItem(
                  'Database', _dbInfo?['databaseName'] ?? 'N/A', Icons.dns),
              _dbInfoItem(
                  'Host', _dbInfo?['host'] ?? 'N/A', Icons.computer),
              _dbInfoItem('Kích thước', _dbInfo?['size'] ?? 'N/A',
                  Icons.pie_chart),
              _dbInfoItem(
                  'Backups',
                  '${_dbInfo?['backups']?['count'] ?? 0} files (${_dbInfo?['backups']?['totalSizeMB'] ?? 0} MB)',
                  Icons.backup),
            ]),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text('Dữ liệu theo bảng',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.grey[700])),
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 10, children: [
              _dbTableCount(
                  'Cửa hàng', _dbInfo?['tables']?['stores'], Icons.store),
              _dbTableCount('Người dùng', _dbInfo?['tables']?['users'],
                  Icons.people),
              _dbTableCount('Nhân viên', _dbInfo?['tables']?['employees'],
                  Icons.badge),
              _dbTableCount('Thiết bị', _dbInfo?['tables']?['devices'],
                  Icons.router),
              _dbTableCount('Nhân sự máy',
                  _dbInfo?['tables']?['deviceUsers'], Icons.person_pin),
              _dbTableCount('Lệnh máy',
                  _dbInfo?['tables']?['deviceCommands'], Icons.terminal),
              _dbTableCount('Chấm công',
                  _dbInfo?['tables']?['attendanceLogs'], Icons.fingerprint),
              _dbTableCount('Nhật ký', _dbInfo?['tables']?['auditLogs'],
                  Icons.history),
            ]),
          ] else
            const Center(
                child: Text('Đang tải...',
                    style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _dbInfoItem(String label, String value, IconData icon) {
    return SizedBox(
      width: 200,
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[500])),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ]),
        ),
      ]),
    );
  }

  Widget _dbTableCount(String label, dynamic count, IconData icon) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminHelpers.surfaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: AdminHelpers.primary),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style:
                    TextStyle(fontSize: 11, color: Colors.grey[600]))),
        Text('${count ?? 0}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AdminHelpers.primary)),
      ]),
    );
  }

  Widget _buildBackupSection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration:
          AdminHelpers.cardDecoration(borderColor: AdminHelpers.success),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AdminHelpers.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.backup,
                  color: AdminHelpers.success, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Sao lưu dữ liệu',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey[800])),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            ElevatedButton.icon(
              onPressed: _isBackingUp ? null : _performFullBackup,
              icon: _isBackingUp
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload, size: 18),
              label: Text(
                  _isBackingUp ? 'Đang backup...' : 'Backup toàn bộ DB'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12)),
            ),
            OutlinedButton.icon(
              onPressed: _isBackingUp ? null : _showBackupStoreDialog,
              icon: const Icon(Icons.store, size: 18),
              label: const Text('Backup theo cửa hàng'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AdminHelpers.success,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildBackupFilesList() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AdminHelpers.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.folder,
                color: AdminHelpers.primary, size: 20),
            const SizedBox(width: 8),
            Text('File backup (${_backupFiles.length})',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.grey[800])),
            const Spacer(),
          ]),
          const SizedBox(height: 12),
          if (_backupFiles.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                  child: Text('Chưa có file backup',
                      style: TextStyle(color: Colors.grey[500]))),
            )
          else
            ..._backupFiles.map((f) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AdminHelpers.surfaceBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(children: [
                    Icon(
                      f['type'] == 'full'
                          ? Icons.cloud_done
                          : Icons.store,
                      size: 18,
                      color: f['type'] == 'full'
                          ? AdminHelpers.success
                          : AdminHelpers.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f['fileName'] ?? '',
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            Text(
                                '${f['sizeMB'] ?? 0} MB — ${AdminHelpers.formatDateTime(f['createdAt'])}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500])),
                          ]),
                    ),
                    AdminHelpers.statusChip(
                        f['type'] == 'full' ? 'Full' : 'Store',
                        f['type'] == 'full'
                            ? AdminHelpers.success
                            : AdminHelpers.primary),
                    const SizedBox(width: 8),
                    if (f['type'] == 'full')
                      IconButton(
                        icon: const Icon(Icons.restore,
                            size: 18, color: AdminHelpers.warning),
                        tooltip: 'Restore',
                        onPressed: () =>
                            _showRestoreDialog(f['fileName']),
                      ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: Colors.red[300]),
                      tooltip: 'Xóa',
                      onPressed: () =>
                          _deleteBackupFile(f['fileName']),
                    ),
                  ]),
                )),
        ],
      ),
    );
  }

  Widget _buildDangerZone() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration:
          AdminHelpers.cardDecoration(borderColor: AdminHelpers.danger),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.warning_amber,
                  color: Colors.red, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Vùng nguy hiểm',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.red[700])),
          ]),
          const SizedBox(height: 12),
          Text(
              'Các thao tác dưới đây không thể hoàn tác. Hãy chắc chắn đã sao lưu dữ liệu trước khi thực hiện.',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            OutlinedButton.icon(
              onPressed: _showDeleteStoreDataDialog,
              icon: const Icon(Icons.delete_sweep, size: 18),
              label: const Text('Xóa dữ liệu cửa hàng'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12)),
            ),
            OutlinedButton.icon(
              onPressed: _showPurgeAllDialog,
              icon: const Icon(Icons.delete_forever, size: 18),
              label: const Text('Xóa dữ liệu vận hành'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12)),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _performFullBackup() async {
    setState(() => _isBackingUp = true);
    try {
      final res = await _apiService.backupDatabase();
      if (mounted) {
        if (res['isSuccess'] == true) {
          AdminHelpers.showSuccess(context,
              'Backup thành công: ${res['data']?['fileName']} (${res['data']?['sizeMB']}MB)');
          loadData();
        } else {
          AdminHelpers.showError(context,
              'Backup thất bại: ${res['message'] ?? res['errors']?.toString() ?? 'Unknown error'}');
        }
      }
    } catch (e) {
      if (mounted) AdminHelpers.showError(context, 'Lỗi: $e');
    }
    if (mounted) setState(() => _isBackingUp = false);
  }

  void _showBackupStoreDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup dữ liệu cửa hàng'),
        content: SizedBox(
          width: 400,
          child: widget.stores.isEmpty
              ? const Text('Chưa có cửa hàng nào')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Chọn cửa hàng cần backup:',
                        style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    ...widget.stores.take(20).map((s) => ListTile(
                          leading: const Icon(Icons.store,
                              color: AdminHelpers.primary),
                          title: Text(s['name'] ?? 'N/A'),
                          subtitle: Text(s['code'] ?? '',
                              style: const TextStyle(fontSize: 12)),
                          onTap: () async {
                            Navigator.pop(ctx);
                            setState(() => _isBackingUp = true);
                            final res = await _apiService.backupStoreData(
                                s['id']?.toString() ?? '');
                            if (mounted) {
                              if (res['isSuccess'] == true) {
                                AdminHelpers.showSuccess(context,
                                    'Backup cửa hàng ${s['name']} thành công');
                              } else {
                                AdminHelpers.showError(context,
                                    'Backup thất bại: ${res['message'] ?? 'Unknown'}');
                              }
                              loadData();
                            }
                            if (mounted) {
                              setState(() => _isBackingUp = false);
                            }
                          },
                        )),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'))
        ],
      ),
    );
  }

  void _showRestoreDialog(String? fileName) {
    if (fileName == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber, color: Colors.orange[700]),
          const SizedBox(width: 8),
          const Text('Restore Database'),
        ]),
        content: SizedBox(
          width: 420,
          child:
              Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.warning, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'Thao tác này sẽ GHI ĐÈ toàn bộ dữ liệu hiện tại bằng dữ liệu từ file backup. Không thể hoàn tác!',
                        style: TextStyle(fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 12),
            Text('File: $fileName',
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isBackingUp = true);
              final res =
                  await _apiService.restoreDatabase(fileName);
              if (mounted) {
                if (res['isSuccess'] == true) {
                  AdminHelpers.showSuccess(
                      context, 'Restore thành công!');
                } else {
                  AdminHelpers.showError(context,
                      'Restore thất bại: ${res['message'] ?? 'Unknown'}');
                }
              }
              if (mounted) setState(() => _isBackingUp = false);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange),
            child: const Text('Xác nhận Restore'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBackupFile(String? fileName) async {
    if (fileName == null) return;
    final confirm = await AdminHelpers.showConfirmDialog(
        context, 'Xóa file backup', 'Bạn có chắc muốn xóa "$fileName"?');
    if (confirm == true) {
      await _apiService.deleteBackupFile(fileName);
      loadData();
    }
  }

  void _showDeleteStoreDataDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.delete_sweep, color: Colors.red),
          SizedBox(width: 8),
          Text('Xóa dữ liệu cửa hàng'),
        ]),
        content: SizedBox(
          width: 400,
          child: widget.stores.isEmpty
              ? const Text('Chưa có cửa hàng nào')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Row(children: [
                        Icon(Icons.warning,
                            color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                'Sẽ xóa: chấm công, lệnh máy, nhân sự máy, thiết bị, nhân viên của cửa hàng được chọn.',
                                style: TextStyle(fontSize: 13))),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    ...widget.stores.take(20).map((s) => ListTile(
                          leading: const Icon(Icons.store,
                              color: Colors.red),
                          title: Text(s['name'] ?? 'N/A'),
                          subtitle: Text(s['code'] ?? '',
                              style: const TextStyle(fontSize: 12)),
                          onTap: () async {
                            Navigator.pop(ctx);
                            final confirm =
                                await AdminHelpers.showConfirmDialog(
                              context,
                              'Xác nhận xóa dữ liệu',
                              'Bạn có chắc muốn xóa TOÀN BỘ dữ liệu của "${s['name']}"? Thao tác này không thể hoàn tác!',
                            );
                            if (confirm == true) {
                              final res = await _apiService
                                  .deleteStoreData(
                                      s['id']?.toString() ?? '');
                              if (mounted) {
                                if (res['isSuccess'] == true) {
                                  AdminHelpers.showSuccess(context,
                                      'Đã xóa dữ liệu ${s['name']}');
                                } else {
                                  AdminHelpers.showError(context,
                                      'Lỗi: ${res['message'] ?? 'Unknown'}');
                                }
                                loadData();
                              }
                            }
                          },
                        )),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'))
        ],
      ),
    );
  }

  void _showPurgeAllDialog() {
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.delete_forever, color: Colors.red),
          const SizedBox(width: 8),
          Text('Xóa dữ liệu vận hành',
              style: TextStyle(color: Colors.red[700])),
        ]),
        content: SizedBox(
          width: 420,
          child:
              Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Column(children: [
                Row(children: [
                  Icon(Icons.warning, color: Colors.red, size: 24),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'CẢNH BÁO: Thao tác này sẽ xóa dữ liệu chấm công, lệnh máy, nhân sự máy, vân tay, khuôn mặt, thiết bị, nhân viên trên toàn hệ thống!',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.red))),
                ]),
                SizedBox(height: 8),
                Text(
                    'GIỮ NGUYÊN: cửa hàng, tài khoản người dùng, license key, cài đặt. Thao tác KHÔNG THỂ HOÀN TÁC.',
                    style: TextStyle(fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 16),
            const Text(
                'Nhập "CONFIRM_DELETE_ALL" để xác nhận:',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: confirmCtrl,
              decoration: InputDecoration(
                hintText: 'CONFIRM_DELETE_ALL',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                prefixIcon:
                    const Icon(Icons.key, color: Colors.red),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (confirmCtrl.text != 'CONFIRM_DELETE_ALL') {
                AdminHelpers.showError(
                    ctx, 'Mã xác nhận không đúng');
                return;
              }
              Navigator.pop(ctx);
              final res = await _apiService
                  .purgeAllData(confirmCtrl.text);
              if (mounted) {
                if (res['isSuccess'] == true) {
                  AdminHelpers.showSuccess(
                      context, 'Đã xóa dữ liệu vận hành!');
                } else {
                  AdminHelpers.showError(context,
                      'Lỗi: ${res['message'] ?? 'Unknown'}');
                }
                loadData();
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red),
            child: const Text('XÓA DỮ LIỆU'),
          ),
        ],
      ),
    ).then((_) {
      confirmCtrl.dispose();
    });
  }
}
