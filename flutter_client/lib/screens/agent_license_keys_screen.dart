import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';

class AgentLicenseKeysScreen extends StatefulWidget {
  const AgentLicenseKeysScreen({super.key});

  @override
  State<AgentLicenseKeysScreen> createState() => _AgentLicenseKeysScreenState();
}

class _AgentLicenseKeysScreenState extends State<AgentLicenseKeysScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _keys = [];
  Map<String, dynamic>? _profile;
  bool _isLoading = false;
  int _page = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  int _pageSize = 20;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  // Filters
  String? _filterUsed; // null=all, 'true'=used, 'false'=available
  String? _filterType;
  final TextEditingController _searchCtrl = TextEditingController();

  // Mobile UI state
  bool _showMobileFilters = false;

  static const _primary = Color(0xFF1E3A5F);
  static const _success = Color(0xFF22C55E);
  static const _danger = Color(0xFFEF4444);
  static const _warning = Color(0xFFF59E0B);
  static const _info = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getAgentProfile(),
        _apiService.getAgentMyLicenses(
          page: _page,
          pageSize: _pageSize,
          isUsed: _filterUsed == null ? null : _filterUsed == 'true',
          licenseType: _filterType,
          search: _searchCtrl.text.isNotEmpty ? _searchCtrl.text : null,
        ),
      ]);

      if (!mounted) return;

      if (results[0]['isSuccess'] == true) {
        setState(() => _profile = results[0]['data']);
      }

      if (results[1]['isSuccess'] == true) {
        final data = results[1]['data'];
        setState(() {
          _keys = _extractList(data?['items'] ?? data);
          _totalCount = data?['totalCount'] ?? _keys.length;
          _totalPages = data?['totalPages'] ?? 1;
        });
      } else {
        _showError(results[1]['message'] ?? 'Lỗi tải dữ liệu');
      }
    } catch (e) {
      debugPrint('AgentLicenseKeys error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data is List) return data.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
    return [];
  }

  void _showError(String msg) {
    if (!mounted) return;
    NotificationOverlayManager().showError(title: 'Lỗi', message: msg);
  }

  void _applyFilter() {
    _page = 1;
    _loadData();
  }

  void _copyKey(String key) {
    Clipboard.setData(ClipboardData(text: key));
    NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã copy license key');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(),
          if (!Responsive.isMobile(context) || _showMobileFilters) _buildFilters(),
          Expanded(
            child: _isLoading && _keys.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _keys.isEmpty
                    ? _buildEmpty()
                    : _buildKeyList(),
          ),
          if (_totalPages > 1 && !Responsive.isMobile(context)) _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final total = _profile?['totalKeys'] ?? _totalCount;
    final used = _profile?['usedKeys'] ?? 0;
    final available = _profile?['availableKeys'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.vpn_key, color: _primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('License Keys được cấp',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (_profile != null)
                    Text('Đại lý: ${_profile!['name'] ?? ''} (${_profile!['code'] ?? ''})',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            ),
            if (Responsive.isMobile(context))
              IconButton(
                onPressed: () => setState(() => _showMobileFilters = !_showMobileFilters),
                icon: Stack(
                  children: [
                    Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, size: 20, color: _primary),
                    if (_filterUsed != null || _filterType != null || _searchCtrl.text.isNotEmpty)
                      Positioned(right: 0, top: 0, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle))),
                  ],
                ),
                tooltip: 'Bộ lọc',
              ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 8, children: [
            _statChip('Tổng', total, _primary),
            _statChip('Đã dùng', used, _warning),
            _statChip('Còn trống', available, _success),
          ]),
        ],
      ),
    );
  }

  Widget _statChip(String label, dynamic value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$value', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ]),
    );
  }

  Widget _buildFilters() {
    final isMobile = Responsive.isMobile(context);
    final searchField = SizedBox(
      width: isMobile ? double.infinity : 250,
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Tìm key, store, ghi chú...',
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () { _searchCtrl.clear(); _applyFilter(); },
                )
              : null,
        ),
        onSubmitted: (_) => _applyFilter(),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: Colors.white,
      child: isMobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  _filterDropdown(
                    value: _filterUsed,
                    hint: 'Trạng thái',
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Tất cả')),
                      DropdownMenuItem(value: 'false', child: Text('Còn trống')),
                      DropdownMenuItem(value: 'true', child: Text('Đã dùng')),
                    ],
                    onChanged: (v) { _filterUsed = v; _applyFilter(); },
                  ),
                  _filterDropdown(
                    value: _filterType,
                    hint: 'Loại',
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Tất cả')),
                      DropdownMenuItem(value: 'Basic', child: Text('Cơ bản')),
                      DropdownMenuItem(value: 'Advanced', child: Text('Nâng cao')),
                      DropdownMenuItem(value: 'Professional', child: Text('Chuyên nghiệp')),
                    ],
                    onChanged: (v) { _filterType = v; _applyFilter(); },
                  ),
                  Text('$_totalCount keys',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ],
              ),
            ],
          )
        : Row(children: [
            searchField,
            const SizedBox(width: 12),
            _filterDropdown(
              value: _filterUsed,
              hint: 'Trạng thái',
              items: const [
                DropdownMenuItem(value: null, child: Text('Tất cả')),
                DropdownMenuItem(value: 'false', child: Text('Còn trống')),
                DropdownMenuItem(value: 'true', child: Text('Đã dùng')),
              ],
              onChanged: (v) { _filterUsed = v; _applyFilter(); },
            ),
            const SizedBox(width: 12),
            _filterDropdown(
              value: _filterType,
              hint: 'Loại',
              items: const [
                DropdownMenuItem(value: null, child: Text('Tất cả')),
                DropdownMenuItem(value: 'Basic', child: Text('Cơ bản')),
                DropdownMenuItem(value: 'Advanced', child: Text('Nâng cao')),
                DropdownMenuItem(value: 'Professional', child: Text('Chuyên nghiệp')),
              ],
              onChanged: (v) { _filterType = v; _applyFilter(); },
            ),
            const Spacer(),
            Text('$_totalCount keys',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ]),
    );
  }

  Widget _filterDropdown({
    required String? value,
    required String hint,
    required List<DropdownMenuItem<String?>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 13)),
          isDense: true,
          items: items,
          onChanged: onChanged,
          style: TextStyle(fontSize: 13, color: Colors.grey[800]),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.vpn_key_outlined, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text('Chưa có license key nào',
            style: TextStyle(color: Colors.grey[500], fontSize: 15)),
        const SizedBox(height: 6),
        Text('Liên hệ quản trị viên để được cấp key',
            style: TextStyle(color: Colors.grey[400], fontSize: 13)),
      ]),
    );
  }

  Widget _buildKeyList() {
    if (Responsive.isMobile(context)) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _keys.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
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
            child: _buildKeyDeckItem(_keys[i]),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _keys.length,
      itemBuilder: (ctx, i) => _buildKeyCard(_keys[i]),
    );
  }

  Widget _buildKeyDeckItem(Map<String, dynamic> key) {
    final isUsed = key['isUsed'] == true;
    final licenseType = key['licenseType']?.toString() ?? 'Basic';
    final keyStr = key['key']?.toString() ?? '';
    final packageName = key['servicePackageName']?.toString();
    final typeLabel = _licenseLabel(licenseType);
    final typeColor = _getTypeColor(licenseType);

    return InkWell(
      onTap: () => _showKeyDetail(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.vpn_key, color: typeColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(keyStr.length > 20 ? '${keyStr.substring(0, 20)}...' : keyStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                [typeLabel, if (packageName != null) packageName].join(' · '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: isUsed ? Colors.grey.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(isUsed ? 'Đã dùng' : 'Chưa dùng', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isUsed ? Colors.grey : Colors.green)),
          ),
        ]),
      ),
    );
  }

  Widget _buildKeyCard(Map<String, dynamic> key) {
    final isUsed = key['isUsed'] == true;
    final licenseType = key['licenseType']?.toString() ?? 'Basic';
    final keyStr = key['key']?.toString() ?? '';
    final storeName = key['storeName']?.toString();
    final createdAt = key['createdAt']?.toString();
    final maxUsers = key['maxUsers'] ?? 0;
    final maxDevices = key['maxDevices'] ?? 0;
    final durationDays = key['durationDays'] ?? 0;
    final packageName = key['servicePackageName']?.toString();
    final isActive = key['isActive'] != false;

    final typeLabel = _licenseLabel(licenseType);
    final typeColor = _getTypeColor(licenseType);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isUsed ? Colors.grey.shade200 : _success.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showKeyDetail(key),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (isUsed ? _warning : _success).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isUsed ? Icons.check_circle : Icons.vpn_key,
                  color: isUsed ? _warning : _success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              // Key info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(keyStr,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: isActive ? Colors.grey[800] : Colors.grey[400],
                            )),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () => _copyKey(keyStr),
                        tooltip: 'Copy key',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      _tag(typeLabel, typeColor),
                      _tag(isUsed ? 'Đã dùng' : 'Còn trống', isUsed ? _warning : _success),
                      if (!isActive) _tag('Vô hiệu', _danger),
                      if (packageName != null) _tag(packageName, _info),
                    ]),
                    if (storeName != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.store, size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(storeName,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ]),
                    ],
                  ],
                ),
              ),
              // Right side info
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$maxUsers users · $maxDevices TBị',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Text('$durationDays ngày',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  if (createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(_formatDate(createdAt),
                        style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showKeyDetail(Map<String, dynamic> key) {
    final keyStr = key['key']?.toString() ?? '';
    final isUsed = key['isUsed'] == true;
    final licenseType = key['licenseType']?.toString() ?? 'Basic';
    final typeLabel = _licenseLabel(licenseType);
    final storeName = key['storeName']?.toString();
    final activatedAt = key['activatedAt']?.toString();
    final createdAt = key['createdAt']?.toString();
    final maxUsers = key['maxUsers'] ?? 0;
    final maxDevices = key['maxDevices'] ?? 0;
    final durationDays = key['durationDays'] ?? 0;
    final packageName = key['servicePackageName']?.toString();
    final notes = key['notes']?.toString();
    final isMobile = MediaQuery.of(context).size.width < 600;

    const titleRow = Row(children: [
      Icon(Icons.vpn_key, color: _primary, size: 22),
      SizedBox(width: 10),
      Text('Chi tiết License Key', style: TextStyle(fontSize: 16)),
    ]);

    final contentBody = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow(Icons.key, 'Key', keyStr, copyable: true),
        _detailRow(Icons.category, 'Loại', typeLabel),
        _detailRow(Icons.circle, 'Trạng thái', isUsed ? 'Đã sử dụng' : 'Còn trống'),
        _detailRow(Icons.people, 'Max Users', '$maxUsers'),
        _detailRow(Icons.router, 'Max Thiết bị', '$maxDevices'),
        _detailRow(Icons.timer, 'Thời hạn', '$durationDays ngày'),
        if (packageName != null) _detailRow(Icons.inventory_2, 'Gói DV', packageName),
        if (storeName != null) _detailRow(Icons.store, 'Cửa hàng', storeName),
        if (activatedAt != null) _detailRow(Icons.check_circle, 'Kích hoạt', _formatDateTime(activatedAt)),
        if (createdAt != null) _detailRow(Icons.schedule, 'Ngày tạo', _formatDateTime(createdAt)),
        if (notes != null && notes.isNotEmpty) _detailRow(Icons.notes, 'Ghi chú', notes),
      ],
    );

    final actionButtons = [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
      ElevatedButton.icon(
        onPressed: () { _copyKey(keyStr); Navigator.pop(context); },
        icon: const Icon(Icons.copy, size: 16),
        label: const Text('Copy Key'),
      ),
    ];

    if (isMobile) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
                title: const Text('Chi tiết License Key', overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    const SizedBox(height: 16),
                    contentBody,
                  ],
                ),
              ),
              bottomNavigationBar: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: actionButtons,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: titleRow,
          content: SizedBox(
            width: math.min(450, MediaQuery.of(context).size.width - 32).toDouble(),
            child: SingleChildScrollView(child: contentBody),
          ),
          actions: actionButtons,
        ),
      );
    }
  }

  Widget _detailRow(IconData icon, String label, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                fontFamily: copyable ? 'monospace' : null,
              )),
        ),
        if (copyable)
          IconButton(
            icon: const Icon(Icons.copy, size: 14),
            onPressed: () => _copyKey(value),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
      ]),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildPagination() {
    final start = _totalCount > 0 ? (_page - 1) * _pageSize + 1 : 0;
    final end = (_page * _pageSize).clamp(0, _totalCount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text('Hiển thị $start-$end / $_totalCount',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Hiển thị:', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(width: 8),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _pageSize,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() { _pageSize = v; _page = 1; });
                        _loadData();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _page > 1 ? () { setState(() => _page--); _loadData(); } : null,
                visualDensity: VisualDensity.compact,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$_page / $_totalPages',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: _page < _totalPages ? () { setState(() => _page++); _loadData(); } : null,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'basic': return _info;
      case 'advanced': return _primary;
      case 'professional': return _warning;
      default: return _primary;
    }
  }

  String _licenseLabel(String type) {
    switch (type) {
      case 'Basic': return 'Cơ bản';
      case 'Advanced': return 'Nâng cao';
      case 'Professional': return 'Chuyên nghiệp';
      default: return type;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) { return dateStr; }
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return dateStr; }
  }
}
