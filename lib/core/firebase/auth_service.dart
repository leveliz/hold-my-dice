import 'package:firebase_auth/firebase_auth.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';

/// Anonymous Firebase sign-in: the same uid comes back after a reload as long
/// as the browser or phone keeps its storage.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService([FirebaseAuth? auth])
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Future<String> ensureSignedIn() async {
    // On the web the saved sign-in is restored asynchronously, so wait for the
    // first answer before deciding that nobody is signed in.
    try {
      final restored = await _auth.authStateChanges().first;
      final user = restored ?? (await _auth.signInAnonymously()).user;
      return user!.uid;
    } on FirebaseAuthException catch (e) {
      // Without a connection signing in fails; say so in the room's terms.
      throw RoomException(
        e.code == 'network-request-failed'
            ? RoomError.offline
            : RoomError.unknown,
        e.code,
      );
    }
  }
}
