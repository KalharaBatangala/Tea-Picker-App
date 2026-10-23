import 'dart:async';

import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'services/migration_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirestoreService _firestore = FirestoreService();
  StreamSubscription<Rates>? _ratesSub;

  bool _isWageEditable = false;
  bool _isBusEditable = false;
  bool _importing = false;

  final TextEditingController _wageController = TextEditingController();
  final TextEditingController _busController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Rates are shared by all phones; follow changes made elsewhere unless
    // the user is currently editing that field.
    _ratesSub = _firestore.rates().listen((rates) {
      if (!_isWageEditable) _wageController.text = rates.wageRate.toString();
      if (!_isBusEditable) _busController.text = rates.busFee.toString();
    });
  }

  @override
  void dispose() {
    _ratesSub?.cancel();
    _wageController.dispose();
    _busController.dispose();
    super.dispose();
  }

  void _showMessage(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _saveWageRate() {
    double? value = double.tryParse(_wageController.text.trim().replaceAll(',', '.'));
    if (value != null && value > 0) {
      _firestore.saveWageRate(value);
      _showMessage('Wage rate updated successfully!');
    } else {
      _showMessage('Please enter a valid wage rate');
    }
  }

  void _saveBusFee() {
    double? value = double.tryParse(_busController.text.trim().replaceAll(',', '.'));
    if (value != null && value >= 0) {
      _firestore.saveBusFee(value);
      _showMessage('Bus fee updated successfully!');
    } else {
      _showMessage('Please enter a valid bus fee');
    }
  }

  Future<void> _importOldData() async {
    setState(() => _importing = true);
    final result = await MigrationService.run(force: true);
    if (!mounted) return;
    setState(() => _importing = false);
    _showMessage(result ?? 'Old data checked.');
  }

  Widget _buildEditableRow({
    required String label,
    required bool isEditable,
    required ValueChanged<bool> onToggle,
    required TextEditingController controller,
    required VoidCallback onSave,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Switch(
                        value: isEditable,
                        onChanged: onToggle,
                      ),
                    ],
                  ),
                  TextField(
                    controller: controller,
                    enabled: isEditable,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: label,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: (_) => onSave(),
                  ),
                ],
              ),
            ),
            if (isEditable)
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.green),
                onPressed: onSave,
                tooltip: 'Save',
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildEditableRow(
            label: 'Wage Rate (Rs/kg)',
            isEditable: _isWageEditable,
            onToggle: (val) {
              setState(() => _isWageEditable = val);
              if (!val) _saveWageRate(); // Auto-save on toggle off
            },
            controller: _wageController,
            onSave: () {
              _saveWageRate();
              setState(() => _isWageEditable = false);
            },
          ),
          _buildEditableRow(
            label: 'Bus Fee (Rs)',
            isEditable: _isBusEditable,
            onToggle: (val) {
              setState(() => _isBusEditable = val);
              if (!val) _saveBusFee(); // Auto-save on toggle off
            },
            controller: _busController,
            onSave: () {
              _saveBusFee();
              setState(() => _isBusEditable = false);
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'Rates are shared by all family phones. The bus fee is added once per picker per day. '
              'Changing a rate only affects new entries.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.cloud_sync, color: Colors.green),
              title: const Text('Import data from old app'),
              subtitle: const Text('Safe to repeat – only adds records that are missing'),
              trailing: _importing
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: _importing ? null : _importOldData,
            ),
          ),
        ],
      ),
    );
  }
}
