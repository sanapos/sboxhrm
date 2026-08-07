class GlobalLocationReporter {
  static final GlobalLocationReporter instance = GlobalLocationReporter._();
  GlobalLocationReporter._();
  Future<void> start() async {}
  Future<void> stop() async {}
  Future<void> syncNow() async {}
  Future<void> startIfEligible({String? employeeId, dynamic user}) async {}
}
