import 'package:flutter/material.dart';

// A simple app-wide settings holder. ValueNotifier automatically
// tells any listening widget to rebuild when the value changes.
class AppSettings {
  static final ValueNotifier<bool> darkMode = ValueNotifier(false);
  static final ValueNotifier<bool> useFahrenheit = ValueNotifier(false);
}