import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../../theme/tokens.dart';
import '../doctor/doctors_screen.dart';
import '../medicines/medicines_screen.dart';
import '../visits/care_screen.dart';
import '../visits/reminders_screen.dart';

/// Mobile Care destination — Visits / Reminders / Medicines / Doctors at bottom.
class CareTab extends StatefulWidget {
  const CareTab({
    super.key,
    required this.store,
    required this.onChanged,
  });

  final LocalStore store;
  final VoidCallback onChanged;

  @override
  State<CareTab> createState() => _CareTabState();
}

class _CareTabState extends State<CareTab> {
  int _sub = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(title: const Text('Care')),
      body: IndexedStack(
        index: _sub,
        children: [
          CareScreen(
            store: widget.store,
            onChanged: widget.onChanged,
            embedded: true,
            includeReminders: false,
          ),
          RemindersScreen(
            store: widget.store,
            onChanged: widget.onChanged,
            embedded: true,
          ),
          MedicinesScreen(
            store: widget.store,
            onChanged: widget.onChanged,
            embedded: true,
          ),
          DoctorsScreen(
            store: widget.store,
            onChanged: widget.onChanged,
            embedded: true,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _sub,
        onDestinationSelected: (i) => setState(() => _sub = i),
        height: 64,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Visits',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Reminders',
          ),
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication),
            label: 'Medicines',
          ),
          NavigationDestination(
            icon: Icon(Icons.medical_information_outlined),
            selectedIcon: Icon(Icons.medical_information),
            label: 'Doctors',
          ),
        ],
      ),
    );
  }
}
