import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../utils/navigation_notifier.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_fab_clearance.dart';
import '../widgets/shift_swap_panel.dart';

/// Màn hình đổi ca làm việc (danh sách + tạo yêu cầu).
class ShiftSwapScreen extends StatefulWidget {
  const ShiftSwapScreen({super.key});

  @override
  State<ShiftSwapScreen> createState() => _ShiftSwapScreenState();
}

class _ShiftSwapScreenState extends State<ShiftSwapScreen> {
  final GlobalKey<ShiftSwapPanelState> _panelKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (NavigationNotifier.takePendingAiOpenCreate('shift_swap')) {
        _panelKey.currentState?.showCreateDialog();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canCreateSwap =
        Provider.of<PermissionProvider>(context, listen: false)
            .canCreate('ShiftSwap');
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: NavigationNotifier.mobileDrawerModuleActive,
            builder: (context, _) {
              if (NavigationNotifier.mobileDrawerModuleActive.value) {
                return const SizedBox.shrink();
              }
              return Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [HrmPageChrome.primaryNavy, Color(0xFF6366F1)],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.swap_horiz,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Đổi ca làm việc',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            Text('Gửi yêu cầu · Phản hồi · Quản lý duyệt',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: HrmFabClearance(
              fabVisible: canCreateSwap,
              extendedFab: true,
              child: ShiftSwapPanel(key: _panelKey),
            ),
          ),
        ],
      ),
      floatingActionButton:
          Provider.of<PermissionProvider>(context, listen: false)
                  .canCreate('ShiftSwap')
              ? FloatingActionButton.extended(
                  onPressed: () => _panelKey.currentState?.showCreateDialog(),
                  backgroundColor: HrmPageChrome.primaryNavy,
                  icon: const Icon(Icons.add),
                  label: const Text('Yêu cầu đổi ca'),
                )
              : null,
    );
  }
}
