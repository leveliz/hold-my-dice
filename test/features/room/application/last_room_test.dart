import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:hold_my_dice/features/room/application/last_room.dart';

void main() {
  test('nothing is remembered at first', () {
    expect(LastRoomStorage(MemoryJsonStore()).read(), isNull);
  });

  test('a saved code comes back', () async {
    final store = MemoryJsonStore();
    LastRoomStorage(store).save('K7M2QX');
    await Future<void>.value();
    expect(LastRoomStorage(store).read(), 'K7M2QX');
  });

  test('something that is not a room code is not given back', () {
    final store = MemoryJsonStore();
    for (final raw in [
      '{"code": "hello"}',
      '{"code": 7}',
      '{"other": "K7M2QX"}',
      'not json',
    ]) {
      store.putRaw(LastRoomStorage.key, raw);
      expect(LastRoomStorage(store).read(), isNull, reason: raw);
    }
  });

  test('a store that cannot write does not break remembering', () async {
    final storage = LastRoomStorage(_BrokenStore());
    final container = ProviderContainer(
      overrides: [lastRoomStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    container.read(lastRoomProvider.notifier).remember('K7M2QX');
    await Future<void>.value();
    expect(container.read(lastRoomProvider), 'K7M2QX');
  });

  test('the notifier starts from what was saved and follows new rooms', () {
    final store = MemoryJsonStore()
      ..putRaw(LastRoomStorage.key, '{"code": "K7M2QX"}');
    final container = ProviderContainer(
      overrides: [
        lastRoomStorageProvider.overrideWithValue(LastRoomStorage(store)),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(lastRoomProvider), 'K7M2QX');
    container.read(lastRoomProvider.notifier).remember('P3KQ7M');
    expect(container.read(lastRoomProvider), 'P3KQ7M');
    expect(LastRoomStorage(store).read(), 'P3KQ7M');
  });
}

class _BrokenStore extends MemoryJsonStore {
  @override
  Future<void> write(String key, Map<String, dynamic> value) =>
      Future.error(StateError('no storage'));
}
