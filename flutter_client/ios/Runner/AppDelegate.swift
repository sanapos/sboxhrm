import Flutter
import UIKit
// Force-link TensorFlowLite (Swift wrapper) so dyld eagerly loads the
// underlying TensorFlowLiteC.framework at app launch. tflite_flutter
// uses dlsym(RTLD_DEFAULT, "TfLiteModelCreate") via FFI, which only
// finds symbols in libraries already loaded into the Runner process.
// Without an explicit reference here, the linker dead-strips TFLiteC.
import TensorFlowLite

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Keep a strong reference so the optimizer can't strip the import.
  private static let _tfliteKeepalive: Interpreter.Type = Interpreter.self

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Enable foreground local notifications on iOS
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
