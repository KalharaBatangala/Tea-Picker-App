import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/db_helper.dart';
import 'firestore_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _wageRate = await _db.getWageRate();
    _pickers = await _db.getAllPickersWithRecords();
    setState(() {});
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
                  String enteredBy = _auth.currentUser?.displayName ?? 'Unknown';
                  String timestamp = DateFormat('dd-MM-yyyy h:mm a').format(DateTime.now());
                  double wages = weight! * _wageRate;
                  await _db.insertRecord(pickerName!, weight!, enteredBy, timestamp, wages);
                  await _firestore.uploadRecord({
                    'picker_name': pickerName,
                    'weight': weight,
                    'entered_by': enteredBy,
                    'timestamp': timestamp,
                    'wages': wages,
                    'user_uid': _auth.currentUser?.uid,
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
                  String enteredBy = _auth.currentUser?.displayName ?? 'Unknown';
                  String timestamp = DateFormat('dd-MM-yyyy h:mm a').format(DateTime.now());
                  double wages = weight! * _wageRate;
                  await _db.insertRecord(pickerName, weight!, enteredBy, timestamp, wages);
                  await _firestore.uploadRecord({
                    'picker_name': pickerName,
                    'weight': weight,
                    'entered_by': enteredBy,
                    'timestamp': timestamp,
                    'wages': wages,
                    'user_uid': _auth.currentUser?.uid,
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

  Widget _buildPickerCard(Map<String, dynamic> picker) {
    String pickerName = picker['picker_name'];
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _db.getRecordsForPicker(pickerName),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        List<Map<String, dynamic>> records = snapshot.data!;
        double totalKg = records.fold(0.0, (sum, r) => sum + r['weight']);
        double totalWages = records.fold(0.0, (sum, r) => sum + r['wages']);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    pickerName,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(),
                ...records.map((r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('weight: ${r['weight']} kg'),
                    Text('entered by: ${r['entered_by']}'),
                    Text('time: ${r['timestamp']}'),
                    const Divider(),
                  ],
                )),
                Text('Total: $totalKg kg'),
                Text('wages: Rs: ${totalWages.toStringAsFixed(2)}'),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Current Date: $currentDate', style: const TextStyle(fontSize: 18)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _pickers.length,
              itemBuilder: (context, index) => _buildPickerCard(_pickers[index]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPickerDialog,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}