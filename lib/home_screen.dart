import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'models/tea_entry.dart';
import './services/report_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FirestoreService _firestore = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ReportService _reportService = ReportService();

  late String _today;
  late Stream<List<TeaEntry>> _todayEntries;
  late final Stream<List<Picker>> _pickers = _firestore.pickerList();
  StreamSubscription<Rates>? _ratesSub;
  Rates _rates = Rates.defaults;
  Timer? _dayTimer;

  final Map<String, bool> _deleteMode = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setDay();
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

  void _setDay() {
    _today = dayKey(DateTime.now());
    _todayEntries = _firestore.entriesForDay(_today);
  }

  void _checkNewDay() {
    if (dayKey(DateTime.now()) != _today && mounted) setState(_setDay);
  }

  Future<void> _refreshData() =>
      _firestore.refreshFromServer(FirestoreService.entries.where('date', isEqualTo: _today));

  void _saveEntry(String pickerName, double weight) {
    final now = DateTime.now();
    _firestore.addEntry(TeaEntry(
      id: const Uuid().v4(),
      pickerName: pickerName,
      weight: weight,
      enteredBy: _auth.currentUser?.displayName ?? 'Unknown',
      createdAt: now,
      date: dayKey(now),
      wages: weight * _rates.wageRate,
      rate: _rates.wageRate,
      busFee: _rates.busFee,
    ));
    _reportService.refreshDailySummaryNotification(cacheOnly: true);
  }

  /// Shared by the "+" floating button (choose picker) and each card's "+".
  Future<void> _showEntryDialog({String? fixedPicker}) async {
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
              _saveEntry(pickerName!, weight);
            }
          }

          return AlertDialog(
            title: Text(fixedPicker == null ? 'Add New Entry' : 'Add Weight for $fixedPicker'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (fixedPicker == null)
                  StreamBuilder<List<Picker>>(
                    stream: _pickers,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const CircularProgressIndicator();
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
                          Text('time: ${timeFormat.format(r.createdAt)}'),
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
    String currentDate = DateFormat('dd-MM-yyyy').format(DateTime.now());
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: StreamBuilder<List<TeaEntry>>(
          stream: _todayEntries,
          builder: (context, snapshot) {
            final days = groupByPickerDay(snapshot.data ?? const []);
            return ListView.builder(
              // Always scrollable so pull-to-refresh works on an empty day.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: days.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(child: Text('Today: $currentDate', style: const TextStyle(fontSize: 18))),
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
