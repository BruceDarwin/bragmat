import 'package:flutter/material.dart';
import 'screens/catch_list_screen.dart';
import 'screens/add_catch_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/fishing_trips_screen.dart';
import 'screens/catch_map_screen.dart';
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
        return const CatchMapScreen();
      case 5:
        return const SettingsScreen();
      default:
        return const CatchListScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildScreen(_selectedIndex),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Stack(
          children: [
            BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              type: BottomNavigationBarType.fixed,
              elevation: 0,
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
                  icon: Icon(Icons.map),
                  label: 'Map',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
            // Gold indicator line for selected tab
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: Row(
                  children: List.generate(6, (index) {
                    final isSelected = index == _selectedIndex;
                    return Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? const Color(0xFFdfb10a) // Gold accent
                              : Colors.transparent,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(2),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}