import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/features/room/application/room_code.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Typing a room code by hand, for a friend who was told it out loud.
class EnterCodeScreen extends StatefulWidget {
  const EnterCodeScreen({super.key});

  @override
  State<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends State<EnterCodeScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _code => normalizeRoomCode(_controller.text);

  void _enter() {
    final code = _code;
    if (code != null) context.pushReplacement('/room/$code');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const HelperAppBar(title: Text('เข้าห้อง')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('รหัสห้อง 6 ตัว', style: text.titleMedium),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('code-field'),
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: text.headlineMedium?.copyWith(letterSpacing: 4),
                decoration: const InputDecoration(hintText: 'K7M2QX'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _enter(),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const ValueKey('enter-code'),
                onPressed: _code == null ? null : _enter,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: text.titleLarge,
                ),
                icon: const Icon(LucideIcons.doorOpen),
                label: const Text('เข้าห้อง'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
