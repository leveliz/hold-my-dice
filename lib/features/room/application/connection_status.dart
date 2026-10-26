import 'dart:async';

/// Whether this device is online, from a stream that says for each snapshot of
/// a document whether it came from the local cache (`true`) or from the server
/// (`false`). Starts as online; goes offline when snapshots have come from the
/// cache for the whole [grace] time without one from the server; is online
/// again at the first snapshot from the server. Speaks only when the answer
/// changes. (Firestore on the web has no direct "connected" flag; a listener
/// opened with metadata changes tells this much.)
Stream<bool> onlineFrom(
  Stream<bool> fromCache, {
  Duration grace = const Duration(seconds: 8),
}) {
  late final StreamController<bool> controller;
  StreamSubscription<bool>? subscription;
  Timer? countdown;
  var online = true;

  void say(bool value) {
    if (value == online) return;
    online = value;
    controller.add(value);
  }

  controller = StreamController<bool>(
    onListen: () {
      controller.add(true);
      subscription = fromCache.listen(
        (cached) {
          if (cached) {
            countdown ??= Timer(grace, () {
              countdown = null;
              say(false);
            });
          } else {
            countdown?.cancel();
            countdown = null;
            say(true);
          }
        },
        onError: controller.addError,
        onDone: () {
          countdown?.cancel();
          controller.close();
        },
      );
    },
    onCancel: () {
      countdown?.cancel();
      return subscription?.cancel();
    },
  );
  return controller.stream;
}
