import 'package:flutter/material.dart';

/// Fixed list of room icons - only the index is stored in the database, so the
/// list must not be reordered later.
const List<IconData> roomIcons = [
  Icons.weekend,
  Icons.bed,
  Icons.kitchen,
  Icons.bathtub,
  Icons.meeting_room,
  Icons.menu_book,
  Icons.garage,
  Icons.deck,
  Icons.stairs,
  Icons.pets,
  Icons.desktop_windows,
  Icons.local_fire_department,
];

IconData roomIconAt(int index) => roomIcons[index.clamp(0, roomIcons.length - 1)];
