import 'package:flutter/material.dart';

/// Placeholder until the Score Snitch screens (S3) are built.
class ScoreScreen extends StatelessWidget {
  const ScoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const Text('Score Snitch')),
      body: const Center(
        key: ValueKey('score-placeholder'),
        child: Text('นับคะแนนรายรอบ'),
      ),
    );
  }
}
