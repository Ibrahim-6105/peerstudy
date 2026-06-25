// Student shell screen with placeholder tabs for Home, Chat, Quizzes, Peers, and Profile.
// This page will become the main student navigation container.

import 'package:flutter/material.dart';

class StudentShellScreen extends StatefulWidget {
  const StudentShellScreen({super.key});

  // Creates the state that remembers the selected bottom navigation tab.
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
  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  // Builds the main student shell with placeholder sections for the MVP.
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
