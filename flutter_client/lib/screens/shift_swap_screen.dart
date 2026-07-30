import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../utils/navigation_notifier.dart';
import '../widgets/hrm_fab_clearance.dart';
import '../widgets/page_top_actions.dart';
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
    return RegisterPageTopActions(
      actions: [
        if (canCreateSwap)
          HrmTopBarAction(
            icon: Icons.add,
            label: 'Yêu cầu đổi ca',
            primary: true,
            showLabel: true,
            onPressed: () => _panelKey.currentState?.showCreateDialog(),
          ),
      ],
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        body: HrmFabClearance(
          fabVisible: false,
          child: ShiftSwapPanel(key: _panelKey),
        ),
      ),
    );
  }
}
