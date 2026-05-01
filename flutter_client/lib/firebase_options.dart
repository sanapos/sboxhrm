// File generated manually from google-services.json + GoogleService-Info.plist.
// Do not edit by hand unless those config files change.
//
// Project: sbox-hrm
// Used by Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web. '
        'Re-run flutterfire configure if web support is needed.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD7Qvsq7SWzxrhYh5MXuf2_W-hpqTwL_Pw',
    appId: '1:653364898689:android:84a64ec3c97e132d9c1680',
    messagingSenderId: '653364898689',
    projectId: 'sbox-hrm',
    storageBucket: 'sbox-hrm.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDZI3qB3cpRiQMLppdALdWmD-oEgS5ykjs',
    appId: '1:653364898689:ios:8340cce3fa53cba39c1680',
    messagingSenderId: '653364898689',
    projectId: 'sbox-hrm',
    storageBucket: 'sbox-hrm.firebasestorage.app',
    iosBundleId: 'vn.sana.sbox',
  );
}
