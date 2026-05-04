import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Firebase is initialized from Dart via Firebase.initializeApp(options: DefaultFirebaseOptions...)
    // in FcmService.initialize(). Do NOT call FirebaseApp.configure() here — it would
    // look for GoogleService-Info.plist which is not bundled (we use programmatic options).
    // Enable foreground local notifications on iOS
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register the native (CoreML + Vision) face embedder channel so Dart
    // can call it via MethodChannel('sana/native_face_embedder').
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeFaceEmbedder") {
      NativeFaceEmbedder.register(with: registrar)
    }
  }
}
