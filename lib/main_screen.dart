import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'teapickers_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import 'auth_service.dart';
import 'login_screen.dart';
import 'firestore_service.dart';
import 'services/migration_service.dart';
import 'services/notification_service.dart';
import 'services/report_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final AuthService _authService = AuthService();

  static const List<Widget> _screens = [
    HomeScreen(),
    TeaPickersScreen(),
    SettingsScreen(),
    HistoryScreen(),
  ];

  static const List<String> _titles = [
    'Home',
    'Tea Pickers',
    'Settings',
    'History',
  ];

  @override
  void initState() {
    super.initState();
    // Background start-up work, after the first frame so the UI shows at once.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startupTasks());
  }

  Future<void> _startupTasks() async {
    await NotificationService.requestPermission();
    final message = await MigrationService.run();
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    await ReportService().refreshDailySummaryNotification();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _signOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    await _authService.signOut();
    navigator.pushReplacement(
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_selectedIndex],
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: FirestoreService.lastError,
            builder: (context, error, _) => error == null
                ? const SizedBox.shrink()
                : MaterialBanner(
                    backgroundColor: Colors.orange[50],
                    leading: const Icon(Icons.cloud_off, color: Colors.orange),
                    content: Text('Cloud sync problem: $error'),
                    actions: [
                      TextButton(
                        onPressed: () => FirestoreService.lastError.value = null,
                        child: const Text('DISMISS'),
                      ),
                    ],
                  ),
          ),
          // IndexedStack keeps every tab alive, so switching tabs is instant.
          Expanded(child: IndexedStack(index: _selectedIndex, children: _screens)),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Tea Pickers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
    );
  }
}
