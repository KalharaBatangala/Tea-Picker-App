import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'firestore_service.dart';

class TeaPickersScreen extends StatefulWidget {
  const TeaPickersScreen({super.key});

  @override
  _TeaPickersScreenState createState() => _TeaPickersScreenState();
}

class _TeaPickersScreenState extends State<TeaPickersScreen> {
  final DBHelper _db = DBHelper();
  final FirestoreService _firestore = FirestoreService();
  List<Map<String, dynamic>> _pickers = [];

  @override
  void initState() {
    super.initState();
    _loadPickers();
  }

  Future<void> _loadPickers() async {
    _pickers = await _db.getPickers();
    setState(() {});
  }

  Future<void> _showAddPickerDialog() async {
    String? name;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Tea Picker'),
          content: TextField(
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (value) => name = value.trim(),
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (name != null && name!.isNotEmpty) {
                  await _db.insertPicker(name!);
                  await _firestore.addPicker(name!);
                  _loadPickers();
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deletePicker(int id, String name) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete $name?'),
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
      await _db.deletePicker(id);
      await _firestore.deletePicker(name);
      _loadPickers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: _pickers.length,
        itemBuilder: (context, index) {
          String name = _pickers[index]['name'];
          int id = _pickers[index]['id'];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: ListTile(
              title: Text(name),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => _deletePicker(id, name),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPickerDialog,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}