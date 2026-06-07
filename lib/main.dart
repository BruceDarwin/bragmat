import 'package:flutter/material.dart';
import 'screens/catch_list_screen.dart';
import 'screens/add_catch_screen.dart';
import 'screens/settings_screen.dart';
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
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const CatchListScreen(),
    const AddCatchScreen(),
    const SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'My Catches',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add),
            label: 'Add Catch',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}