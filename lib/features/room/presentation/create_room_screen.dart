import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/thousands_formatter.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/section_label.dart';
import 'package:hold_my_dice/features/bank/data/bank_storage.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:hold_my_dice/features/room/presentation/room_error_text.dart';
import 'package:hold_my_dice/features/room/presentation/room_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _minSeats = 2;
const _maxSeats = 8;

/// Opening a room: who you are, the money, and the options of the room.
class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  final _name = TextEditingController();
  final _startCash = TextEditingController();
  final _goCash = TextEditingController();
  final _password = TextEditingController();
  final _bankLimit = TextEditingController();
  Color _color = roomColorChoices.first;
  var _maxPlayers = 6;
  var _usePassword = false;
  var _spectators = true;
  var _hideOthers = false;
  var _limitBank = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    // The money of the last single-device game, else the usual Monopoly sums.
    final last = ref.read(bankStorageProvider).loadSettings();
    _startCash.text = formatMoney(last?.startingCash ?? 1500);
    _goCash.text = formatMoney(last?.goAmount ?? 200);
  }

  @override
  void dispose() {
    _name.dispose();
    _startCash.dispose();
    _goCash.dispose();
    _password.dispose();
    _bankLimit.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      !_busy &&
      _name.text.trim().isNotEmpty &&
      (parseMoney(_startCash.text) ?? 0) > 0 &&
      (parseMoney(_goCash.text) ?? 0) > 0 &&
      (!_usePassword || _password.text.isNotEmpty) &&
      (!_limitBank || (parseMoney(_bankLimit.text) ?? 0) > 0);

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final meta = await ref
          .read(roomRepositoryProvider)
          .createRoom(
            settings: RoomSettings(
              startingCash: parseMoney(_startCash.text)!,
              goAmount: parseMoney(_goCash.text)!,
              maxPlayers: _maxPlayers,
              hideOthers: _hideOthers,
              allowSpectators: _spectators,
              bankLimit: _limitBank ? parseMoney(_bankLimit.text) : null,
            ),
            password: _usePassword ? _password.text : null,
            name: _name.text.trim(),
            color: _color.toARGB32(),
          );
      if (mounted) context.pushReplacement('/room/${meta.code}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(roomErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    void refresh(Object? _) => setState(() {});
    return Scaffold(
      appBar: const HelperAppBar(title: Text('สร้างห้อง')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  RoomField(
                    key: const ValueKey('room-name'),
                    label: 'ชื่อของคุณ',
                    controller: _name,
                    hint: 'ใส่ชื่อ',
                    inputFormatters: const [NameLimitFormatter()],
                    onChanged: refresh,
                  ),
                  const SizedBox(height: 12),
                  ColorSwatches(
                    selected: _color,
                    onSelected: (c) => setState(() => _color = c),
                  ),
                  const SectionLabel('เงิน'),
                  const SizedBox(height: 8),
                  RoomField(
                    key: const ValueKey('start-cash'),
                    label: 'เงินเริ่มต้นของทุกคน',
                    controller: _startCash,
                    hint: 'ใส่จำนวน',
                    keyboardType: TextInputType.number,
                    inputFormatters: const [ThousandsFormatter()],
                    onChanged: refresh,
                  ),
                  const SizedBox(height: 8),
                  RoomField(
                    key: const ValueKey('go-cash'),
                    label: 'เงินผ่านจุดเริ่ม',
                    controller: _goCash,
                    hint: 'ใส่จำนวน',
                    keyboardType: TextInputType.number,
                    inputFormatters: const [ThousandsFormatter()],
                    onChanged: refresh,
                  ),
                  const SectionLabel('ห้อง'),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: tileDecoration(context),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('นั่งได้สูงสุด', style: text.titleMedium),
                        ),
                        IconButton(
                          key: const ValueKey('seats-minus'),
                          tooltip: 'ลดที่นั่ง',
                          onPressed: _maxPlayers > _minSeats
                              ? () => setState(() => _maxPlayers--)
                              : null,
                          icon: const Icon(LucideIcons.minus),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(
                            '$_maxPlayers คน',
                            key: const ValueKey('seats-value'),
                            textAlign: TextAlign.center,
                            style: text.titleLarge,
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('seats-plus'),
                          tooltip: 'เพิ่มที่นั่ง',
                          onPressed: _maxPlayers < _maxSeats
                              ? () => setState(() => _maxPlayers++)
                              : null,
                          icon: const Icon(LucideIcons.plus),
                        ),
                      ],
                    ),
                  ),
                  RoomSwitch(
                    label: 'ตั้งรหัสผ่านห้อง',
                    value: _usePassword,
                    onChanged: (v) => setState(() => _usePassword = v),
                  ),
                  if (_usePassword)
                    RoomField(
                      key: const ValueKey('room-password'),
                      label: 'รหัสผ่าน',
                      controller: _password,
                      hint: 'ใส่รหัสผ่าน',
                      onChanged: refresh,
                    ),
                  RoomSwitch(
                    label: 'ให้ผู้ชมเข้าได้',
                    value: _spectators,
                    onChanged: (v) => setState(() => _spectators = v),
                  ),
                  RoomSwitch(
                    label: 'ซ่อนยอดคนอื่นบนจอ',
                    value: _hideOthers,
                    onChanged: (v) => setState(() => _hideOthers = v),
                  ),
                  RoomSwitch(
                    label: 'ธนาคารมีเงินจำกัด',
                    value: _limitBank,
                    onChanged: (v) => setState(() => _limitBank = v),
                  ),
                  if (_limitBank)
                    RoomField(
                      key: const ValueKey('bank-limit'),
                      label: 'เงินในธนาคาร',
                      controller: _bankLimit,
                      hint: 'ใส่จำนวน',
                      keyboardType: TextInputType.number,
                      inputFormatters: const [ThousandsFormatter()],
                      onChanged: refresh,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FilledButton.icon(
                key: const ValueKey('create-room'),
                onPressed: _canCreate ? _create : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: text.titleLarge,
                ),
                icon: const Icon(LucideIcons.ticket),
                label: const Text('ออกตั๋วห้อง'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
