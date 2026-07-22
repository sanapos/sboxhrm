import 'package:web/web.dart' as web;

import 'web_route_parser.dart';

/// Đọc deep link đã lưu trong sessionStorage (index.html ghi trước Flutter bootstrap).
void captureInitialRouteFromStorage() {
  final route = web.window.sessionStorage.getItem('sbox_route');
  if (route == 'login' || route == 'login-app') {
    InitialWebRoute.showLogin = true;
    web.window.sessionStorage.removeItem('sbox_route');
    return;
  }
  if (route == 'forgot-password') {
    InitialWebRoute.showForgotPassword = true;
    web.window.sessionStorage.removeItem('sbox_route');
    return;
  }
  if (route == 'register') {
    InitialWebRoute.showRegister = true;
    final agentCode = web.window.sessionStorage.getItem('sbox_agent_code');
    if (agentCode != null && agentCode.isNotEmpty) {
      InitialWebRoute.queryParams = {
        ...InitialWebRoute.queryParams,
        'agentCode': agentCode,
      };
    }
    web.window.sessionStorage.removeItem('sbox_route');
    // Giữ sbox_agent_code — RegisterScreen đọc và xóa sau khi đăng ký thành công.
    return;
  }
  if (route == 'agent-register') {
    InitialWebRoute.showAgentRegister = true;
    final token = web.window.sessionStorage.getItem('sbox_agent_token');
    if (token != null && token.isNotEmpty) {
      InitialWebRoute.agentRegisterToken = token;
    }
    web.window.sessionStorage.removeItem('sbox_route');
    web.window.sessionStorage.removeItem('sbox_agent_token');
  }
}
