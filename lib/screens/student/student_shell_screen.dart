// Main student shell screen.
// For now it holds placeholder tabs, but this is where the student experience
// will grow: home, chat, AI quizzes, peer posts, and profile.

import 'package:flutter/material.dart';

class StudentShellScreen extends StatefulWidget {
  const StudentShellScreen({super.key});

  // Creates the state that remembers the selected bottom navigation tab.
  // A StatefulWidget is enough here because the selected tab is only local UI
  // state, not shared app data.
  @override
  State<StudentShellScreen> createState() => _StudentShellScreenState();
}

class _StudentShellScreenState extends State<StudentShellScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    Center(child: Text('Home screen placeholder')),
    Center(child: Text('Chat placeholder')),
    Center(child: Text('AI Quiz placeholder')),
    Center(child: Text('Peers placeholder')),
    Center(child: Text('Profile placeholder')),
  ];

  // Updates the selected tab when the student taps the bottom navigation.
  // setState tells Flutter to rebuild the body with the page at the new index.
  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  // Builds the main student shell with placeholder sections for the MVP.
  // Later, each placeholder can become its own screen or component without
  // changing how the bottom navigation works.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PeerStudy')),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.quiz), label: 'Quiz'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Peers'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
