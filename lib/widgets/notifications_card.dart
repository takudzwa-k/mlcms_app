import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'surfaces.dart';

class NotificationsCard extends StatefulWidget {
  const NotificationsCard({super.key});

  @override
  State<NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<NotificationsCard> {
  AuthorizationStatus? _status;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  bool get _on =>
      _status == AuthorizationStatus.authorized ||
      _status == AuthorizationStatus.provisional;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await NotificationService.status();
      if (mounted) setState(() => _status = s);
    } catch (_) {
      // leave the status blank
    }
  }

  Future<void> _enable() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final s = await NotificationService.requestPermission();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = s;
        if (s != AuthorizationStatus.authorized &&
            s != AuthorizationStatus.provisional) {
          _messageIsError = true;
          _message =
              "Notifications are blocked. Turn them on in your phone's Settings, under Apps, MLCMS, Notifications.";
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _messageIsError = true;
        _message = 'Could not ask for permission. Try again.';
      });
    }
  }

  Future<void> _copyToken() async {
    try {
      final t = await NotificationService.token();
      if (t == null || t.isEmpty) {
        throw Exception('no token');
      }
      await Clipboard.setData(ClipboardData(text: t));
      HapticFeedback.selectionClick();
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Device token copied.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = 'No device token yet. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pillColor = _on ? AppColors.ok : AppColors.warn;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: dark ? Colors.white10 : AppColors.selected,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  size: 20,
                  color: AppColors.teal,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Push alerts',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              if (_status != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: pillColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _on ? 'On' : 'Off',
                    style: TextStyle(
                      color: pillColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Get a notification when a unit leaves its safe range and when it recovers. '
            'Supervisors are also told if a breach keeps going.',
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade600),
          ),
          if (_status != null && !_on) ...[
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _busy ? null : _enable,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Enable notifications'),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _messageIsError ? AppColors.dangerLight : AppColors.okLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _messageIsError ? AppColors.danger : AppColors.ok,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _copyToken,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.teal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text(
              'Copy device token (for testing)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}