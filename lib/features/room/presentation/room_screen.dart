import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/player_avatar.dart';
import 'package:hold_my_dice/core/widgets/section_label.dart';
import 'package:hold_my_dice/features/room/application/last_room.dart';
import 'package:hold_my_dice/features/room/application/presence_beater.dart';
import 'package:hold_my_dice/features/room/application/room_password.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:hold_my_dice/features/room/presentation/room_error_text.dart';
import 'package:hold_my_dice/features/room/presentation/room_game_screen.dart';
import 'package:hold_my_dice/features/room/presentation/room_summary_screen.dart';
import 'package:hold_my_dice/features/room/presentation/room_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _gone = 'ห้องนี้จบแล้วหรือไม่มีอยู่';

void _say(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

/// Where a room link lands. [code] is already a valid room code, or null when
/// the link carried something that cannot be one. Shows what suits the person:
/// the join form for a newcomer, the waiting room for a member.
class RoomScreen extends ConsumerWidget {
  const RoomScreen({super.key, this.code});

  final String? code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = this.code;
    if (code == null) return const _Message(_gone, home: true);
    // Only a room that is really not there is "gone"; a lost connection or
    // any other failure can be tried again.
    Widget failed(Object error) =>
        error is RoomException && error.error == RoomError.roomNotFound
        ? const _Message(_gone, home: true)
        // Trying again cannot help: only a newer app can read this room.
        : error is RoomException && error.error == RoomError.unsupportedVersion
        ? _Message(roomErrorText(error), home: true)
        : _Message(
            roomErrorText(error),
            retry: () {
              ref.invalidate(roomMetaProvider(code));
              ref.invalidate(myMemberProvider(code));
            },
          );
    return ref
        .watch(roomMetaProvider(code))
        .when(
          loading: () => const _Message(null),
          error: (e, _) => failed(e),
          data: (meta) {
            if (meta == null) return const _Message(_gone, home: true);
            return ref
                .watch(myMemberProvider(code))
                .when(
                  loading: () => const _Message(null),
                  error: (e, _) => failed(e),
                  data: (me) {
                    final ended = meta.status == RoomStatus.ended;
                    // Nobody new can join a game that ended.
                    if (me == null) {
                      return ended
                          ? const _Message('เกมนี้จบแล้ว', home: true)
                          : _JoinForm(meta: meta);
                    }
                    return _Present(
                      code: code,
                      beating: !ended,
                      child: switch (meta.status) {
                        RoomStatus.lobby => _Lobby(meta: meta, me: me),
                        RoomStatus.playing => RoomGameScreen(code: code),
                        RoomStatus.ended => RoomSummaryScreen(code: code),
                      },
                    );
                  },
                );
          },
        );
  }
}

/// Keeps telling the room that this person is here for as long as they are
/// on one of its pages (the waiting room and the game).
class _Present extends ConsumerStatefulWidget {
  const _Present({
    required this.code,
    required this.child,
    this.beating = true,
  });

  final String code;
  final Widget child;

  /// Whether to keep beating (not once the game has ended: nobody needs it
  /// and each beat is a write).
  final bool beating;

  @override
  ConsumerState<_Present> createState() => _PresentState();
}

