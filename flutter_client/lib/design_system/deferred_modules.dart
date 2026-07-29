/// Deferred / lazy-load helpers for heavy Flutter web modules.
///
/// POS Sell is large; prefer loading it only when user opens the module.
/// Full `deferred as` wiring requires route-level split — use this facade
/// when migrating [MainLayout] nav screens to deferred imports.
library;

/// Marker type so call sites stay stable when deferred loading is enabled.
typedef DeferredModuleLoader = Future<void> Function();

/// Placeholder registry — extend when splitting POS / orgchart / dashboard.
abstract final class DeferredModules {
  static Future<void> ensurePosSellReady() async {
    // Currently eager (imported by MainLayout). When switching to
    // `import '...pos_sell_screen.dart' deferred as pos_sell;`, load here:
    // await pos_sell.loadLibrary();
  }
}
