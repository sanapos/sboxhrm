class FcmService {
  static final FcmService instance = FcmService._();
  FcmService._();
  Future<void> init() async {}
  Future<void> clear() async {}
  Future<void> syncToken() async {}
  Future<void> unregister() async {}
  Future<void> registerForCurrentUser([dynamic user]) async {}
  Future<void> unregisterForLogout() async {}
}
