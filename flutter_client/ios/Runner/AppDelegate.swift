import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Firebase natively using GoogleService-Info.plist.
    // This must happen BEFORE any APNs registration callbacks so that
    // Firebase Messaging can capture the APNs token via method swizzling.
    // The Dart-side Firebase.initializeApp() call in FcmService is guarded
    // with Firebase.apps.isEmpty so there is no duplicate-init error.
    FirebaseApp.configure()

    // Enable foreground local notifications on iOS
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    // Explicitly request APNs token registration at launch, before Dart runs.
    // With FlutterImplicitEngineDelegate, plugins register asynchronously, so
    // we cannot rely on firebase_messaging plugin to call this at the right time.
    application.registerForRemoteNotifications()

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

  // Explicitly forward the APNs device token to Firebase Messaging as a safety net.
  // FirebaseApp.configure() enables swizzling which should do this automatically,
  // but the explicit set here guarantees the token is captured.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // Write APNs registration failure to UserDefaults so Dart can read it.
  // Key uses "flutter." prefix so Flutter's shared_preferences plugin can access it.
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    UserDefaults.standard.set(error.localizedDescription, forKey: "flutter.apns_registration_error")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
