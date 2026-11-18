import 'package:flutter/widgets.dart';
import 'app/app_shells.dart';
import 'features/boss/boss_shell.dart';
import 'screens/landing_guide_screen.dart';
import 'utils/landing_usage_guide.dart';
import 'utils/landing_usage_guide_hrm.dart';
import 'screens/main_layout.dart';
import 'screens/main_layout_hrm_nav.dart';
import 'screens/overview/overview_entry.dart';
import 'screens/overview/overview_router_screen.dart';
import 'screens/main_layout_nav_hook.dart';
import 'screens/staff/staff_shell.dart';
import 'screens/system_admin_screen.dart' deferred as system_admin;
import 'widgets/deferred_screen.dart';
import 'screens/settings_hub_pages_hrm.dart';
import 'services/biometric_auth.dart';
import 'services/biometric_auth_local.dart';
import 'services/global_location_reporter.dart';
import 'utils/location_reporting.dart';
import 'utils/settings_hub_hrm_hook.dart';
import 'utils/hrm_shell_hooks.dart';
import 'screens/overview/business_overview_hrm_sheets.dart';
import 'utils/hrm_refresh_notifier.dart';
import 'screens/overtime_screen.dart';
import 'screens/hr_finance/hr_finance_hub_screen.dart';
import 'widgets/device_sync_progress_overlay.dart';
import 'app_boot.dart';

/// Điểm vào SBOX HRM / BOSS / Nhân Viên / SBOX POS Android.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Gắn các mục Thiết lập của HRM. Bản SBOX Bán Hàng có điểm vào riêng và không gắn,
  // nên mã chấm công / lương không vào gói (Apple 2.5.19).
  settingsHubHrmPage = hrmSettingsHubPage;
  // Khung màn chính của từng bản app; bản SBOX Bán Hàng (main_pos.dart) không gắn.
  hrmNavItemsHook = hrmNavItems;
  hrmOverviewScreen = () => const OverviewRouterScreen();
  AppShells.hrm = () => const MainLayout();
  AppShells.landingGuide = () => const LandingGuideScreen();
  // Bài hướng dẫn phần HRM (bản SBOX Bán Hàng không gắn).
  hrmGuideBasicSteps = () => hrmBasicSteps;
  hrmGuideAdvancedSteps = () => hrmAdvancedSteps;
  hrmGuideKeywords = () => hrmAllKeywords;
  AppShells.boss = () => const BossShell();
  AppShells.staff = () => const StaffShell();
  AppShells.systemAdmin = (agentMode) => DeferredScreen(
        load: system_admin.loadLibrary,
        builder: () => system_admin.SystemAdminScreen(agentMode: agentMode),
      );
  // Các mảnh HRM mà khung màn chung gọi tới; bản SBOX Bán Hàng không gắn nên không vào gói iOS.
  hrmOvertimePage = () => const OvertimeScreen();
  hrmCashHubScreen = () => const HrFinanceHubScreen(initialTab: HrFinTab.cash);
  hrmShellOverlay = (child) => DeviceSyncProgressOverlay(child: child);
  hrmSuppressPunchPopup = DeviceSyncProgressManager.shouldSuppressAttendancePopup;
  hrmSuppressPunchNotifications =
      () => DeviceSyncProgressManager.shouldSuppressAttendanceNotifications;
  hrmOverviewPeopleSheet = showHrmOverviewPeopleSheet;
  hrmLatePenaltySheet = showHrmLatePenaltySheet;
  hrmOnPunchRefresh = HrmRefresh.scheduleDataRefresh;
  hrmOnMobileDeviceRefresh = () {
    HrmRefresh.refreshMobileAttendanceSettings();
    HrmRefresh.refreshMobileDeviceRegistration();
  };
  biometricAuth = LocalAuthBiometric();
  locationReporter = GlobalLocationReporter.instance;
  await runSbox();
}
