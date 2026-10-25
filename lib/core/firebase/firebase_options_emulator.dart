import 'package:firebase_core/firebase_core.dart';

/// Made-up values for the local emulators. A project id starting with `demo-`
/// never talks to Google, so a build made for the emulators cannot reach the
/// real dev or prod project whatever else is set.
const emulatorFirebaseOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:web:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-hold-my-dice',
);
