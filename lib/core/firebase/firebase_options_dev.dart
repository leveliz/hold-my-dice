import 'package:firebase_core/firebase_core.dart';

/// The dev project. Until `flutterfire configure` has been run for the real
/// dev project these are made-up values, good for the local emulators only
/// (a project id starting with `demo-` never talks to Google).
const devFirebaseOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:web:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-hold-my-dice',
);
