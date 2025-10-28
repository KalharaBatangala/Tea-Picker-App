import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    //Plugin initialization
    tzdata.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    //Plugin initialization
    await _notificationsPlugin.initialize(initializationSettings);
  }

  // Request permission for Android 13+ devices
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


  // Function for notification with .show
  static Future<void> showMonthlyReportNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'monthly_report_channel',
      'Monthly Report Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      0,
      title,
      body,
      notificationDetails,
    );
  }


  // Function for notification with zonedSchedule
  static Future<void> scheduleEndOfMonthNotification({
    required String title,
    required String body,
  }) async {
    try {
      // ⏰ Test: trigger after 10 seconds
      final scheduledDate = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10));

      //Android notification Details
      const androidDetails = AndroidNotificationDetails(
        'monthly_summary_channel',
        'Monthly Summary Notifications',
        channelDescription: 'Sends monthly summary reminders',
        importance: Importance.high,
        priority: Priority.high,  //will appear even if the app is in the background
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.zonedSchedule(
        0,
        title,
        body,
        scheduledDate, // ✅ no need to re-wrap
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'monthly_summary',
        // matchDateTimeComponents removed for one-time test
      );

      print('✅ Notification scheduled for: $scheduledDate');
    } catch (e) {
      print('⚠️ Failed to schedule exact alarm: $e');
    }
  }

}
