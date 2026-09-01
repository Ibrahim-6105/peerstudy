// Main student shell screen.
// It gives beginners three predictable destinations: Home, Catalog, Profile.
//
// Beginner note: a shell holds several tabs inside one page. IndexedStack keeps
// each tab alive while the bottom navigation changes the visible destination.

import 'package:flutter/material.dart';
import 'package:peerstudy/screens/profile/student_profile_screen.dart';
import 'package:peerstudy/screens/student/student_departments_screen.dart';
import 'package:peerstudy/screens/student/student_home_screen.dart';

class StudentShellScreen extends StatefulWidget {
  const StudentShellScreen({super.key});

  @override
  State<StudentShellScreen> createState() => _StudentShellScreenState();
}

class _StudentShellScreenState extends State<StudentShellScreen> {
  // 0 is Home, 1 is the academic catalog, and 2 is Profile.
  int _selectedIndex = 0;

  // setState rebuilds only the shell selection; the IndexedStack keeps tab state.
  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // Home and Profile can switch directly to the academic catalog tab.
    final pages = <Widget>[
      StudentHomeScreen(onBrowseSubjects: () => _onItemTapped(1)),
      const StudentDepartmentsScreen(),
      StudentProfileTab(
        isActive: _selectedIndex == 2,
        onBrowseSubjects: () => _onItemTapped(1),
      ),
    ];

    // Titles match the same stable destinations already shown to students.
    const titles = ['Home', 'Academic Catalog', 'Profile'];

    return Scaffold(
      appBar: AppBar(title: Text(titles[_selectedIndex])),
      // SafeArea keeps every tab clear of cut-outs and system gesture areas.
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
      bottomNavigationBar: Semantics(
        container: true,
        label: 'Student navigation',
        child: NavigationBar(
          // A compact bar keeps more room for study content on small phones.
          height: 64,
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onItemTapped,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book_rounded),
              label: 'Catalog',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
