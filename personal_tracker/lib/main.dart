import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'storage_helper.dart';

void main() => runApp(const PersonalTrackerApp());

const purple = Color(0xFF315FEA);
const teal = Color(0xFF159D91);
const orange = Color(0xFFF2A34A);
const ink = Color(0xFF1E293B);
const muted = Color(0xFF64748B);

class PersonalTrackerApp extends StatelessWidget {
  const PersonalTrackerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Momentum Personal Tracker',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: purple),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF6F7FB),
        foregroundColor: ink,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE8EBF2)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F3F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E8EF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: purple, width: 1.5),
        ),
      ),
    ),
    home: const DashboardPage(),
  );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<Map<String, dynamic>> records = [];
  bool loading = true, saving = false;
  int page = 0;

  @override
  void initState() {
    super.initState();
    loadRecords();
  }

  String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String get today => dateKey(DateTime.now());
  String money(double n) => '₹${n.toStringAsFixed(2)}';

  List<String> dates(Map<String, dynamic> r) {
    final raw = r['completionDates'];
    if (raw is List)
      return raw.map((e) => e.toString()).toSet().toList()..sort();
    return r['completed'] == true ? [today] : [];
  }

  bool doneToday(Map<String, dynamic> r) => dates(r).contains(today);

  Future<void> loadRecords() async {
    try {
      final data = await StorageHelper.loadRecords();
      if (!mounted) return;
      setState(() {
        records = data;
        loading = false;
      });
    } catch (e) {
      debugPrint('Load error: $e');
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load saved records.')),
      );
    }
  }

  int count(String c) => records.where((r) => r['category'] == c).length;
  int get activities => count('Activity');
  int get habits => count('Habit');
  int get expenses => count('Expense');
  int get habitsDone =>
      records.where((r) => r['category'] == 'Habit' && doneToday(r)).length;
  double get progress => habits == 0 ? 0 : habitsDone / habits;
  double get totalSpent => records
      .where((r) => r['category'] == 'Expense')
      .fold<double>(
        0,
        (sum, r) => sum + (double.tryParse(r['amount']?.toString() ?? '') ?? 0),
      );

  Color colorFor(String c) => c == 'Habit'
      ? teal
      : c == 'Expense'
      ? orange
      : purple;
  IconData iconFor(String c) => c == 'Habit'
      ? Icons.task_alt
      : c == 'Expense'
      ? Icons.account_balance_wallet_outlined
      : Icons.monitor_heart_outlined;

  int streak(Map<String, dynamic> r) {
    final completed = dates(r).toSet();
    var day = DateTime.now();
    if (!completed.contains(dateKey(day))) {
      day = day.subtract(const Duration(days: 1));
      if (!completed.contains(dateKey(day))) return 0;
    }
    var n = 0;
    while (completed.contains(dateKey(day))) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  int longestStreak(Map<String, dynamic> r) {
    final sorted = dates(r).toSet().toList()..sort();
    var best = 0, run = 0;
    DateTime? previous;
    for (final s in sorted) {
      final d0 = DateTime.tryParse(s);
      if (d0 == null) continue;
      final d = DateTime(d0.year, d0.month, d0.day);
      if (previous != null && d.difference(previous).inDays == 1) {
        run++;
      } else if (previous != null && d.difference(previous).inDays == 0) {
        continue;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      previous = d;
    }
    return best;
  }

  Future<void> save(List<Map<String, dynamic>> next, String message) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await StorageHelper.saveRecords(next);
      if (!mounted) return;
      setState(() {
        records = next;
        saving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e, st) {
      debugPrint('Save error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> addRecord({String? category}) async {
    if (saving) return;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddRecordPage(initialCategory: category),
      ),
    );
    if (!mounted || result == null) return;
    final next = records.map((r) => Map<String, dynamic>.from(r)).toList()
      ..add(result);
    await save(next, 'Record added successfully!');
  }

  Future<void> editRecord(int i) async {
    if (saving || i < 0 || i >= records.length) return;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddRecordPage(
          existingRecord: Map<String, dynamic>.from(records[i]),
        ),
      ),
    );
    if (!mounted || result == null) return;
    final next = records.map((r) => Map<String, dynamic>.from(r)).toList();
    next[i] = result;
    await save(next, 'Record updated successfully!');
  }

  Future<void> toggleHabit(int i, bool value) async {
    if (saving || i < 0 || i >= records.length) return;
    final next = records.map((r) => Map<String, dynamic>.from(r)).toList();
    if (next[i]['category'] != 'Habit') return;
    final completed = dates(next[i]);
    if (value && !completed.contains(today)) completed.add(today);
    if (!value) completed.remove(today);
    completed.sort();
    next[i]['completionDates'] = completed;
    next[i]['completed'] = completed.contains(today);
    next[i]['updatedAt'] = DateTime.now().toIso8601String();
    await save(
      next,
      value ? 'Habit marked complete!' : 'Habit marked incomplete.',
    );
  }

  Future<void> deleteRecord(int i) async {
    if (saving || i < 0 || i >= records.length) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text('Delete "${records[i]['title']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || yes != true) return;
    final next = records.map((r) => Map<String, dynamic>.from(r)).toList()
      ..removeAt(i);
    await save(next, 'Record deleted successfully!');
  }

  String get displayDate {
    final d = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final views = [_home(), _recordsPage(), _habitsPage()];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'M O M E N T U M',
              style: TextStyle(
                color: purple,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            Text(
              [
                'Your day, organized',
                'Your records',
                'Build your habits',
              ][page],
              style: const TextStyle(
                color: ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 18),
            child: CircleAvatar(
              backgroundColor: Color(0xFFE5ECFF),
              foregroundColor: purple,
              child: Text('M', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: page, children: views),
      floatingActionButton: FloatingActionButton(
        onPressed: saving ? null : () => addRecord(),
        backgroundColor: purple,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 28),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (i) => setState(() => page = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE4EBFF),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.format_list_bulleted),
            label: 'Records',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt_outlined),
            selectedIcon: Icon(Icons.task_alt),
            label: 'Habits',
          ),
        ],
      ),
    );
  }

  Widget _home() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final recent = records.asMap().entries.toList().reversed.take(4).toList();
    return RefreshIndicator(
      onRefresh: loadRecords,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 105),
        children: [
          Text(
            greeting,
            style: const TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w900,
              color: ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(displayDate, style: const TextStyle(color: muted)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF245BE8), Color(0xFF3C83F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: purple.withValues(alpha: .16),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "TODAY'S MOMENTUM",
                  style: TextStyle(
                    color: Color(0xFFDCE7FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  records.isEmpty
                      ? 'Start your first check-in'
                      : 'You are building momentum',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  records.isEmpty
                      ? 'Add an activity, expense or habit to begin.'
                      : 'You have ${records.length} saved records. Keep going!',
                  style: const TextStyle(color: Colors.white, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'SPENT TOTAL',
                  money(totalSpent),
                  Icons.account_balance_wallet_outlined,
                  purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _metric(
                  'HABITS DONE',
                  '$habitsDone/$habits',
                  Icons.check_circle_outline,
                  teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Quick add',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Capture it while it is fresh',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _quick('Activity', Icons.monitor_heart_outlined, purple),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _quick(
                  'Expense',
                  Icons.account_balance_wallet_outlined,
                  orange,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(child: _quick('Habit', Icons.task_alt_outlined, teal)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Today',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => page = 1),
                child: const Text('See all'),
              ),
            ],
          ),
          const Text(
            'Your latest check-ins',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            _empty(
              'Nothing logged yet',
              'Add your first activity, expense or habit.',
              Icons.auto_awesome_outlined,
            )
          else
            ...recent.map((e) => _recordCard(e.key, e.value)),
          const SizedBox(height: 20),
          _categoryTable(),
          const SizedBox(height: 16),
          _pieCard(),
        ],
      ),
    );
  }

  Widget _metric(String title, String value, IconData icon, Color color) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .4,
                ),
              ),
              const SizedBox(height: 7),
              FittedBox(
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _quick(String category, IconData icon, Color color) => InkWell(
    onTap: () => addRecord(category: category),
    borderRadius: BorderRadius.circular(17),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 9),
            Text(
              category,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _recordCard(int i, Map<String, dynamic> r) {
    final category = r['category']?.toString() ?? 'Activity';
    final color = colorFor(category);
    final amount = double.tryParse(r['amount']?.toString() ?? '') ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          foregroundColor: color,
          child: Icon(iconFor(category)),
        ),
        title: Text(
          r['title']?.toString() ?? 'Untitled',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          category == 'Expense' ? '$category • ${money(amount)}' : category,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        trailing: PopupMenuButton<String>(
          enabled: !saving,
          onSelected: (v) {
            if (v == 'edit') editRecord(i);
            if (v == 'delete') deleteRecord(i);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Widget _categoryTable() {
    final items = [
      ('Activity', activities, Icons.monitor_heart_outlined, purple),
      ('Habit', habits, Icons.task_alt_outlined, teal),
      ('Expense', expenses, Icons.account_balance_wallet_outlined, orange),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Category overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 13),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1),
              },
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: Color(0xFFF5F7FB)),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Category',
                        style: TextStyle(
                          color: muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Count',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                ...items.map(
                  (x) => TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(x.$3, color: x.$4, size: 20),
                            const SizedBox(width: 9),
                            Text(
                              x.$1,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '${x.$2}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: x.$4,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pieCard() {
    final values = [
      activities.toDouble(),
      habits.toDouble(),
      expenses.toDouble(),
    ];
    const colors = [purple, teal, orange];
    const labels = ['Activity', 'Habit', 'Expense'];
    final total = values.fold<double>(0, (a, b) => a + b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Record distribution',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            if (total == 0)
              const Text(
                'Add records to see your chart.',
                style: TextStyle(color: muted),
              )
            else
              Row(
                children: [
                  SizedBox(
                    width: 130,
                    height: 130,
                    child: PieChart(
                      PieChartData(
                        sections: List.generate(
                          3,
                          (i) => PieChartSectionData(
                            value: values[i],
                            color: colors[i],
                            title: values[i] == 0 ? '' : '${values[i].toInt()}',
                            radius: 42,
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ).where((s) => s.value > 0).toList(),
                        centerSpaceRadius: 24,
                        sectionsSpace: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: List.generate(
                        3,
                        (i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 5,
                                backgroundColor: colors[i],
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(labels[i])),
                              Text(
                                '${values[i].toInt()}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _empty(String title, String subtitle, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFF78A4F5)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted),
          ),
        ],
      ),
    ),
  );

  Widget _recordsPage() => _RecordsView(
    records: records,
    saving: saving,
    colorFor: colorFor,
    iconFor: iconFor,
    money: money,
    onEdit: editRecord,
    onDelete: deleteRecord,
    onAdd: () => addRecord(),
  );

  Widget _habitsPage() {
    final list = records
        .asMap()
        .entries
        .where((e) => e.value['category'] == 'Habit')
        .toList();
    final week = List<DateTime>.generate(7, (i) {
      final d = DateTime.now();
      return DateTime(d.year, d.month, d.day).subtract(Duration(days: 6 - i));
    });
    return RefreshIndicator(
      onRefresh: loadRecords,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 105),
        children: [
          const Text(
            'Your habits',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Small routines. Meaningful progress.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "Today's progress",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          color: teal,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '$habitsDone of $habits habits completed',
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 13),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 11,
                      color: teal,
                      backgroundColor: teal.withValues(alpha: .12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            _empty(
              'No habits yet',
              'Tap + to add your first habit.',
              Icons.task_alt_outlined,
            )
          else
            ...list.map((e) {
              final i = e.key;
              final r = e.value;
              final completed = dates(r).toSet();
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: doneToday(r),
                            activeColor: teal,
                            onChanged: saving
                                ? null
                                : (v) {
                                    if (v != null) toggleHabit(i, v);
                                  },
                          ),
                          Expanded(
                            child: Text(
                              r['title']?.toString() ?? 'Habit',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.local_fire_department,
                            color: orange,
                            size: 20,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${streak(r)} day streak',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') editRecord(i);
                              if (v == 'delete') deleteRecord(i);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Longest streak: ${longestStreak(r)} days',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: week.map((d) {
                          final key = dateKey(d);
                          final done = completed.contains(key);
                          final isToday = key == today;
                          const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                          return Column(
                            children: [
                              Text(
                                letters[d.weekday - 1],
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Container(
                                width: 29,
                                height: 29,
                                decoration: BoxDecoration(
                                  color: done ? teal : const Color(0xFFF0F2F6),
                                  borderRadius: BorderRadius.circular(8),
                                  border: isToday
                                      ? Border.all(color: purple, width: 2)
                                      : null,
                                ),
                                child: Icon(
                                  done ? Icons.check : Icons.remove,
                                  size: 15,
                                  color: done ? Colors.white : muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${d.day}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: saving ? null : () => addRecord(category: 'Habit'),
            icon: const Icon(Icons.add),
            label: const Text('Add a habit'),
          ),
        ],
      ),
    );
  }
}

class _RecordsView extends StatefulWidget {
  final List<Map<String, dynamic>> records;
  final bool saving;
  final Color Function(String) colorFor;
  final IconData Function(String) iconFor;
  final String Function(double) money;
  final Future<void> Function(int) onEdit, onDelete;
  final VoidCallback onAdd;
  const _RecordsView({
    required this.records,
    required this.saving,
    required this.colorFor,
    required this.iconFor,
    required this.money,
    required this.onEdit,
    required this.onDelete,
    required this.onAdd,
  });
  @override
  State<_RecordsView> createState() => _RecordsViewState();
}

class _RecordsViewState extends State<_RecordsView> {
  String filter = 'All';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.records
        .asMap()
        .entries
        .where((e) => filter == 'All' || e.value['category'] == filter)
        .toList()
        .reversed
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 105),
      children: [
        const Text(
          'All records',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Browse your activities, habits and expenses',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 17),
        Wrap(
          spacing: 8,
          children: ['All', 'Expense', 'Activity', 'Habit'].map((s) {
            final selected = filter == s;
            return ChoiceChip(
              label: Text(s),
              selected: selected,
              onSelected: (_) => setState(() => filter = s),
              selectedColor: purple,
              side: BorderSide.none,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: selected ? Colors.white : ink,
                fontWeight: FontWeight.w800,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                '${filtered.length} record${filtered.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add new'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                children: [
                  const Icon(
                    Icons.filter_alt_outlined,
                    size: 42,
                    color: Color(0xFF78A4F5),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'No matching records',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Try another category or add a new check-in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                  TextButton.icon(
                    onPressed: widget.onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a record'),
                  ),
                ],
              ),
            ),
          )
        else
          ...filtered.map((e) {
            final i = e.key;
            final r = e.value;
            final c = r['category']?.toString() ?? 'Activity';
            final color = widget.colorFor(c);
            final amount = double.tryParse(r['amount']?.toString() ?? '') ?? 0;
            final desc = r['description']?.toString() ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 5,
                ),
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: .12),
                  foregroundColor: color,
                  child: Icon(widget.iconFor(c)),
                ),
                title: Text(
                  r['title']?.toString() ?? 'Untitled',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${desc.isEmpty ? c : '$desc\\n$c'}${c == 'Expense' ? ' • ${widget.money(amount)}' : ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  enabled: !widget.saving,
                  onSelected: (v) {
                    if (v == 'edit') widget.onEdit(i);
                    if (v == 'delete') widget.onDelete(i);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class AddRecordPage extends StatefulWidget {
  final Map<String, dynamic>? existingRecord;
  final String? initialCategory;
  const AddRecordPage({super.key, this.existingRecord, this.initialCategory});
  @override
  State<AddRecordPage> createState() => _AddRecordPageState();
}

class _AddRecordPageState extends State<AddRecordPage> {
  late final TextEditingController titleController,
      descriptionController,
      amountController;
  final formKey = GlobalKey<FormState>();
  late String category;
  bool get editing => widget.existingRecord != null;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRecord;
    titleController = TextEditingController(
      text: r?['title']?.toString() ?? '',
    );
    descriptionController = TextEditingController(
      text: r?['description']?.toString() ?? '',
    );
    amountController = TextEditingController(
      text: r?['amount']?.toString() ?? '',
    );
    category =
        r?['category']?.toString() ?? widget.initialCategory ?? 'Activity';
    if (!['Activity', 'Expense', 'Habit'].contains(category))
      category = 'Activity';
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    amountController.dispose();
    super.dispose();
  }

  void saveRecord() {
    if (!formKey.currentState!.validate()) return;
    final old = widget.existingRecord;
    final completionDates = old?['completionDates'] is List
        ? List<String>.from(
            (old!['completionDates'] as List).map((e) => e.toString()),
          )
        : <String>[];
    if (completionDates.isEmpty && old?['completed'] == true) {
      final d = DateTime.now();
      completionDates.add(
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );
    }
    Navigator.pop<Map<String, dynamic>>(context, {
      'title': titleController.text.trim(),
      'description': descriptionController.text.trim(),
      'category': category,
      'amount': category == 'Expense'
          ? (double.tryParse(amountController.text.trim()) ?? 0)
          : 0,
      'completionDates': category == 'Habit' ? completionDates : <String>[],
      'completed': category == 'Habit' && old?['completed'] == true,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final expense = category == 'Expense';
    final activeColor = category == 'Habit'
        ? teal
        : expense
        ? orange
        : purple;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          editing ? 'Edit record' : 'New check-in',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            const Text(
              'What are you tracking?',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _categoryButton(
                  'Activity',
                  Icons.monitor_heart_outlined,
                  purple,
                ),
                const SizedBox(width: 8),
                _categoryButton(
                  'Expense',
                  Icons.account_balance_wallet_outlined,
                  orange,
                ),
                const SizedBox(width: 8),
                _categoryButton('Habit', Icons.task_alt_outlined, teal),
              ],
            ),
            const SizedBox(height: 22),
            const Text('Title', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextFormField(
              controller: titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'e.g. Morning walk'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Please enter a title.'
                  : null,
            ),
            if (expense) ...[
              const SizedBox(height: 18),
              const Text(
                'Amount (₹)',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixText: '₹ ',
                ),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  return n == null || !n.isFinite || n < 0
                      ? 'Enter a valid non-negative amount.'
                      : null;
                },
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Note (optional)',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: descriptionController,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Add a little context',
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: saveRecord,
                style: FilledButton.styleFrom(
                  backgroundColor: activeColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: Icon(editing ? Icons.save_outlined : Icons.add),
                label: Text(
                  editing ? 'Update record' : 'Add to tracker',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryButton(String value, IconData icon, Color color) {
    final selected = category == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => category = value),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: .10) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: .5)
                  : const Color(0xFFE5E8EF),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? color : muted),
              const SizedBox(height: 5),
              Text(
                value,
                style: TextStyle(
                  color: selected ? color : ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
