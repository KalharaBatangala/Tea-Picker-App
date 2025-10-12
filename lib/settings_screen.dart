import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DBHelper _db = DBHelper();

  double _wageRate = 0.0;
  double _busFee = 0.0;

  bool _isWageEditable = false;
  bool _isBusEditable = false;

  final TextEditingController _wageController = TextEditingController();
  final TextEditingController _busController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    double wageRate = await _db.getWageRate();
    double busFee = await _db.getBusFee();
    setState(() {
      _wageRate = wageRate;
      _busFee = busFee;
      _wageController.text = wageRate.toString();
      _busController.text = busFee.toString();
    });
  }

  Future<void> _saveWageRate() async {
    double? value = double.tryParse(_wageController.text);
    if (value != null && value > 0) {
      await _db.updateWageRate(value);
      setState(() => _wageRate = value);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wage rate updated successfully!')),
      );
    }
  }

  Future<void> _saveBusFee() async {
    double? value = double.tryParse(_busController.text);
    if (value != null && value >= 0) {
      await _db.updateBusFee(value);
      setState(() => _busFee = value);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bus fee updated successfully!')),
      );
    }
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
                    keyboardType: TextInputType.number,
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
        ],
      ),
    );
  }
}
