import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'firestore_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DBHelper _db = DBHelper();
  final FirestoreService _firestore = FirestoreService();
  List<Map<String, dynamic>> _pickers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _pickers = await _db.getAllHistoricalPickers();
    setState(() {});
  }

  Future<void> _deleteRecord(String pickerName, int id, String timestamp) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this record?'),
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
      await _db.deleteHistoricalRecord(id);
      await _firestore.deleteHistoricalRecord(pickerName, timestamp);
      _loadData();
    }
  }

  Widget _buildPickerCard(Map<String, dynamic> picker) {
    String pickerName = picker['picker_name'];
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _db.getHistoricalRecordsForPicker(pickerName),
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
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteRecord(pickerName, r['id'], r['timestamp']),
                    ),
                    const Divider(),
                  ],
                )),
                Text('Total: $totalKg kg'),
                Text('wages: Rs: ${totalWages.toStringAsFixed(2)}'),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: _pickers.length,
        itemBuilder: (context, index) => _buildPickerCard(_pickers[index]),
      ),
    );
  }
}