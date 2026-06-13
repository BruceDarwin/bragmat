import 'package:flutter/material.dart';
import 'screens/catch_list_screen.dart';
import 'screens/add_catch_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/fishing_trips_screen.dart';
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
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void switchToMyCatches() {
    setState(() {
      _selectedIndex = 0; // Switch to My Catches tab after saving
    });
  }

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return const CatchListScreen();
      case 1:
        return AddCatchScreen(onCatchSaved: switchToMyCatches);
      case 2:
        return const StatisticsScreen();
      case 3:
        return const FishingTripsScreen();
      case 4:
        return const SettingsScreen();
      default:
        return const CatchListScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildScreen(_selectedIndex),
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
            icon: Icon(Icons.bar_chart),
            label: 'Statistics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_boat),
            label: 'Trips',
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