import 'package:firebase_core/firebase_core.dart';

/// The prod project. Not set up yet: `flutterfire configure` for the prod
/// project replaces the body of this getter with the real options.
FirebaseOptions get prodFirebaseOptions => throw StateError(
  'The prod Firebase project is not set up yet. '
  'Run flutterfire configure for it and fill in firebase_options_prod.dart.',
);
