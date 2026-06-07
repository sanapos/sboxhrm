import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../utils/number_formatter.dart';
import '../widgets/loading_widget.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';

class PenaltySettingsScreen extends StatefulWidget {
  const PenaltySettingsScreen({super.key});

  @override
  State<PenaltySettingsScreen> createState() => _PenaltySettingsScreenState();
}

class _PenaltySettingsScreenState extends State<PenaltySettingsScreen> {
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  final ApiService _apiService = ApiService();
  final _scrollController = ScrollController();
  bool _isLoading = true;
  bool _isSaving = false;

  final _lateMinutes1Controller = TextEditingController();
  final _latePenalty1Controller = TextEditingController();
  final _lateMinutes2Controller = TextEditingController();
  final _latePenalty2Controller = TextEditingController();
  final _lateMinutes3Controller = TextEditingController();
  final _latePenalty3Controller = TextEditingController();

  final _earlyMinutes1Controller = TextEditingController();
  final _earlyPenalty1Controller = TextEditingController();
  final _earlyMinutes2Controller = TextEditingController();
  final _earlyPenalty2Controller = TextEditingController();
  final _earlyMinutes3Controller = TextEditingController();
  final _earlyPenalty3Controller = TextEditingController();

  final _repeatTimes1Controller = TextEditingController();
  final _repeatPenalty1Controller = TextEditingController();
  final _repeatTimes2Controller = TextEditingController();
  final _repeatPenalty2Controller = TextEditingController();
  final _repeatTimes3Controller = TextEditingController();
  final _repeatPenalty3Controller = TextEditingController();

  final _forgotCheckPenaltyController = TextEditingController();
  final _unauthorizedAbsencePenaltyController = TextEditingController();
  final _violationPenaltyController = TextEditingController();

  static const _bg = Color(0xFFFAFAFA);
  static const _navy = HrmPageChrome.primaryNavy;
  static const _border = Color(0xFFE4E4E7);
  static const _muted = Color(0xFF71717A);

  @override
  void initState() {
    super.initState();
    _loadPenaltySettings();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _lateMinutes1Controller.dispose();
    _latePenalty1Controller.dispose();
    _lateMinutes2Controller.dispose();
    _latePenalty2Controller.dispose();
    _lateMinutes3Controller.dispose();
    _latePenalty3Controller.dispose();
    _earlyMinutes1Controller.dispose();
    _earlyPenalty1Controller.dispose();
    _earlyMinutes2Controller.dispose();
    _earlyPenalty2Controller.dispose();
    _earlyMinutes3Controller.dispose();
    _earlyPenalty3Controller.dispose();
    _repeatTimes1Controller.dispose();
    _repeatPenalty1Controller.dispose();
    _repeatTimes2Controller.dispose();
    _repeatPenalty2Controller.dispose();
    _repeatTimes3Controller.dispose();
    _repeatPenalty3Controller.dispose();
    _forgotCheckPenaltyController.dispose();
    _unauthorizedAbsencePenaltyController.dispose();
    _violationPenaltyController.dispose();
    super.dispose();
  }

