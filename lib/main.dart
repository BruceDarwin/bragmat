import 'package:flutter/material.dart';
import 'screens/catch_list_screen.dart';

void main() {
  runApp(const BragmatApp());
}

class BragmatApp extends StatelessWidget {
  const BragmatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: CatchListScreen(),
    );
  }
}