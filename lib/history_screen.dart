import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'firestore_service.dart';
import 'models/tea_entry.dart';
import 'services/report_service.dart';

final NumberFormat _kg = NumberFormat('#,##0.##');
final NumberFormat _rs = NumberFormat('#,##0.00');

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final FirestoreService _firestore = FirestoreService();
  final ReportService _reportService = ReportService();

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Stream<List<TeaEntry>> _entries;
  String? _pickerFilter; // picker key, null = all
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _entries = _firestore.entriesForMonth(monthKey(_month));
  }

  void _changeMonth(DateTime month) {
    setState(() {
      _month = DateTime(month.year, month.month);
      _entries = _firestore.entriesForMonth(monthKey(_month));
    });
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final months = List.generate(36, (i) => DateTime(now.year, now.month - i));
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select month'),
        children: [
          SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView(
              children: months
                  .map((m) => ListTile(
                        title: Text(DateFormat('MMMM yyyy').format(m)),
                        selected: m == _month,
                        onTap: () => Navigator.pop(context, m),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
    if (picked != null) _changeMonth(picked);
  }

  Future<void> _deleteRecord(TeaEntry entry) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete ${entry.weight} kg for ${entry.pickerName} on '
            '${DateFormat('dd-MM-yyyy h:mm a').format(entry.createdAt)}?'),
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
      _firestore.deleteEntry(entry.id, deletedBy: FirebaseAuth.instance.currentUser?.displayName);
    }
  }

  Future<void> _export(List<PickerDay> days, String? pickerName, {required bool pdf}) async {
    if (days.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No records to export for this selection')));
      return;
    }
    setState(() => _exporting = true);
    try {
      if (pdf) {
        await _reportService.sharePdf(
            month: monthKey(_month),
            monthLabel: DateFormat('MMMM yyyy').format(_month),
            pickerName: pickerName,
            days: days);
      } else {
        await _reportService.shareCsv(month: monthKey(_month), pickerName: pickerName, days: days);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _monthBar() {
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _changeMonth(DateTime(_month.year, _month.month - 1)),
        ),
        TextButton.icon(
          onPressed: _pickMonth,
          icon: const Icon(Icons.calendar_month, color: Colors.green),
          label: Text(DateFormat('MMMM yyyy').format(_month),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: isCurrent ? null : () => _changeMonth(DateTime(_month.year, _month.month + 1)),
        ),
      ],
    );
  }

  Widget _filterBar(List<PickerSummary> summaries, List<PickerDay> filteredDays, String? pickerName) {
    // A filter left over from another month may not exist here; keep it visible anyway.
    final names = {for (final s in summaries) pickerKey(s.pickerName): s.pickerName};
    if (_pickerFilter != null && !names.containsKey(_pickerFilter)) {
      names[_pickerFilter!] = pickerName ?? _pickerFilter!;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              key: ValueKey('filter-$_pickerFilter-${names.length}'),
              initialValue: _pickerFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tea picker',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All pickers')),
                ...names.entries.map((e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
              ],
              onChanged: (v) => setState(() => _pickerFilter = v),
            ),
          ),
          const SizedBox(width: 8),
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            IconButton(
              tooltip: 'Export PDF',
              icon: const Icon(Icons.picture_as_pdf, color: Colors.green),
              onPressed: () => _export(filteredDays, pickerName, pdf: true),
            ),
            IconButton(
              tooltip: 'Export CSV',
              icon: const Icon(Icons.table_chart, color: Colors.green),
              onPressed: () => _export(filteredDays, pickerName, pdf: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _totalsCard(List<PickerDay> days) {
    final weight = days.fold(0.0, (s, d) => s + d.weight);
    final pay = days.fold(0.0, (s, d) => s + d.total);
    final bus = days.fold(0.0, (s, d) => s + d.busFee);
    final entries = days.fold(0, (s, d) => s + d.entries.length);
    final workDays = days.map((d) => d.date).toSet().length;

    Widget stat(String label, String value) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ]),
        );

    return Card(
      color: Colors.green[50],
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(children: [
          Row(children: [stat('Total weight', '${_kg.format(weight)} kg'), stat('Total pay', 'Rs ${_rs.format(pay)}')]),
          const SizedBox(height: 10),
          Row(children: [
            stat('Entries', '$entries'),
            stat('Days', '$workDays'),
            stat('Bus fees', 'Rs ${_rs.format(bus)}'),
          ]),
        ]),
      ),
    );
  }

  Widget _pickerSummaryTable(List<PickerSummary> summaries) {
    const header = TextStyle(fontWeight: FontWeight.bold, color: Colors.white);
    Widget row(List<String> cells, {TextStyle? style, VoidCallback? onTap, Color? color}) => InkWell(
          onTap: onTap,
          child: Container(
            color: color,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Row(children: [
              Expanded(flex: 4, child: Text(cells[0], style: style)),
              Expanded(flex: 2, child: Text(cells[1], style: style, textAlign: TextAlign.right)),
              Expanded(flex: 3, child: Text(cells[2], style: style, textAlign: TextAlign.right)),
              Expanded(flex: 4, child: Text(cells[3], style: style, textAlign: TextAlign.right)),
            ]),
          ),
        );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        row(['Picker', 'Days', 'Kg', 'Rs'], style: header, color: Colors.green),
        for (var i = 0; i < summaries.length; i++)
          row(
            [summaries[i].pickerName, '${summaries[i].dayCount}', _kg.format(summaries[i].weight),
              _rs.format(summaries[i].total)],
            color: i.isOdd ? Colors.grey[100] : null,
            onTap: () => setState(() => _pickerFilter = pickerKey(summaries[i].pickerName)),
          ),
      ]),
    );
  }

  Widget _dateHeader(String date, List<PickerDay> days) {
    final d = DateTime.parse(date);
    final kg = days.fold(0.0, (s, x) => s + x.weight);
    final rs = days.fold(0.0, (s, x) => s + x.total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(children: [
        Expanded(
          child: Text(DateFormat('EEE, dd-MM-yyyy').format(d),
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
        ),
        Text('${_kg.format(kg)} kg  •  Rs ${_rs.format(rs)}', style: const TextStyle(color: Colors.black54)),
      ]),
    );
  }

  Widget _pickerDayTile(PickerDay day, {required bool showName}) {
    final timeFormat = DateFormat('h:mm a');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
      child: ExpansionTile(
        shape: const Border(),
        title: Text(showName ? day.pickerName : '${day.entries.length} entr${day.entries.length == 1 ? 'y' : 'ies'}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${_kg.format(day.weight)} kg'
            '${day.busFee > 0 ? '  •  bus Rs ${_rs.format(day.busFee)}' : ''}'),
        trailing: Text('Rs ${_rs.format(day.total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        children: day.entries
            .map((e) => ListTile(
                  dense: true,
                  title: Text('${e.weight} kg  •  ${timeFormat.format(e.createdAt)}'),
                  subtitle: Text('entered by: ${e.enteredBy}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (e.pendingUpload)
                      const Icon(Icons.cloud_upload_outlined, size: 18, color: Colors.grey),
                    IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteRecord(e)),
                  ]),
                ))
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<TeaEntry>>(
        stream: _entries,
        builder: (context, snapshot) {
          final allDays = groupByPickerDay(snapshot.data ?? const []);
          final summaries = summarisePickers(allDays);
          final days = _pickerFilter == null
              ? allDays
              : allDays.where((d) => pickerKey(d.pickerName) == _pickerFilter).toList();
          final pickerName = _pickerFilter == null
              ? null
              : (days.isNotEmpty ? days.first.pickerName : _pickerFilter);

          // Newest day first, grouped under date headers.
          final Map<String, List<PickerDay>> byDate = {};
          for (final d in days.reversed) {
            byDate.putIfAbsent(d.date, () => []).add(d);
          }
          final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

          final items = <Widget Function()>[
            _monthBar,
            () => _filterBar(summaries, days, pickerName),
            () => _totalsCard(days),
            if (_pickerFilter == null && summaries.isNotEmpty) () => _pickerSummaryTable(summaries),
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
              () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (days.isEmpty)
              () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No records for this month', style: TextStyle(color: Colors.grey))),
                  ),
            for (final date in dates) ...[
              () => _dateHeader(date, byDate[date]!),
              for (final d in byDate[date]!) () => _pickerDayTile(d, showName: _pickerFilter == null),
            ],
          ];

          return RefreshIndicator(
            onRefresh: () => _firestore.refreshFromServer(
                FirestoreService.entries.where('month', isEqualTo: monthKey(_month))),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: items.length,
              itemBuilder: (context, i) => items[i](),
            ),
          );
        },
      ),
    );
  }
}
