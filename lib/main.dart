import 'package:flutter/material.dart';
import 'screens/catch_list_screen.dart';
import 'screens/add_catch_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/fishing_trips_screen.dart';
import 'screens/catch_map_screen.dart';
import 'theme.dart';
import 'services/theme_service.dart';
import 'services/connectivity_service.dart';

void main() {
  runApp(const BragmatApp());
}

class BragmatApp extends StatefulWidget {
  const BragmatApp({super.key});

  @override
  State<BragmatApp> createState() => _BragmatAppState();
}

class _BragmatAppState extends State<BragmatApp> {
  final ThemeService _themeService = ThemeService();

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {
      // Theme will be rebuilt with new palette
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bragmat',
      theme: AppTheme.lightTheme(palette: _themeService.currentPalette),
      home: MainScreen(themeService: _themeService),
    );
  }
}

class MainScreen extends StatefulWidget {
  final ThemeService themeService;

  const MainScreen({super.key, required this.themeService});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isOnline = true;
  final ConnectivityService _connectivityService = ConnectivityService();

  @override
  void initState() {
    super.initState();
    _connectivityService.initialize();
    _connectivityService.connectivityStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectivityService.dispose();
    super.dispose();
  }

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
      body: Column(
        children: [
          if (!_isOnline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_off,
                    size: 16,
                    color: Colors.orange.shade900,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Offline Fishing Mode',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildScreen(_selectedIndex)),
        ],
      ),
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
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onItemTapped,
          backgroundColor: Colors.white,
          elevation: 0,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.list),
              label: 'Catches',
            ),
            NavigationDestination(
              icon: Icon(Icons.add),
              label: 'Add',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart),
              label: 'Stats',
            ),
            NavigationDestination(
              icon: Icon(Icons.directions_boat),
              label: 'Trips',
            ),
            NavigationDestination(
              icon: Icon(Icons.map),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}