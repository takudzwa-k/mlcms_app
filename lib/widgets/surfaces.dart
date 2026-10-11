import 'package:flutter/material.dart';

/// Pure white in light mode, a deep teal-grey in dark mode.
Color appSurface(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? const Color(0xFF16272B) : Colors.white;
}

/// A soft shadow that lifts white cards off the cream background.
List<BoxShadow> softShadow(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;

  if (dark) {
    return [
      BoxShadow(
        color: Colors.black.withAlpha(110),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];
  }

  return [
    BoxShadow(
      color: const Color(0xFF3B3A2C).withAlpha(22),
      blurRadius: 22,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: const Color(0xFF3B3A2C).withAlpha(14),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];
}

/// A soft red fade used at the top of alert tiles instead of an outline.
LinearGradient alertGradient(BuildContext context, {double fadeTo = 0.6}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: dark
        ? const [Color(0xFF4A2326), Color(0xFF16272B)]
        : const [Color(0xFFF8CBC6), Colors.white],
    stops: [0.0, fadeTo],
  );
}