import 'package:flutter/material.dart';

class HubScreen extends StatelessWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hold My Dice')),
      body: const Center(child: Text('ตัวช่วยบอร์ดเกม')),
    );
  }
}
