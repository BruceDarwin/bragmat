import 'package:flutter/material.dart';
import 'screens/catch_list_screen.dart';
import 'theme.dart';

void main() {
  runApp(const BragmatApp());
}

class BragmatApp extends StatelessWidget {
  const BragmatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bragmat',
      theme: AppTheme.lightTheme,
      home: const CatchListScreen(),
    );
  }
}