import 'package:tea_picker_app/services/notification_service.dart';
import '../database/db_helper.dart';
import 'package:intl/intl.dart';

class ReportService {
  final DBHelper _db = DBHelper();

  /// Compute totals for [year, month] (month: 1-12).
  /// If year/month omitted, uses current month.
  Future<void> scheduleMonthlySummaryNotification({int? year, int? month}) async {
    final now = DateTime.now();
    year ??= now.year;
    month ??= now.month;

    // Fetch all historical rows and aggregate in Dart since timestamp is saved as text.
    final dbClient = await _db.db;
    final List<Map<String, dynamic>> rows =
    List<Map<String, dynamic>>.from(await dbClient.query('historical_records'));

    final dateFormat = DateFormat('dd-MM-yyyy h:mm a'); // matches your stored format
    double totalWeight = 0.0;
    double totalWages = 0.0;

    for (final row in rows) {
      try {
        final ts = row['timestamp'] as String?;
        if (ts == null) continue;

        // parse timestamp string into DateTime
        final dt = dateFormat.parse(ts);

        if (dt.year == year && dt.month == month) {
          final weightVal = row['weight'];
          final wagesVal = row['wages'];

          // weight/wages might be int, double, or other numeric types; normalize safely
          final weightNum = (weightVal is num) ? weightVal.toDouble() : double.tryParse(weightVal?.toString() ?? '0') ?? 0.0;
          final wagesNum = (wagesVal is num) ? wagesVal.toDouble() : double.tryParse(wagesVal?.toString() ?? '0') ?? 0.0;

          totalWeight += weightNum;
          totalWages += wagesNum;
        }
      } catch (e) {
        // skip rows with unparsable timestamps
        continue;
      }
    }

    final formattedMonth = DateFormat('MMMM yyyy').format(DateTime(year, month));

    // Schedule a notification at end of month with the totals (NotificationService handles scheduling)
    await NotificationService.scheduleEndOfMonthNotification(
      title: 'Monthly Report Reminder - $formattedMonth',
      body:
      'Total weight: ${totalWeight.toStringAsFixed(2)} kg\nTotal wages: Rs. ${totalWages.toStringAsFixed(2)}\nPlease enter revenue to generate your profit report.',
    );
  }

  /// For quick testing during development — show immediate notification with current-month totals.
  Future<void> showImmediateMonthlySummaryNotification({int? year, int? month}) async {
    final now = DateTime.now();
    year ??= now.year;
    month ??= now.month;

    final dbClient = await _db.db;
    final List<Map<String, dynamic>> rows =
    List<Map<String, dynamic>>.from(await dbClient.query('historical_records'));

    final dateFormat = DateFormat('dd-MM-yyyy h:mm a');
    double totalWeight = 0.0;
    double totalWages = 0.0;

    for (final row in rows) {
      try {
        final ts = row['timestamp'] as String?;
        if (ts == null) continue;
        final dt = dateFormat.parse(ts);
        if (dt.year == year && dt.month == month) {
          final weightNum = (row['weight'] is num) ? (row['weight'] as num).toDouble() : double.tryParse(row['weight']?.toString() ?? '0') ?? 0.0;
          final wagesNum = (row['wages'] is num) ? (row['wages'] as num).toDouble() : double.tryParse(row['wages']?.toString() ?? '0') ?? 0.0;
          totalWeight += weightNum;
          totalWages += wagesNum;
        }
      } catch (e) {
        continue;
      }
    }

    final formattedMonth = DateFormat('MMMM yyyy').format(DateTime(year, month));

    await NotificationService.showMonthlyReportNotification(
      title: 'Monthly Summary - $formattedMonth',
      body:
      'Total weight: ${totalWeight.toStringAsFixed(2)} kg\nTotal wages: Rs. ${totalWages.toStringAsFixed(2)}\nPlease open the app to enter revenue.',
    );
  }
}