  Future<void> _loadPenaltySettings() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getPenaltySettings();
      final settings = (response['isSuccess'] == true &&
              response['data'] is Map<String, dynamic>)
          ? response['data'] as Map<String, dynamic>
          : response;
      if (response['isSuccess'] == true) {
        _populateControllers(settings);
      } else {
        debugPrint('Penalty settings API not successful, using defaults');
      }
    } catch (e) {
      debugPrint('Error loading penalty settings: $e');
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: 'Không thể tải thiết lập phạt, đang dùng giá trị mặc định',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateControllers(Map<String, dynamic> settings) {
    _lateMinutes1Controller.text = (settings['lateMinutes1'] ?? 15).toString();
    _latePenalty1Controller.text = formatNumber(settings['latePenalty1'] ?? 50000);
    _lateMinutes2Controller.text = (settings['lateMinutes2'] ?? 30).toString();
    _latePenalty2Controller.text = formatNumber(settings['latePenalty2'] ?? 100000);
    _lateMinutes3Controller.text = (settings['lateMinutes3'] ?? 60).toString();
    _latePenalty3Controller.text = formatNumber(settings['latePenalty3'] ?? 200000);

    _earlyMinutes1Controller.text = (settings['earlyMinutes1'] ?? 15).toString();
    _earlyPenalty1Controller.text = formatNumber(settings['earlyPenalty1'] ?? 50000);
    _earlyMinutes2Controller.text = (settings['earlyMinutes2'] ?? 30).toString();
    _earlyPenalty2Controller.text = formatNumber(settings['earlyPenalty2'] ?? 100000);
    _earlyMinutes3Controller.text = (settings['earlyMinutes3'] ?? 60).toString();
    _earlyPenalty3Controller.text = formatNumber(settings['earlyPenalty3'] ?? 200000);

    _repeatTimes1Controller.text = (settings['repeatCount1'] ?? 3).toString();
    _repeatPenalty1Controller.text = formatNumber(settings['repeatPenalty1'] ?? 100000);
    _repeatTimes2Controller.text = (settings['repeatCount2'] ?? 5).toString();
    _repeatPenalty2Controller.text = formatNumber(settings['repeatPenalty2'] ?? 200000);
    _repeatTimes3Controller.text = (settings['repeatCount3'] ?? 10).toString();
    _repeatPenalty3Controller.text = formatNumber(settings['repeatPenalty3'] ?? 500000);

    _forgotCheckPenaltyController.text =
        formatNumber(settings['forgotCheckPenalty'] ?? 100000);
    _unauthorizedAbsencePenaltyController.text =
        formatNumber(settings['unauthorizedLeavePenalty'] ?? 500000);
    _violationPenaltyController.text =
        formatNumber(settings['violationPenalty'] ?? 200000);
  }

  Future<void> _savePenaltySettings() async {
    setState(() => _isSaving = true);
    try {
      final data = {
        'lateMinutes1': int.tryParse(_lateMinutes1Controller.text) ?? 15,
        'latePenalty1':
            parseFormattedNumber(_latePenalty1Controller.text)?.toDouble() ?? 50000,
        'lateMinutes2': int.tryParse(_lateMinutes2Controller.text) ?? 30,
        'latePenalty2':
            parseFormattedNumber(_latePenalty2Controller.text)?.toDouble() ?? 100000,
        'lateMinutes3': int.tryParse(_lateMinutes3Controller.text) ?? 60,
        'latePenalty3':
            parseFormattedNumber(_latePenalty3Controller.text)?.toDouble() ?? 200000,
        'earlyMinutes1': int.tryParse(_earlyMinutes1Controller.text) ?? 15,
        'earlyPenalty1':
            parseFormattedNumber(_earlyPenalty1Controller.text)?.toDouble() ?? 50000,
        'earlyMinutes2': int.tryParse(_earlyMinutes2Controller.text) ?? 30,
        'earlyPenalty2':
            parseFormattedNumber(_earlyPenalty2Controller.text)?.toDouble() ?? 100000,
        'earlyMinutes3': int.tryParse(_earlyMinutes3Controller.text) ?? 60,
        'earlyPenalty3':
            parseFormattedNumber(_earlyPenalty3Controller.text)?.toDouble() ?? 200000,
        'repeatCount1': int.tryParse(_repeatTimes1Controller.text) ?? 3,
        'repeatPenalty1':
            parseFormattedNumber(_repeatPenalty1Controller.text)?.toDouble() ?? 100000,
        'repeatCount2': int.tryParse(_repeatTimes2Controller.text) ?? 5,
        'repeatPenalty2':
            parseFormattedNumber(_repeatPenalty2Controller.text)?.toDouble() ?? 200000,
        'repeatCount3': int.tryParse(_repeatTimes3Controller.text) ?? 10,
        'repeatPenalty3':
            parseFormattedNumber(_repeatPenalty3Controller.text)?.toDouble() ?? 500000,
        'forgotCheckPenalty':
            parseFormattedNumber(_forgotCheckPenaltyController.text)?.toDouble() ??
                100000,
        'unauthorizedLeavePenalty': parseFormattedNumber(
                    _unauthorizedAbsencePenaltyController.text)
                ?.toDouble() ??
            500000,
        'violationPenalty':
            parseFormattedNumber(_violationPenaltyController.text)?.toDouble() ??
                200000,
      };

      final response = await _apiService.savePenaltySettings(data);
      if (!mounted) return;
      if (response['isSuccess'] == true) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: 'Đã lưu thiết lập phạt',
        );
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: response['message'] ?? 'Lỗi khi lưu thiết lập',
        );
      }
    } catch (e) {
      debugPrint('Error saving penalty settings: $e');
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: 'Không thể lưu thiết lập: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _scrollFieldIntoView(BuildContext fieldContext) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        fieldContext,
        alignment: 0.25,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: LoadingWidget(),
      );
    }

    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      appBar: (!HrmPageChrome.isEmbedded && isMobile)
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: const Text(
                'Thiết lập Phạt',
                style: TextStyle(
                  color: Color(0xFF18181B),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            )
          : null,
      body: _buildScrollBody(context),
    );
  }

  Widget _buildScrollBody(BuildContext context) {
    final pad = Responsive.isMobile(context) ? 12.0 : 20.0;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    // LayoutBuilder + SizedBox.expand: đảm bảo vùng cuộn có chiều cao cố định
    // (tránh ColoredBox/IntrinsicHeight khiến có thanh cuộn nhưng không lăn được).
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding:
                EdgeInsets.fromLTRB(pad, pad, pad, pad + bottomInset + 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight > 0
                    ? constraints.maxHeight - pad * 2
                    : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (HrmPageChrome.isEmbedded) ...[
                    _buildSaveSettingsButton(context),
                    const SizedBox(height: 16),
                  ] else ...[
                    _buildTitleSection(context),
                    const SizedBox(height: 16),
                  ],
                  _buildCardsLayout(context),
                  if (!HrmPageChrome.isEmbedded) ...[
                    const SizedBox(height: 16),
                    _buildSaveSettingsButton(context),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Tối đa 2 cột — tránh 4 cột hẹp làm hàng nhập tiền bị cắt.
  Widget _buildCardsLayout(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final twoCols = w >= 720;
    final gap = 16.0;

    final cards = [
      _buildLatePenaltyCard(),
      _buildEarlyLeavePenaltyCard(),
      _buildRepeatOffensePenaltyCard(),
      _buildOtherPenaltiesCard(),
    ];

    if (!twoCols) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            cards[i],
          ],
        ],
      );
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            SizedBox(width: gap),
            Expanded(child: cards[1]),
          ],
        ),
        SizedBox(height: gap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[2]),
            SizedBox(width: gap),
            Expanded(child: cards[3]),
          ],
        ),
      ],
    );
  }

  Widget _buildSaveSettingsButton(BuildContext context) {
    if (!_perm.canEdit('PenaltySetup')) return const SizedBox.shrink();
    final isNarrow = MediaQuery.sizeOf(context).width < 560;
    return SizedBox(
      width: isNarrow ? double.infinity : null,
      child: FilledButton.icon(
        onPressed: _isSaving ? null : _savePenaltySettings,
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.save, size: 18),
        label: Text(_isSaving ? 'Đang lưu...' : 'Lưu thiết lập'),
        style: FilledButton.styleFrom(
          backgroundColor: HrmPageChrome.primaryNavy,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildTitleSection(BuildContext context) {
    final intro = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _navy.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.gavel, color: _navy, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!HrmPageChrome.isEmbedded)
                const Text(
                  'Thiết lập Phạt',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (!HrmPageChrome.isEmbedded) const SizedBox(height: 4),
              const Text(
                'Cấu hình mức phạt đi trễ, về sớm, tái phạm và các vi phạm khác',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _muted, fontSize: 14, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: intro,
    );
  }

  Widget _buildSectionCard({
    required Widget header,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const Divider(color: _border, height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildCardHeader({
    required List<Color> gradient,
    required IconData icon,
    required String title,
    required String subtitle,
    Color? iconBg,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: iconBg == null
                  ? LinearGradient(colors: gradient)
                  : null,
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor ?? Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF18181B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: _muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatePenaltyCard() {
    return _buildSectionCard(
      header: _buildCardHeader(
        gradient: const [Color(0xFFEF4444), Color(0xFFF87171)],
        icon: Icons.schedule,
        title: 'Phạt đi trễ',
        subtitle: 'Mức phạt theo số phút đi trễ',
      ),
      children: [
        _buildPenaltyLevelRow(
          level: 1,
          thresholdLabel: 'Từ (phút)',
          minutesController: _lateMinutes1Controller,
          penaltyController: _latePenalty1Controller,
        ),
        _buildPenaltyLevelRow(
          level: 2,
          thresholdLabel: 'Từ (phút)',
          minutesController: _lateMinutes2Controller,
          penaltyController: _latePenalty2Controller,
        ),
        _buildPenaltyLevelRow(
          level: 3,
          thresholdLabel: 'Từ (phút)',
          minutesController: _lateMinutes3Controller,
          penaltyController: _latePenalty3Controller,
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildEarlyLeavePenaltyCard() {
    return _buildSectionCard(
      header: _buildCardHeader(
        gradient: const [HrmPageChrome.primaryNavy, Color(0xFF2D5F8B)],
        icon: Icons.logout,
        title: 'Phạt về sớm',
        subtitle: 'Mức phạt theo số phút về sớm',
      ),
      children: [
        _buildPenaltyLevelRow(
          level: 1,
          thresholdLabel: 'Từ (phút)',
          minutesController: _earlyMinutes1Controller,
          penaltyController: _earlyPenalty1Controller,
        ),
        _buildPenaltyLevelRow(
          level: 2,
          thresholdLabel: 'Từ (phút)',
          minutesController: _earlyMinutes2Controller,
          penaltyController: _earlyPenalty2Controller,
        ),
        _buildPenaltyLevelRow(
          level: 3,
          thresholdLabel: 'Từ (phút)',
          minutesController: _earlyMinutes3Controller,
          penaltyController: _earlyPenalty3Controller,
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildRepeatOffensePenaltyCard() {
    return _buildSectionCard(
      header: _buildCardHeader(
        gradient: const [Color(0xFFFEF3C7), Color(0xFFFEF3C7)],
        icon: Icons.refresh,
        title: 'Phạt tái phạm',
        subtitle: 'Phạt thêm khi vi phạm nhiều lần trong tháng',
        iconBg: const Color(0xFFFEF3C7),
        iconColor: const Color(0xFFF59E0B),
      ),
      children: [
        _buildPenaltyLevelRow(
          level: 1,
          thresholdLabel: 'Từ (lần)',
          minutesController: _repeatTimes1Controller,
          penaltyController: _repeatPenalty1Controller,
          isTimes: true,
        ),
        _buildPenaltyLevelRow(
          level: 2,
          thresholdLabel: 'Từ (lần)',
          minutesController: _repeatTimes2Controller,
          penaltyController: _repeatPenalty2Controller,
          isTimes: true,
        ),
        _buildPenaltyLevelRow(
          level: 3,
          thresholdLabel: 'Từ (lần)',
          minutesController: _repeatTimes3Controller,
          penaltyController: _repeatPenalty3Controller,
          isTimes: true,
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildOtherPenaltiesCard() {
    return _buildSectionCard(
      header: _buildCardHeader(
        gradient: const [Color(0xFFEF4444), Color(0xFFF97316)],
        icon: Icons.warning_amber_rounded,
        title: 'Các loại phạt khác',
        subtitle: 'Quên chấm công, nghỉ không phép, vi phạm nội quy',
      ),
      children: [
        _buildOtherPenaltyRow(
          icon: Icons.fingerprint,
          iconColor: const Color(0xFFF59E0B),
          title: 'Quên chấm công',
          description: 'Không chấm công vào hoặc ra',
          controller: _forgotCheckPenaltyController,
          suffix: 'đ / lần',
        ),
        _buildOtherPenaltyRow(
          icon: Icons.event_busy,
          iconColor: _navy,
          title: 'Nghỉ không phép',
          description: 'Nghỉ không xin phép hoặc không thông báo',
          controller: _unauthorizedAbsencePenaltyController,
          suffix: 'đ / ngày',
        ),
        _buildOtherPenaltyRow(
          icon: Icons.rule,
          iconColor: HrmPageChrome.primaryNavy,
          title: 'Vi phạm quy định công ty',
          description: 'Vi phạm các quy định nội bộ công ty',
          controller: _violationPenaltyController,
          suffix: 'đ / lần',
          isLast: true,
        ),
      ],
    );
  }

  Color _levelColor(int level) {
    return level == 3 ? const Color(0xFFEF4444) : _navy;
  }

  /// Mỗi mức: nhãn + 2 ô nhập full-width (hoặc 2 cột khi card đủ rộng).
  Widget _buildPenaltyLevelRow({
    required int level,
    required String thresholdLabel,
    required TextEditingController minutesController,
    required TextEditingController penaltyController,
    bool isTimes = false,
    bool isLast = false,
  }) {
    final color = _levelColor(level);

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 380;

        Widget thresholdField = _labeledField(
          context: context,
          label: thresholdLabel,
          controller: minutesController,
          isMoney: false,
          hint: isTimes ? '3' : '15',
        );

        Widget moneyField = _labeledField(
          context: context,
          label: 'Mức phạt (VNĐ)',
          controller: penaltyController,
          isMoney: true,
          hint: '50.000',
        );

        final fields = sideBySide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: thresholdField),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: moneyField),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  thresholdField,
                  const SizedBox(height: 10),
                  moneyField,
                ],
              );

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'MỨC $level',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              fields,
            ],
          ),
        );
      },
    );
  }

  Widget _buildOtherPenaltyRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required TextEditingController controller,
    required String suffix,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF18181B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 12, color: _muted, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (fieldContext) => _labeledField(
              context: fieldContext,
              label: 'Mức phạt — $suffix',
              controller: controller,
              isMoney: true,
              hint: '100.000',
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledField({
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    required bool isMoney,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _muted,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: isMoney ? [ThousandSeparatorFormatter()] : null,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          onTap: () => _scrollFieldIntoView(context),
          style: const TextStyle(
            color: Color(0xFF18181B),
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 14),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _navy, width: 2),
            ),
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
