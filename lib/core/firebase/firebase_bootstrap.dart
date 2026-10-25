import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hold_my_dice/core/firebase/firebase_options_dev.dart';
import 'package:hold_my_dice/core/firebase/firebase_options_prod.dart';

/// Which Firebase project the app talks to. [name] is `dev` or `prod`;
/// [emulatorHost] (for example `localhost`, or `10.0.2.2` from the Android
/// emulator) points Auth and Firestore at the local emulators instead, on the
/// ports in firebase.json.
class FirebaseEnv {
  const FirebaseEnv({required this.name, this.emulatorHost});

  final String name;
  final String? emulatorHost;
}

const _envName = String.fromEnvironment('FIREBASE_ENV');
const _emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR');

/// Read from `--dart-define=FIREBASE_ENV=dev|prod` and
/// `--dart-define=FIREBASE_EMULATOR=<host>`; null when no environment is given,
/// which keeps the app in single-device mode only.
FirebaseEnv? firebaseEnvFromDefines() {
  if (_envName.isEmpty) return null;
  return FirebaseEnv(
    name: _envName,
    emulatorHost: _emulatorHost.isEmpty ? null : _emulatorHost,
  );
}

const _firestoreEmulatorPort = 8080;
const _authEmulatorPort = 9099;

Future<void> initializeFirebase(FirebaseEnv env) async {
  await Firebase.initializeApp(
    options: switch (env.name) {
      'dev' => devFirebaseOptions,
      'prod' => prodFirebaseOptions,
      _ => throw ArgumentError.value(
        env.name,
        'FIREBASE_ENV',
        'use dev or prod',
      ),
    },
  );
  final host = env.emulatorHost;
  if (host != null) {
    await FirebaseAuth.instance.useAuthEmulator(host, _authEmulatorPort);
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      _firestoreEmulatorPort,
    );
  }
}