class _PresentState extends ConsumerState<_Present>
    with WidgetsBindingObserver {
  late final PresenceBeater _beater;

  @override
  void initState() {
    super.initState();
    _beater = PresenceBeater(
      ref.read(roomRepositoryProvider),
      widget.code,
      onNotAMember: _lookAgain,
    );
    if (widget.beating) _beater.start();
    WidgetsBinding.instance.addObserver(this);
    // A provider is not changed while the tree is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(lastRoomProvider.notifier).remember(widget.code);
    });
  }

  /// Asks the room who this person is now; if somebody took their seat over
  /// while the phone slept, the screen falls back to the join form.
  void _lookAgain() {
    if (mounted) ref.invalidate(myMemberProvider(widget.code));
  }

  @override
  void didUpdateWidget(_Present old) {
    super.didUpdateWidget(old);
    if (old.beating && !widget.beating) _beater.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A locked or backgrounded phone sends no beats; say we are back at once.
    if (state == AppLifecycleState.resumed && widget.beating) {
      _beater.beatNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _beater.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A page with one line of text (or a spinner when [text] is null).
class _Message extends StatelessWidget {
  const _Message(this.text, {this.home = false, this.retry});

  final String? text;
  final bool home;

  /// Offers a "try again" button when given.
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HelperAppBar(title: Text('ห้อง')),
      body: Center(
        child: text == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(text!, style: Theme.of(context).textTheme.titleMedium),
                  if (retry != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      key: const ValueKey('room-retry'),
                      onPressed: retry,
                      child: const Text('ลองใหม่'),
                    ),
                  ],
                  if (home) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      key: const ValueKey('gone-home'),
                      onPressed: () => context.go('/'),
                      child: const Text('กลับหน้าแรก'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

// ---- the waiting room ----------------------------------------------------

class _Lobby extends ConsumerStatefulWidget {
  const _Lobby({required this.meta, required this.me});

  final RoomMeta meta;
  final Member me;

  @override
  ConsumerState<_Lobby> createState() => _LobbyState();
}

class _LobbyState extends ConsumerState<_Lobby> {
  var _busy = false;

  /// Whether the room code and the password are shown as dots (for a screen
  /// that others can see).
  var _hidden = false;

  Future<void> _copy(String what, String done) async {
    await Clipboard.setData(ClipboardData(text: what));
    if (mounted) _say(context, done);
  }

  Future<void> _claimOwnership() async {
    try {
      await ref.read(roomRepositoryProvider).claimOwnership(widget.meta.code);
    } catch (e) {
      if (mounted) _say(context, roomErrorText(e));
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await ref.read(roomRepositoryProvider).startGame(widget.meta.code);
    } catch (e) {
      if (mounted) _say(context, roomErrorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  /// The owner takes the room down after one question; everybody else who is
  /// in the waiting room is told that it is gone.
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('delete-room-dialog'),
        title: const Text('ลบห้องนี้?'),
        content: const Text(
          'ทุกคนที่อยู่ในห้องจะถูกเด้งออก และเอากลับมาไม่ได้',
        ),
        actions: [
          TextButton(
            key: const ValueKey('delete-room-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ไม่ลบ'),
          ),
          FilledButton(
            key: const ValueKey('delete-room-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบห้อง'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(roomRepositoryProvider).deleteRoom(widget.meta.code);
      ref.read(roomPasswordStorageProvider).forget(widget.meta.code);
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _say(context, roomErrorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final paper = PaperStyle.maybeOf(context) != null;
    final members = ref.watch(roomMembersProvider(meta.code)).value ?? const [];
    final bySeat = {
      for (final m in members)
        if (m.seat != null) m.seat!: m,
    };
    final spectators = members.where((m) => m.role == MemberRole.spectator);
    final owner = members.where((m) => m.uid == meta.ownerUid).firstOrNull;
    final isOwner = widget.me.uid == meta.ownerUid;
    final link = roomShareLink(meta.code);
    // Only the device that made the room can know the password.
    final password = isOwner && meta.hasPassword
        ? ref.watch(roomPasswordStorageProvider).read(meta.code)
        : null;
    final line = paper
        ? PaperStyle.dash
        : theme.colorScheme.onSurface.withValues(alpha: 0.25);

    return Scaffold(
      appBar: const HelperAppBar(title: Text('ห้องรอ')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  TicketCard(
                    key: const ValueKey('ticket'),
                    line: line,
                    top: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ห้องของ ${owner?.name ?? ''}',
                            style: text.bodyMedium?.copyWith(
                              color: text.bodyMedium?.color?.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          RoomCodeTiles(
                            code: meta.code,
                            hidden: _hidden,
                            onCopied: () => _say(context, 'คัดลอกรหัสแล้ว'),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              OutlinedButton.icon(
                                key: const ValueKey('copy-code'),
                                onPressed: () =>
                                    _copy(meta.code, 'คัดลอกรหัสแล้ว'),
                                icon: const Icon(LucideIcons.copy, size: 18),
                                label: const Text('คัดลอกรหัส'),
                              ),
                              TextButton.icon(
                                key: const ValueKey('toggle-secret'),
                                onPressed: () =>
                                    setState(() => _hidden = !_hidden),
                                icon: Icon(
                                  _hidden
                                      ? LucideIcons.eye
                                      : LucideIcons.eyeOff,
                                  size: 18,
                                ),
                                label: Text(_hidden ? 'แสดงรหัส' : 'ซ่อนรหัส'),
                              ),
                            ],
                          ),
                          if (isOwner && meta.hasPassword) ...[
                            const SizedBox(height: 8),
                            Row(
                              key: const ValueKey('room-password-row'),
                              children: [
                                const Icon(LucideIcons.lock, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: password == null
                                      ? Text(
                                          'ไม่ทราบรหัสผ่านบนเครื่องนี้',
                                          style: text.bodyMedium,
                                        )
                                      : Semantics(
                                          container: true,
                                          child: Text.rich(
                                            key: const ValueKey(
                                              'room-password-text',
                                            ),
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: 'รหัสผ่านห้อง  ',
                                                  style: text.bodyMedium,
                                                ),
                                                TextSpan(
                                                  text: _hidden
                                                      ? '••••••'
                                                      : password,
                                                  style: serifStyle(
                                                    text.titleMedium,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                ),
                                if (password != null)
                                  IconButton(
                                    key: const ValueKey('copy-password'),
                                    tooltip: 'คัดลอกรหัสผ่าน',
                                    onPressed: () =>
                                        _copy(password, 'คัดลอกรหัสผ่านแล้ว'),
                                    icon: const Icon(
                                      LucideIcons.copy,
                                      size: 18,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    bottom: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          RoomQr(key: const ValueKey('room-qr'), data: link),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'สแกน หรือส่งลิงก์ให้เพื่อน',
                                  style: text.bodyMedium,
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  key: const ValueKey('copy-link'),
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: link),
                                    );
                                    if (context.mounted) {
                                      _say(context, 'คัดลอกลิงก์แล้ว');
                                    }
                                  },
                                  icon: const Icon(LucideIcons.copy),
                                  label: const Text('คัดลอกลิงก์'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('ที่นั่ง', style: text.titleMedium),
                      const SizedBox(width: 8),
                      RoomChip(
                        '${bySeat.length} / ${meta.settings.maxPlayers}',
                        key: const ValueKey('seat-count'),
                      ),
                      const Spacer(),
                      const LiveMark(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (var i = 1; i <= meta.settings.maxPlayers; i++) ...[
                    _SeatRow(
                      id: 'p$i',
                      member: bySeat['p$i'],
                      ownerUid: meta.ownerUid,
                      meUid: widget.me.uid,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (spectators.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'ผู้ชม ${spectators.length} คน',
                        key: const ValueKey('spectator-count'),
                        style: text.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: isOwner
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('start-room'),
                          onPressed: !_busy && bySeat.length >= 2
                              ? _start
                              : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            textStyle: text.titleLarge,
                          ),
                          icon: const Icon(LucideIcons.play),
                          label: Text('เริ่มเกม (${bySeat.length} คน)'),
                        ),
                        TextButton.icon(
                          key: const ValueKey('delete-room'),
                          onPressed: _busy ? null : _delete,
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          icon: const Icon(LucideIcons.trash2, size: 18),
                          label: const Text('ไม่เล่นแล้ว ลบห้องนี้'),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'รอเจ้าของห้องเริ่มเกม',
                          key: const ValueKey('wait-owner'),
                          style: text.titleMedium,
                        ),
                        TextButton(
                          key: const ValueKey('claim-owner'),
                          onPressed: _claimOwnership,
                          child: const Text(
                            'เจ้าของห้องหายไปนานแล้ว? รับเป็นเจ้าของแทน',
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({
    required this.id,
    required this.member,
    required this.ownerUid,
    required this.meUid,
  });

  final String id;
  final Member? member;
  final String ownerUid;
  final String meUid;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final m = member;
    return Container(
      key: ValueKey('seat-$id'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: tileDecoration(context),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              id,
              style: text.bodySmall?.copyWith(
                color: text.bodySmall?.color?.withValues(alpha: 0.6),
              ),
            ),
          ),
          if (m == null)
            Expanded(
              child: Text(
                'ว่าง',
                style: text.bodyLarge?.copyWith(
                  color: text.bodyLarge?.color?.withValues(alpha: 0.5),
                ),
              ),
            )
          else ...[
            PlayerAvatar(name: m.name, color: Color(m.color), size: 30),
            const SizedBox(width: 10),
            Expanded(child: Text(m.name, style: text.titleMedium)),
            if (m.uid == ownerUid) const RoomChip('เจ้าของห้อง'),
            if (m.uid == meUid) ...[
              const SizedBox(width: 6),
              const RoomChip('คุณ'),
            ],
          ],
        ],
      ),
    );
  }
}

// ---- joining -------------------------------------------------------------

class _JoinForm extends ConsumerStatefulWidget {
  const _JoinForm({required this.meta});

  final RoomMeta meta;

  @override
  ConsumerState<_JoinForm> createState() => _JoinFormState();
}

class _JoinFormState extends ConsumerState<_JoinForm> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  Color? _picked;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _hasName => _name.text.trim().isNotEmpty;
  bool get _passwordOk => !widget.meta.hasPassword || _password.text.isNotEmpty;
  String? get _passwordOrNull =>
      widget.meta.hasPassword ? _password.text : null;

  /// Runs a join; on success the room screen refreshes into the waiting room.
  Future<void> _run(Future<Object?> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(myMemberProvider(widget.meta.code));
      ref.invalidate(roomSeatsProvider(widget.meta.code));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _say(context, roomErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final repo = ref.read(roomRepositoryProvider);
    final seats = ref.watch(roomSeatsProvider(meta.code)).value ?? const [];
    final taken = seats.whereType<Seat>().toList();
    final owner = taken.where((s) => s.uid == meta.ownerUid).firstOrNull;
    final lobby = meta.status == RoomStatus.lobby;
    // Until they choose, the first colour that nobody in the room wears.
    final usedColors = {for (final s in taken) s.color};
    final color =
        _picked ??
        roomColorChoices.firstWhere(
          (c) => !usedColors.contains(c.toARGB32()),
          orElse: () => roomColorChoices.first,
        );
    final full = taken.length >= meta.settings.maxPlayers;
    void refresh(Object? _) => setState(() {});

    return Scaffold(
      appBar: const HelperAppBar(title: Text('เข้าห้อง')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              '${owner?.name ?? 'เพื่อนของคุณ'} ชวนคุณเข้าห้อง',
              key: const ValueKey('invite'),
              style: text.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              meta.code,
              key: const ValueKey('join-code'),
              style: serifStyle(
                text.headlineMedium?.copyWith(letterSpacing: 3),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                RoomChip(
                  '${taken.length} / ${meta.settings.maxPlayers} ที่นั่ง',
                ),
                if (meta.hasPassword) const RoomChip('มีรหัสผ่าน'),
              ],
            ),
            const SizedBox(height: 16),
            if (meta.hasPassword) ...[
              RoomField(
                key: const ValueKey('join-password'),
                label: 'รหัสผ่านห้อง',
                controller: _password,
                hint: 'ใส่รหัสผ่าน',
                obscure: true,
                onChanged: refresh,
              ),
              const SizedBox(height: 8),
            ],
            RoomField(
              key: const ValueKey('join-name'),
              label: 'ชื่อของคุณ',
              controller: _name,
              hint: 'ใส่ชื่อ',
              inputFormatters: const [NameLimitFormatter()],
              onChanged: refresh,
            ),
            const SizedBox(height: 12),
            ColorSwatches(
              selected: color,
              onSelected: (c) => setState(() => _picked = c),
            ),
            const SizedBox(height: 16),
            if (lobby)
              FilledButton.icon(
                key: const ValueKey('join-seat'),
                onPressed: !_busy && _hasName && _passwordOk && !full
                    ? () => _run(
                        () => repo.joinAsPlayer(
                          code: meta.code,
                          name: _name.text.trim(),
                          color: color.toARGB32(),
                          password: _passwordOrNull,
                        ),
                      )
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: text.titleLarge,
                ),
                icon: const Icon(LucideIcons.armchair),
                label: Text(full ? 'ห้องเต็ม' : 'นั่งโต๊ะ'),
              )
            else
              Text(
                'เกมเริ่มไปแล้ว เข้าได้เฉพาะแทนที่นั่งเดิมหรือเป็นผู้ชม',
                key: const ValueKey('already-started'),
                style: text.bodyMedium,
              ),
            if (meta.settings.allowSpectators) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('join-spectator'),
                onPressed: !_busy && _hasName && _passwordOk
                    ? () => _run(
                        () => repo.joinAsSpectator(
                          code: meta.code,
                          name: _name.text.trim(),
                          color: color.toARGB32(),
                          password: _passwordOrNull,
                        ),
                      )
                    : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(LucideIcons.eye),
                label: const Text('ขอดูเฉย ๆ (ผู้ชม)'),
              ),
            ],
            if (taken.isNotEmpty) ...[
              const SectionLabel(
                'เคยนั่งที่นี่แต่เครื่องหาย? เลือกที่นั่งเดิม',
              ),
              const SizedBox(height: 6),
              for (final s in taken) ...[
                Container(
                  key: ValueKey('claimable-${s.id}'),
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  decoration: tileDecoration(context),
                  child: Row(
                    children: [
                      PlayerAvatar(
                        name: s.name,
                        color: Color(s.color),
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.name, style: text.titleMedium)),
                      TextButton(
                        key: ValueKey('claim-${s.id}'),
                        onPressed: !_busy && _passwordOk
                            ? () => _run(
                                () => repo.claimSeat(
                                  code: meta.code,
                                  seatId: s.id,
                                  password: _passwordOrNull,
                                ),
                              )
                            : null,
                        child: const Text('เข้าแทน'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
