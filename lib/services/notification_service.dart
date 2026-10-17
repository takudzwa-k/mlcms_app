import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../screens/fridge_detail_screen.dart';
import '../theme/app_theme.dart';
import 'fridge_service.dart';

/// Lets the notification code open screens and show banners from anywhere.
final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

class NotificationService {
  static final _fcm = FirebaseMessaging.instance;
  static final List<StreamSubscription<dynamic>> _subs = [];
  static bool _running = false;

  /// Asks for permission and subscribes this device to the alert channels.
  /// Everyone gets "alerts"; supervisors also get "supervisors" (escalations).
  static Future<void> start() async {
    if (_running) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _running = true;

    try {
      // Android 13+ and iOS show a prompt the first time
      await _fcm.requestPermission(alert: true, badge: true, sound: true);

      var role = '';
      try {
        final snap =
            await FirebaseDatabase.instance.ref('users/${user.uid}/role').get();
        role = (snap.value ?? '').toString();
      } catch (_) {
        // treat as a technician
      }

      await _fcm.subscribeToTopic('alerts');
      if (role == 'supervisor') {
        await _fcm.subscribeToTopic('supervisors');
      } else {
        await _fcm.unsubscribeFromTopic('supervisors');
      }

      // App open: show our own banner (the system doesn't show one)
      _subs.add(FirebaseMessaging.onMessage.listen(_showInApp));

      // App in the background: the user tapped the notification
      _subs.add(
        FirebaseMessaging.onMessageOpenedApp
            .listen((m) => _openUnit(m.data['fridgeId'])),
      );

      // App was closed: it was started by tapping the notification
      final initial = await _fcm.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openUnit(initial.data['fridgeId']),
        );
      }
    } catch (_) {
      await _cancelListeners();
      _running = false; // try again next time
    }
  }

  /// Called when the user signs out, so this phone stops getting alerts.
  static Future<void> stop() async {
    await _cancelListeners();
    _running = false;
    try {
      await _fcm.unsubscribeFromTopic('alerts');
      await _fcm.unsubscribeFromTopic('supervisors');
      await _fcm.deleteToken(); // also cuts the link if we were offline
    } catch (_) {
      // nothing more we can do
    }
  }

  static Future<void> _cancelListeners() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  // ----- Used by the Settings screen -----

  static Future<AuthorizationStatus> status() async =>
      (await _fcm.getNotificationSettings()).authorizationStatus;

  static Future<AuthorizationStatus> requestPermission() async =>
      (await _fcm.requestPermission(alert: true, badge: true, sound: true))
          .authorizationStatus;

  static Future<String?> token() => _fcm.getToken();

  // ----- Showing and opening -----

  static void _showInApp(RemoteMessage m) {
    final n = m.notification;
    final messenger = messengerKey.currentState;
    if (n == null || messenger == null) return;

    final kind = (m.data['kind'] ?? '').toString();
    final color = kind == 'resolved'
        ? AppColors.ok
        : (kind == 'escalated' ? AppColors.warn : AppColors.danger);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          duration: const Duration(seconds: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                n.title ?? 'MLCMS',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (n.body != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(n.body!, style: const TextStyle(color: Colors.white)),
                ),
            ],
          ),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () => _openUnit(m.data['fridgeId']),
          ),
        ),
      );
  }

  static Future<void> _openUnit(Object? raw) async {
    final id = raw?.toString() ?? '';
    if (id.isEmpty) return;

    try {
      final fridge = await FridgeService().fridgeStream(id).first;
      final nav = navigatorKey.currentState;
      if (fridge == null || nav == null) return;
      nav.push(
        MaterialPageRoute(builder: (_) => FridgeDetailScreen(fridge: fridge)),
      );
    } catch (_) {
      // the unit may have been removed, so there is nothing to open
    }
  }
}