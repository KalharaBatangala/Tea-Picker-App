import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'models/tea_entry.dart';
import './services/report_service.dart';

/// Daily entry screen. Shows today by default, but any earlier day can be
/// selected to add weights that were missed (e.g. while nobody was at home).
/// Every entry keeps two dates: `date` = the day the tea was picked (used for
/// all totals and reports) and `created_at` = when it was typed in.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FirestoreService _firestore = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ReportService _reportService = ReportService();

  /// Earliest day the calendar allows going back to.
  static final DateTime _firstDay = DateTime(2020);

  late String _today;
  late String _selectedDay;
  late Stream<List<TeaEntry>> _dayEntries;
  late final Stream<List<Picker>> _pickers = _firestore.pickerList();
  StreamSubscription<Rates>? _ratesSub;
  Rates _rates = Rates.defaults;
  Timer? _dayTimer;

  final Map<String, bool> _deleteMode = {};

  bool get _isToday => _selectedDay == _today;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _today = dayKey(DateTime.now());
    _selectDay(_today);
    _ratesSub = _firestore.rates().listen((r) => _rates = r);
    // "Today" moves on at midnight even if the app stays open.
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkNewDay());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ratesSub?.cancel();
    _dayTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkNewDay();
  }

  void _selectDay(String day) {
    _selectedDay = day;
    _dayEntries = _firestore.entriesForDay(day);
    _deleteMode.clear();
  }

  void _goToDay(DateTime d) {
    final key = dayKey(d);
    if (key.compareTo(_today) > 0 || key == _selectedDay) return; // no future days
    setState(() => _selectDay(key));
  }

  void _checkNewDay() {
    final now = dayKey(DateTime.now());
    if (now == _today || !mounted) return;
    setState(() {
      final wasToday = _isToday;
      _today = now;
      // Follow the new day only if the user was looking at "today".
      if (wasToday) _selectDay(now);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_selectedDay),
      firstDate: _firstDay,
      lastDate: DateTime.parse(_today),
      helpText: 'Day the tea was picked',
    );
    if (picked != null) _goToDay(picked);
  }

  Future<void> _refreshData() =>
      _firestore.refreshFromServer(FirestoreService.entries.where('date', isEqualTo: _selectedDay));

  void _saveEntry(String pickerName, double weight, String day) {
    _firestore.addEntry(TeaEntry(
      id: const Uuid().v4(),
      pickerName: pickerName,
      weight: weight,
      enteredBy: _auth.currentUser?.displayName ?? 'Unknown',
      createdAt: DateTime.now(), // when it was typed in
      date: day, // the day the tea was picked
      wages: weight * _rates.wageRate,
      rate: _rates.wageRate,
      busFee: _rates.busFee,
    ));
    _reportService.refreshDailySummaryNotification(cacheOnly: true);
  }

  /// Shared by the "+" floating button (choose picker) and each card's "+".
  Future<void> _showEntryDialog({String? fixedPicker}) async {
    // Lock the day at the moment the dialog opens.
    final day = _selectedDay;
    final isPast = day != _today;
    String? pickerName = fixedPicker;
    String? error;
    final weightController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          void submit() {
            final weight = double.tryParse(weightController.text.trim().replaceAll(',', '.'));
            if (!_rates.known) {
              setDialogState(() => error = 'Rates not loaded yet – connect to the internet once');
            } else if (pickerName == null) {
              setDialogState(() => error = 'Select a tea picker');
            } else if (weight == null || weight <= 0) {
              setDialogState(() => error = 'Enter a valid weight');
            } else if (weight > 500) {
              setDialogState(() => error = 'Weight looks too large – please check');
            } else {
              // Close first: the save is instant locally and uploads in the background.
              Navigator.pop(context);
              _saveEntry(pickerName!, weight, day);
            }
          }

          return AlertDialog(
            title: Text(fixedPicker == null ? 'Add New Entry' : 'Add Weight for $fixedPicker'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DayChip(day: day, isPast: isPast),
                if (isPast)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Current rates apply: Rs ${_rates.wageRate}/kg, bus fee Rs ${_rates.busFee}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                if (fixedPicker == null)
                  StreamBuilder<List<Picker>>(
                    stream: _pickers,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final names = snapshot.data!.map((p) => p.name).toList();
                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Tea Picker Name'),
                        initialValue: pickerName,
                        items: names
                            .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                            .toList(),
                        onChanged: (value) => pickerName = value,
                      );
                    },
                  ),
                TextField(
                  controller: weightController,
                  autofocus: fixedPicker != null,
                  decoration: InputDecoration(labelText: 'Weight (kg)', errorText: error),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              ElevatedButton(onPressed: submit, child: const Text('OK')),
            ],
          );
        });
      },
    );
  }

  Future<void> _deleteEntry(String recordId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _firestore.deleteEntry(recordId, deletedBy: _auth.currentUser?.displayName);
      _reportService.refreshDailySummaryNotification(cacheOnly: true);
    }
  }

  Widget _dateBar() {
    final selected = DateTime.parse(_selectedDay);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous day',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _goToDay(selected.subtract(const Duration(days: 1))),
              ),
              Flexible(
                child: TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month, color: Colors.green),
                  label: Text(
                    '${_isToday ? 'Today' : DateFormat('EEE').format(selected)}: '
                    '${displayDateFormat.format(selected)}',
                    style: const TextStyle(fontSize: 18, color: Colors.black87),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next day',
                icon: const Icon(Icons.chevron_right),
                onPressed: _isToday ? null : () => _goToDay(selected.add(const Duration(days: 1))),
              ),
            ],
          ),
          if (!_isToday)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                border: Border.all(color: Colors.amber.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.history_edu, color: Colors.amber[800]),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Past day – new entries will be saved for this date'),
                  ),
                  TextButton(
                    onPressed: () => _goToDay(DateTime.parse(_today)),
                    child: const Text('TODAY'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPickerCard(PickerDay day) {
    String pickerName = day.pickerName;
    bool deleteMode = _deleteMode[pickerName] ?? false;
    final timeFormat = DateFormat('dd-MM-yyyy h:mm a');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    pickerName,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: deleteMode,
                  onChanged: (bool value) {
                    setState(() {
                      _deleteMode[pickerName] = value;
                    });
                  },
                ),
              ],
            ),
            const Divider(),
            ...day.entries.map((r) => Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('weight: ${r.weight} kg'),
                          Text('entered by: ${r.enteredBy}'),
                          Text(
                            r.recordedLater
                                ? 'added later on: ${timeFormat.format(r.createdAt)}'
                                : 'time: ${timeFormat.format(r.createdAt)}',
                            style: r.recordedLater ? TextStyle(color: Colors.amber[900]) : null,
                          ),
                          const Divider(),
                        ],
                      ),
                    ),
                    if (r.pendingUpload)
                      const Tooltip(
                        message: 'Saved on this phone – will upload when online',
                        child: Icon(Icons.cloud_upload_outlined, size: 18, color: Colors.grey),
                      ),
                    if (deleteMode)
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteEntry(r.id),
                      ),
                  ],
                )),
            Text('Total: ${day.weight.toStringAsFixed(2)} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('wages: Rs: ${day.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (day.busFee > 0)
              Text('(includes bus fee Rs: ${day.busFee.toStringAsFixed(2)})',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _showEntryDialog(fixedPicker: pickerName),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: StreamBuilder<List<TeaEntry>>(
          stream: _dayEntries,
          builder: (context, snapshot) {
            final days = groupByPickerDay(snapshot.data ?? const []);
            final empty = days.isEmpty && snapshot.hasData;
            return ListView.builder(
              // Always scrollable so pull-to-refresh works on an empty day.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: days.length + 1 + (empty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) return _dateBar();
                if (empty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        _isToday ? 'No entries yet today' : 'No entries for this day yet',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }
                return _buildPickerCard(days[index - 1]);
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showEntryDialog,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

/// Shows which day an entry is being saved for, highlighted when it is a past day.
class _DayChip extends StatelessWidget {
  final String day;
  final bool isPast;
  const _DayChip({required this.day, required this.isPast});

  @override
  Widget build(BuildContext context) {
    final color = isPast ? Colors.amber.shade800 : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(isPast ? Icons.history_edu : Icons.today, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${isPast ? 'Picked on' : 'Today'}: ${DateFormat('EEE, dd-MM-yyyy').format(DateTime.parse(day))}',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}
