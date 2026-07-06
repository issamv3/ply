import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Manages system notifications for download progress.
/// Call [init] once at app startup (before runApp completes).
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'ply_downloads';
  static const _channelName = 'Downloads';
  static const _notifId = 1;

  /// Fired when the user taps a "download complete" notification. Carries
  /// the downloaded file's path as the payload so the app can jump straight
  /// into playing it, even if the notification was tapped after the app was
  /// fully killed (cold start).
  static void Function(String filePath)? onOpenDownload;

  static String? _pendingFilePath;

  /// Consumes and returns the file path a cold-start launch was triggered
  /// by tapping a notification for, if any. Call once, right after `init`.
  static String? takePendingFilePath() {
    final path = _pendingFilePath;
    _pendingFilePath = null;
    return path;
  }

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    final details = await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _handleTap,
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        _pendingFilePath = payload;
      }
    }

    // Create the notification channel (no-op on Android < 8, required on 8+)
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Video download progress',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static void _handleTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      onOpenDownload?.call(payload);
    }
  }

  /// Requests the POST_NOTIFICATIONS permission on Android 13+.
  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Shows or updates the ongoing download-progress notification.
  /// [progress] is 0–100. Set [indeterminate] when total size is unknown.
  static Future<void> showProgress({
    required String title,
    required String body,
    required int progress,
    bool indeterminate = false,
  }) async {
    try {
      await _plugin.show(
        _notifId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Video download progress',
            importance: Importance.low,
            priority: Priority.low,
            showProgress: true,
            maxProgress: 100,
            progress: progress,
            indeterminate: indeterminate,
            onlyAlertOnce: true,
            ongoing: true,
            playSound: false,
            enableVibration: false,
            autoCancel: false,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Shows a dismissible "Download complete" notification. Tapping it opens
  /// the downloaded video directly via [filePath], carried as the payload.
  static Future<void> showComplete(String title, {String? filePath}) async {
    try {
      await _plugin.show(
        _notifId,
        'Download complete',
        title,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Video download progress',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            ongoing: false,
            autoCancel: true,
          ),
        ),
        payload: filePath,
      );
    } catch (_) {}
  }

  /// Shows a dismissible "Download failed" notification.
  static Future<void> showError(String title, String detail) async {
    try {
      await _plugin.show(
        _notifId,
        'Download failed',
        '$title — $detail',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Video download progress',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            ongoing: false,
            autoCancel: true,
          ),
        ),
      );
    } catch (_) {}
  }

  static Future<void> cancel() async {
    try {
      await _plugin.cancel(_notifId);
    } catch (_) {}
  }
}
