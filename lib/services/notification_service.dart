// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:timezone/timezone.dart' as tz;
// import 'package:timezone/data/latest_all.dart' as tzdata;
//
// class NotificationService {
//   static final FlutterLocalNotificationsPlugin _notificationsPlugin =
//   FlutterLocalNotificationsPlugin();
//
//   static Future<void> init() async {
//     //Plugin initialization
//     tzdata.initializeTimeZones();
//
//     const AndroidInitializationSettings initializationSettingsAndroid =
//     AndroidInitializationSettings('@mipmap/ic_launcher');
//
//     const InitializationSettings initializationSettings =
//     InitializationSettings(android: initializationSettingsAndroid);
//
//     //Plugin initialization
//     await _notificationsPlugin.initialize(initializationSettings);
//   }
//
//   // Request permission for Android 13+ devices
//   static Future<void> requestPermission() async {
//     final bool? granted = await _notificationsPlugin
//         .resolvePlatformSpecificImplementation<
//         AndroidFlutterLocalNotificationsPlugin>()
//         ?.requestNotificationsPermission();
//
//     if (granted == true) {
//       print('✅ Notification permission granted');
//     } else {
//       print('⚠️ Notification permission denied');
//     }
//   }
//
//
//   // Function for notification with .show
//   static Future<void> showMonthlyReportNotification({
//     required String title,
//     required String body,
//   }) async {
//     const AndroidNotificationDetails androidDetails =
//     AndroidNotificationDetails(
//       'monthly_report_channel',
//       'Monthly Report Notifications',
//       importance: Importance.max,
//       priority: Priority.high,
//     );
//
//     const NotificationDetails notificationDetails =
//     NotificationDetails(android: androidDetails);
//
//     await _notificationsPlugin.show(
//       0,
//       title,
//       body,
//       notificationDetails,
//     );
//   }
//
//
//   // Function for notification with zonedSchedule
//   static Future<void> scheduleEndOfMonthNotification({
//     required String title,
//     required String body,
//   }) async {
//     try {
//       // ⏰ Test: trigger after 10 seconds
//       final scheduledDate = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10));
//
//       //Android notification Details
//       const androidDetails = AndroidNotificationDetails(
//         'monthly_summary_channel',
//         'Monthly Summary Notifications',
//         channelDescription: 'Sends monthly summary reminders',
//         importance: Importance.high,
//         priority: Priority.high,  //will appear even if the app is in the background
//       );
//
//       const notificationDetails = NotificationDetails(android: androidDetails);
//
//       await _notificationsPlugin.zonedSchedule(
//         0,
//         title,
//         body,
//         scheduledDate, // ✅ no need to re-wrap
//         notificationDetails,
//         androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
//         payload: 'monthly_summary',
//         // matchDateTimeComponents removed for one-time test
//       );
//
//       print('✅ Notification scheduled for: $scheduledDate');
//     } catch (e) {
//       print('⚠️ Failed to schedule exact alarm: $e');
//     }
//   }
//
// }



import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // Call once at app start
  static Future<void> init() async {
    // Timezones for scheduling
    tzdata.initializeTimeZones();

    // ✅ Explicitly set to your local timezone (Sri Lanka)
    tz.setLocalLocation(tz.getLocation('Asia/Colombo'));

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(initializationSettings);
  }

  // Android 13+ runtime permission
  static Future<void> requestPermission() async {
    final bool? granted = await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    if (granted == true) {
      print('✅ Notification permission granted');
    } else {
      print('⚠️ Notification permission denied');
    }
  }

  // Check if a notification (by id) is already scheduled (pending requests)
  static Future<bool> isNotificationScheduled(int id) async {
    final List<PendingNotificationRequest> pending =
    await _notificationsPlugin.pendingNotificationRequests();
    return pending.any((p) => p.id == id);
  }

  // Cancel by id
  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  // Immediate show (useful for testing)
  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'immediate_channel',
      'Immediate Notifications',
      channelDescription: 'Test / immediate notifications',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(id, title, body, details);
  }

  // Helper: next tz.TZDateTime instance for given hour/minute (today or tomorrow)
  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled =
    tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Schedules a daily notification at [hour]:[minute] (local time) if not already scheduled.
  /// - [id] is the numeric identifier (use same id if you want one slot).
  /// - Uses DateTimeComponents.time to repeat daily.
  /// - This method is idempotent: safe to call on every app start.
  static Future<void> scheduleDailyAtTimeIfNotScheduled({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    try {
      // Always cancel previous instance of this ID
      await _notificationsPlugin.cancel(id);
      print('Cancelled previous notification id: $id');
      final already = await isNotificationScheduled(id);
      if (already) {
        print('🔁 Notification id $id already scheduled — skipping.');
        return;
      }

      final tz.TZDateTime scheduledDate = _nextInstanceOfTime(hour, minute);

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'daily_summary_channel',
        'Daily Summary Notifications',
        channelDescription: 'Daily summaries at a fixed time',
        importance: Importance.high,
        priority: Priority.high,
      );

      const NotificationDetails notificationDetails =
      NotificationDetails(android: androidDetails);

      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'daily_summary',
        matchDateTimeComponents: DateTimeComponents.time, // repeat daily at same time
      );

      print('✅ Scheduled daily notification id $id at $hour:$minute (first at $scheduledDate)');
    } catch (e) {
      // If scheduling fails (permissions, device policy), don't crash the app.
      print('⚠️ Failed to schedule daily notification id $id: $e');
    }
  }
}
