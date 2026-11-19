import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models/tea_entry.dart';

class TeaPickersScreen extends StatefulWidget {
  const TeaPickersScreen({super.key});

  @override
  State<TeaPickersScreen> createState() => _TeaPickersScreenState();
}

class _TeaPickersScreenState extends State<TeaPickersScreen> {
  final FirestoreService _firestore = FirestoreService();
  late final Stream<List<Picker>> _pickerStream = _firestore.pickerList();
  List<Picker> _pickers = [];

  Future<void> _showAddPickerDialog() async {
    String? name;
    String? error;
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          void add() {
            if (name == null || name!.isEmpty) return;
            if (_pickers.any((p) => p.id == pickerKey(name!))) {
              setDialogState(() => error = '$name is already in the list');
              return;
            }
            Navigator.pop(context);
            _firestore.addPicker(name!);
          }

          return AlertDialog(
            title: const Text('Add Tea Picker'),
            content: TextField(
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Name', errorText: error),
              onChanged: (value) => name = value.trim(),
              onSubmitted: (_) => add(),
            ),
            actions: [
              ElevatedButton(onPressed: add, child: const Text('Add')),
            ],
          );
        });
      },
    );
  }

  Future<void> _deletePicker(Picker picker) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete ${picker.name}?'),
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
    if (confirm == true) _firestore.deletePicker(picker.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Picker>>(
        stream: _pickerStream,
        builder: (context, snapshot) {
          _pickers = snapshot.data ?? const [];
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: _pickers.length,
            itemBuilder: (context, index) {
              final picker = _pickers[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: ListTile(
                  title: Text(picker.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deletePicker(picker),
                  ),
                ),
              );
            },
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
