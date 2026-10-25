import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A to Z without I, L and O (easy to mistake for 1, 1 and 0), and 2 to 9.
const roomCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const roomCodeLength = 6;

/// A new room code. Pass a secure random number generator in the app.
String generateRoomCode(Random random) => String.fromCharCodes([
  for (var i = 0; i < roomCodeLength; i++)
    roomCodeAlphabet.codeUnitAt(random.nextInt(roomCodeAlphabet.length)),
]);

/// What a person typed or a link carried, made into a room code: upper case,
/// without spaces and dashes. Null if it is not a code (wrong length or a
/// character that is never in a code, such as 0, O, 1, I or L).
String? normalizeRoomCode(String input) {
  final code = input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (code.length != roomCodeLength) return null;
  for (final unit in code.codeUnits) {
    if (!roomCodeAlphabet.contains(String.fromCharCode(unit))) return null;
  }
  return code;
}

/// What is stored for a room password: the SHA-256 of the password followed by
/// the room code, in hex. Only a gate for friends, not a secret.
String hashRoomPassword(String password, String code) =>
    sha256.convert(utf8.encode('$password$code')).toString();
