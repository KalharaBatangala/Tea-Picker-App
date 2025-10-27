
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/db_helper.dart';
import 'firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';




class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DBHelper _db = DBHelper();
  final FirestoreService _firestore = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> _pickers = [];
  double _wageRate = 40.0;
  double _busFee = 0;

  Map<String, bool> _deleteMode = {};

  @override
  void initState() {
    super.initState();
    _archiveIfNewDay();
    _loadData();
  }

  Future<void> _archiveIfNewDay() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String today = DateFormat('dd-MM-yyyy').format(DateTime.now());
    String lastArchive = prefs.getString('last_archive_date') ?? '';
    if (lastArchive != today) {
      await _db.archiveRecords();
      await _firestore.syncData();
      prefs.setString('last_archive_date', today);
    }
  }

  Future<void> _loadData() async {
    _wageRate = await _db.getWageRate();
    _busFee = await _db.getBusFee();
    _pickers = await _db.getAllPickersWithRecords();
    for (var picker in _pickers) {
      _deleteMode[picker['picker_name']] = false;
    }
    setState(() {});
  }

  // NEW: Method for pull-to-refresh to sync with Firestore first
  Future<void> _refreshData() async {
    await _firestore.syncData(); // Sync remote changes
    await _loadData(); // Then reload local UI
  }

  Future<void> _showAddPickerDialog() async {
    String? pickerName;
    double? weight;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add New Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _db.getPickers(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  List<String> names = snapshot.data!.map((p) => p['name'] as String).toList();
                  return DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Tea Picker Name'),
                    items: names.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
                    onChanged: (value) {
                      pickerName = value;
                    },
                  );
                },
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
                keyboardType: TextInputType.number,
                onChanged: (value) => weight = double.tryParse(value),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (pickerName != null && weight != null && weight! > 0) {
                  final String recordId = Uuid().v4();
                  String enteredBy = _auth.currentUser?.displayName ?? 'Unknown';
                  String timestamp = DateFormat('dd-MM-yyyy h:mm a').format(DateTime.now());
                  double wages = weight! * _wageRate + _busFee;
                  await _db.insertRecord(pickerName!, weight!, enteredBy, timestamp, wages, recordId );
                  await _firestore.uploadRecord({
                    'id': recordId,
                    'picker_name': pickerName,
                    'weight': weight,
                    'entered_by': enteredBy,
                    'timestamp': timestamp,
                    'wages': wages,
                    // 'user_uid': _auth.currentUser?.uid,
                  });
                  _loadData();
                  Navigator.pop(context);
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddWeightDialog(String pickerName) async {
    double? weight;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add Weight for $pickerName'),
          content: TextField(
            decoration: const InputDecoration(labelText: 'Weight (kg)'),
            keyboardType: TextInputType.number,
            onChanged: (value) => weight = double.tryParse(value),
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (weight != null && weight! > 0) {
                  final String recordId = Uuid().v4();
                  String enteredBy = _auth.currentUser?.displayName ?? 'Unknown';
                  String timestamp = DateFormat('dd-MM-yyyy h:mm a').format(DateTime.now());
                  double wages = weight! * _wageRate + _busFee;
                  await _db.insertRecord(pickerName, weight!, enteredBy, timestamp, wages, recordId);
                  await _firestore.uploadRecord({
                    'id': recordId,
                    'picker_name': pickerName,
                    'weight': weight,
                    'entered_by': enteredBy,
                    'timestamp': timestamp,
                    'wages': wages,
                    // 'user_uid': _auth.currentUser?.uid,
                  });
                  _loadData();
                  Navigator.pop(context);
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteEntry(String pickerName, String recordId) async {
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
      await _db.deleteRecord(recordId);
      await _firestore.deleteRecord(recordId);
      _loadData();
    }
  }

  Widget _buildPickerCard(Map<String, dynamic> picker) {
    String pickerName = picker['picker_name'];
    bool deleteMode = _deleteMode[pickerName] ?? false;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _db.getRecordsForPicker(pickerName),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        List<Map<String, dynamic>> records = snapshot.data!;
        double totalKg = records.fold(0.0, (sum, r) => sum + r['weight']);
        double totalWages = records.fold(0.0, (sum, r) => sum + r['wages']);
        //totalWages = totalWages + _busFee;
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
                    Center(
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
                ...records.map((r) => Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('weight: ${r['weight']} kg'),
                          Text('entered by: ${r['entered_by']}'),
                          Text('time: ${r['timestamp']}'),
                          const Divider(),
                        ],
                      ),
                    ),
                    if (deleteMode)
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteEntry(pickerName,  r['record_id']),
                      ),
                  ],
                )),
                Text('Total: $totalKg kg', style: TextStyle(fontWeight: FontWeight.bold),),
                Text('wages: Rs: ${totalWages.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold),),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showAddWeightDialog(pickerName),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String currentDate = DateFormat('dd-MM-yyyy').format(DateTime.now());
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshData, // UPDATED: Use the new refresh method
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Today: $currentDate', style: const TextStyle(fontSize: 18)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _pickers.length,
              itemBuilder: (context, index) => _buildPickerCard(_pickers[index]),
            ),
          ),
        ],
      ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPickerDialog,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}