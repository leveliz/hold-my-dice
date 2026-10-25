import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

/// The room as it is now and as it changes; null when there is none or it has
/// ended.
final _roomProvider = StreamProvider.autoDispose.family<RoomMeta?, String>(
  (ref, code) => ref
      .watch(roomRepositoryProvider)
      .watchMeta(code)
      .map((meta) => meta?.status == RoomStatus.ended ? null : meta),
);

/// Where a room link lands. [code] is already a valid room code, or null when
/// the link carried something that cannot be one.
class JoinRoomScreen extends ConsumerWidget {
  const JoinRoomScreen({super.key, this.code});

  final String? code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = this.code;
    return Scaffold(
      appBar: AppBar(title: const Text('เข้าห้อง')),
      body: Center(
        child: code == null
            ? const Text('ห้องนี้จบแล้วหรือไม่มีอยู่')
            : ref
                  .watch(_roomProvider(code))
                  .when(
                    loading: () => const CircularProgressIndicator(),
                    error: (_, _) => const Text('ห้องนี้จบแล้วหรือไม่มีอยู่'),
                    data: (meta) => Text(
                      meta == null
                          ? 'ห้องนี้จบแล้วหรือไม่มีอยู่'
                          : 'ห้อง $code',
                    ),
                  ),
      ),
    );
  }
}
