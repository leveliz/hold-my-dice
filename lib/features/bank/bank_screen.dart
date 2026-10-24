import 'package:flutter/material.dart';

class BankScreen extends StatelessWidget {
  const BankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pocket Banker')),
      body: const Center(child: Text('ธนาคารเกมเศรษฐี')),
    );
  }
}
