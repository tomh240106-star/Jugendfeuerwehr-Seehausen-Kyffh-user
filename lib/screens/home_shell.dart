import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'events_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    _DashboardPage(),
    EventsScreen(),
    _SimplePage(
      icon: Icons.school_outlined,
      title: 'Ausbildung',
      text: 'Hier werden die Ausbildungspläne angezeigt.',
    ),
    _SimplePage(
      icon: Icons.message_outlined,
      title: 'Nachrichten',
      text: 'Hier können später Nachrichten angezeigt werden.',
    ),
  ];

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jugendfeuerwehr Seehausen'),
        actions: [
          IconButton(
            tooltip: 'Abmelden',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Start',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Termine',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Ausbildung',
          ),
          NavigationDestination(
            icon: Icon(Icons.message_outlined),
            selectedIcon: Icon(Icons.message),
            label: 'Nachrichten',
          ),
        ],
      ),
    );
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage();

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Willkommen!',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF102638),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          user?.email ?? 'Jugendfeuerwehr Seehausen/Kyffhäuser',
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 28),
        const _DashboardCard(
          icon: Icons.calendar_month,
          title: 'Nächster Dienst',
          subtitle: 'Termine im Bereich „Termine“ ansehen',
        ),
        const SizedBox(height: 14),
        const _DashboardCard(
          icon: Icons.school,
          title: 'Ausbildungsplan',
          subtitle: 'Ausbildungsinhalte anzeigen',
        ),
        const SizedBox(height: 14),
        const _DashboardCard(
          icon: Icons.notifications,
          title: 'Mitteilungen',
          subtitle: 'Keine neuen Mitteilungen',
        ),
        const SizedBox(height: 30),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Column(
              children: [
                Icon(
                  Icons.local_fire_department,
                  size: 50,
                  color: Color(0xFFE30613),
                ),
                SizedBox(height: 12),
                Text(
                  'Gemeinsam. Stark. Für morgen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE30613),
          foregroundColor: Colors.white,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _SimplePage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _SimplePage({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 75,
              color: const Color(0xFFE30613),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
