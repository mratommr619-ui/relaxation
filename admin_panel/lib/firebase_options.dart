import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDmC2RD4qvC_qs_l657bL9jVO-ossYHRR8',
    appId: '1:721601893645:web:be3b59dc65bd35a4ce0c44',
    messagingSenderId: '721601893645',
    projectId: 'our-relaxation',
    authDomain: 'our-relaxation.firebaseapp.com',
    storageBucket: 'our-relaxation.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDnUkuEgrUFWOjEcSfeNe7XYm46etFaPoY',
    appId: '1:721601893645:android:085256a843193f74ce0c44',
    messagingSenderId: '721601893645',
    projectId: 'our-relaxation',
    storageBucket: 'our-relaxation.firebasestorage.app',
  );

  static const FirebaseOptions ios = web;
  static const FirebaseOptions macos = web;
}
