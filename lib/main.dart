import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const FitnessTrackerApp());
}

class FitnessTrackerApp extends StatelessWidget {
  const FitnessTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F1E),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF7C4DFF),
          secondary: const Color(0xFF00E5FF),
          surface: const Color(0xFF1A1A2E),
          onSurface: Colors.white,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ==================== DATABASE HELPER ====================
// Uses in-memory storage on Web (Chrome) and SQLite on Android/iOS

class DatabaseHelper {
  static Database? _database;
  static final List<Map<String, dynamic>> _memoryStore = [];
  static int _nextId = 1;

  static bool get _isWeb => kIsWeb;

  // ---- SQLite (Android/iOS) ----
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    String dbPath = await getDatabasesPath();
    String path = p.join(dbPath, 'fitness_tracker.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE workouts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise TEXT NOT NULL,
            duration INTEGER NOT NULL,
            calories INTEGER NOT NULL,
            steps INTEGER NOT NULL DEFAULT 0,
            date TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // ---- CRUD (works on both Web and Mobile) ----

  static Future<int> insertWorkout(Map<String, dynamic> workout) async {
    if (_isWeb) {
      final entry = Map<String, dynamic>.from(workout);
      entry['id'] = _nextId++;
      _memoryStore.add(entry);
      return entry['id'];
    }
    final db = await database;
    return await db.insert('workouts', workout);
  }

  static Future<List<Map<String, dynamic>>> getWorkouts() async {
    if (_isWeb) {
      final sorted = List<Map<String, dynamic>>.from(_memoryStore);
      sorted.sort((a, b) {
        final dateCompare = (b['date'] as String).compareTo(a['date'] as String);
        if (dateCompare != 0) return dateCompare;
        return (b['id'] as int).compareTo(a['id'] as int);
      });
      return sorted;
    }
    final db = await database;
    return await db.query('workouts', orderBy: 'date DESC, id DESC');
  }

  static Future<List<Map<String, dynamic>>> getWorkoutsByDate(String date) async {
    if (_isWeb) {
      return _memoryStore.where((w) => w['date'] == date).toList();
    }
    final db = await database;
    return await db.query('workouts', where: 'date = ?', whereArgs: [date]);
  }

  static Future<List<Map<String, dynamic>>> getWeeklyWorkouts() async {
    if (_isWeb) {
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 6));
      final startDate = DateFormat('yyyy-MM-dd').format(weekAgo);
      final filtered = _memoryStore.where((w) => (w['date'] as String).compareTo(startDate) >= 0).toList();
      filtered.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
      return filtered;
    }
    final db = await database;
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 6));
    final startDate = DateFormat('yyyy-MM-dd').format(weekAgo);
    return await db.query(
      'workouts',
      where: 'date >= ?',
      whereArgs: [startDate],
      orderBy: 'date ASC',
    );
  }

  static Future<int> updateWorkout(int id, Map<String, dynamic> workout) async {
    if (_isWeb) {
      final index = _memoryStore.indexWhere((w) => w['id'] == id);
      if (index != -1) {
        workout['id'] = id;
        _memoryStore[index] = workout;
        return 1;
      }
      return 0;
    }
    final db = await database;
    return await db.update('workouts', workout, where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> deleteWorkout(int id) async {
    if (_isWeb) {
      _memoryStore.removeWhere((w) => w['id'] == id);
      return 1;
    }
    final db = await database;
    return await db.delete('workouts', where: 'id = ?', whereArgs: [id]);
  }
}

// ==================== HOME PAGE ====================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    DashboardPage(),
    WorkoutListPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          indicatorColor: const Color(0xFF7C4DFF).withValues(alpha: 0.2),
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined, color: Colors.white54),
              selectedIcon: Icon(Icons.dashboard, color: Color(0xFF7C4DFF)),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined, color: Colors.white54),
              selectedIcon: Icon(Icons.fitness_center, color: Color(0xFF7C4DFF)),
              label: 'Workouts',
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== DASHBOARD PAGE ====================

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int todayCalories = 0;
  int todaySteps = 0;
  int todayMinutes = 0;
  int todayWorkouts = 0;
  Map<String, int> weeklyCalories = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayData = await DatabaseHelper.getWorkoutsByDate(today);
    final weeklyData = await DatabaseHelper.getWeeklyWorkouts();

    int cal = 0, steps = 0, mins = 0;
    for (var w in todayData) {
      cal += w['calories'] as int;
      steps += w['steps'] as int;
      mins += w['duration'] as int;
    }

    Map<String, int> weeklyCal = {};
    for (int i = 6; i >= 0; i--) {
      final date = DateFormat('yyyy-MM-dd').format(
        DateTime.now().subtract(Duration(days: i)),
      );
      weeklyCal[date] = 0;
    }
    for (var w in weeklyData) {
      final date = w['date'] as String;
      weeklyCal[date] = (weeklyCal[date] ?? 0) + (w['calories'] as int);
    }

    setState(() {
      todayCalories = cal;
      todaySteps = steps;
      todayMinutes = mins;
      todayWorkouts = todayData.length;
      weeklyCalories = weeklyCal;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FitTrack',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            foreground: Paint()
                              ..shader = const LinearGradient(
                                colors: [Color(0xFF7C4DFF), Color(0xFF00E5FF)],
                              ).createShader(const Rect.fromLTWH(0, 0, 150, 30)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('EEEE, MMM d').format(DateTime.now()),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AddWorkoutPage()),
                        );
                        _loadData();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.add, color: Colors.white, size: 20),
                            SizedBox(width: 6),
                            Text(
                              'Log Workout',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Stats Cards
                Row(
                  children: [
                    Expanded(
                      child: _GradientStatCard(
                        icon: Icons.local_fire_department_rounded,
                        label: 'Calories',
                        value: '$todayCalories',
                        unit: 'kcal',
                        gradient: const [Color(0xFFFF6B35), Color(0xFFFF8F65)],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _GradientStatCard(
                        icon: Icons.directions_walk_rounded,
                        label: 'Steps',
                        value: '$todaySteps',
                        unit: 'steps',
                        gradient: const [Color(0xFF2196F3), Color(0xFF64B5F6)],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _GradientStatCard(
                        icon: Icons.timer_rounded,
                        label: 'Duration',
                        value: '$todayMinutes',
                        unit: 'min',
                        gradient: const [Color(0xFF9C27B0), Color(0xFFCE93D8)],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _GradientStatCard(
                        icon: Icons.fitness_center_rounded,
                        label: 'Workouts',
                        value: '$todayWorkouts',
                        unit: 'today',
                        gradient: const [Color(0xFF00C853), Color(0xFF69F0AE)],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // Weekly Chart
                const Text(
                  'Weekly Overview',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 200,
                  padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: weeklyCalories.isEmpty
                      ? const Center(
                          child: Text(
                            'No data yet',
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: _getMaxY(),
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                tooltipRoundedRadius: 10,
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  return BarTooltipItem(
                                    '${rod.toY.toInt()} kcal',
                                    const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  );
                                },
                              ),
                            ),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 36,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      value.toInt().toString(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white30,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final keys = weeklyCalories.keys.toList();
                                    if (value.toInt() < keys.length) {
                                      final date = DateTime.parse(keys[value.toInt()]);
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          DateFormat('E').format(date),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white38,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      );
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: _getMaxY() / 4,
                              getDrawingHorizontalLine: (value) => FlLine(
                                color: Colors.white.withValues(alpha: 0.04),
                                strokeWidth: 1,
                              ),
                            ),
                            barGroups: _getBarGroups(),
                          ),
                        ),
                ),

                const SizedBox(height: 28),

                // Goals
                const Text(
                  'Daily Goals',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                _GoalProgressCard(
                  icon: Icons.local_fire_department_rounded,
                  label: 'Calories',
                  current: todayCalories,
                  goal: 500,
                  color: const Color(0xFFFF6B35),
                  unit: 'kcal',
                ),
                const SizedBox(height: 10),
                _GoalProgressCard(
                  icon: Icons.directions_walk_rounded,
                  label: 'Steps',
                  current: todaySteps,
                  goal: 10000,
                  color: const Color(0xFF2196F3),
                  unit: 'steps',
                ),
                const SizedBox(height: 10),
                _GoalProgressCard(
                  icon: Icons.timer_rounded,
                  label: 'Duration',
                  current: todayMinutes,
                  goal: 60,
                  color: const Color(0xFF9C27B0),
                  unit: 'min',
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _getMaxY() {
    if (weeklyCalories.isEmpty) return 100;
    final maxVal = weeklyCalories.values.fold(0, (a, b) => a > b ? a : b);
    return maxVal == 0 ? 100 : (maxVal * 1.3).ceilToDouble();
  }

  List<BarChartGroupData> _getBarGroups() {
    final values = weeklyCalories.values.toList();
    return List.generate(values.length, (i) {
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: values[i].toDouble(),
            gradient: const LinearGradient(
              colors: [Color(0xFF7C4DFF), Color(0xFF00E5FF)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
        ],
      );
    });
  }
}

// ==================== GRADIENT STAT CARD ====================

class _GradientStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final List<Color> gradient;

  const _GradientStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [gradient[0].withValues(alpha: 0.2), gradient[1].withValues(alpha: 0.1)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: gradient[0], size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$label · $unit',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.45),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== GOAL PROGRESS CARD ====================

class _GoalProgressCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int current;
  final int goal;
  final Color color;
  final String unit;

  const _GoalProgressCard({
    required this.icon,
    required this.label,
    required this.current,
    required this.goal,
    required this.color,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (current / goal).clamp(0.0, 1.0);
    final percentage = (progress * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '$current / $goal $unit',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color, color.withValues(alpha: 0.7)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$percentage% completed',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== WORKOUT LIST PAGE ====================

class WorkoutListPage extends StatefulWidget {
  const WorkoutListPage({super.key});

  @override
  State<WorkoutListPage> createState() => _WorkoutListPageState();
}

class _WorkoutListPageState extends State<WorkoutListPage> {
  List<Map<String, dynamic>> workouts = [];

  @override
  void initState() {
    super.initState();
    _loadWorkouts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadWorkouts();
  }

  Future<void> _loadWorkouts() async {
    final data = await DatabaseHelper.getWorkouts();
    setState(() {
      workouts = data;
    });
  }

  void _deleteWorkout(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Workout', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete this workout?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.deleteWorkout(id);
              Navigator.pop(context);
              _loadWorkouts();
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _editWorkout(Map<String, dynamic> workout) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddWorkoutPage(workout: workout),
      ),
    );
    _loadWorkouts();
  }

  IconData _getExerciseIcon(String exercise) {
    final lower = exercise.toLowerCase();
    if (lower.contains('run') || lower.contains('jog')) return Icons.directions_run;
    if (lower.contains('walk')) return Icons.directions_walk;
    if (lower.contains('cycle') || lower.contains('bike')) return Icons.directions_bike;
    if (lower.contains('swim')) return Icons.pool;
    if (lower.contains('yoga')) return Icons.self_improvement;
    if (lower.contains('hiit')) return Icons.speed;
    if (lower.contains('jump') || lower.contains('rope')) return Icons.sports;
    if (lower.contains('stretch')) return Icons.accessibility_new;
    return Icons.fitness_center;
  }

  Color _getExerciseColor(String exercise) {
    final lower = exercise.toLowerCase();
    if (lower.contains('run') || lower.contains('jog')) return const Color(0xFFFF6B35);
    if (lower.contains('walk')) return const Color(0xFF2196F3);
    if (lower.contains('cycle') || lower.contains('bike')) return const Color(0xFF00C853);
    if (lower.contains('swim')) return const Color(0xFF00BCD4);
    if (lower.contains('yoga')) return const Color(0xFF9C27B0);
    if (lower.contains('weight')) return const Color(0xFFFF5252);
    if (lower.contains('hiit')) return const Color(0xFFFF9800);
    return const Color(0xFF7C4DFF);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'My Workouts',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AddWorkoutPage()),
                      );
                      _loadWorkouts();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // List
            Expanded(
              child: workouts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.fitness_center_rounded,
                            size: 64,
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No workouts logged yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap + to log your first workout!',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadWorkouts,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        itemCount: workouts.length,
                        itemBuilder: (context, index) {
                          final w = workouts[index];
                          final date = DateTime.parse(w['date']);
                          final isToday = DateFormat('yyyy-MM-dd').format(date) ==
                              DateFormat('yyyy-MM-dd').format(DateTime.now());
                          final exerciseColor = _getExerciseColor(w['exercise']);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A2E),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: exerciseColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _getExerciseIcon(w['exercise']),
                                    color: exerciseColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        w['exercise'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${w['duration']} min  ·  ${w['calories']} kcal  ·  ${w['steps']} steps',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withValues(alpha: 0.4),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        isToday ? 'Today' : DateFormat('MMM d, yyyy').format(date),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.white.withValues(alpha: 0.25),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: Icon(
                                    Icons.more_vert,
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                  color: const Color(0xFF252540),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _editWorkout(w);
                                    } else if (value == 'delete') {
                                      _deleteWorkout(w['id']);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_rounded, size: 18, color: Colors.white70),
                                          SizedBox(width: 10),
                                          Text('Edit', style: TextStyle(color: Colors.white70)),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_rounded, size: 18, color: Colors.redAccent),
                                          SizedBox(width: 10),
                                          Text('Delete', style: TextStyle(color: Colors.redAccent)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== ADD WORKOUT PAGE ====================

class AddWorkoutPage extends StatefulWidget {
  final Map<String, dynamic>? workout;

  const AddWorkoutPage({super.key, this.workout});

  @override
  State<AddWorkoutPage> createState() => _AddWorkoutPageState();
}

class _AddWorkoutPageState extends State<AddWorkoutPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _exerciseController;
  late TextEditingController _durationController;
  late TextEditingController _caloriesController;
  late TextEditingController _stepsController;
  late DateTime _selectedDate;

  final List<String> _exerciseTypes = [
    'Running',
    'Walking',
    'Cycling',
    'Swimming',
    'Weight Training',
    'Yoga',
    'HIIT',
    'Jump Rope',
    'Stretching',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _exerciseController = TextEditingController(
      text: widget.workout?['exercise'] ?? '',
    );
    _durationController = TextEditingController(
      text: widget.workout?['duration']?.toString() ?? '',
    );
    _caloriesController = TextEditingController(
      text: widget.workout?['calories']?.toString() ?? '',
    );
    _stepsController = TextEditingController(
      text: widget.workout?['steps']?.toString() ?? '0',
    );
    _selectedDate = widget.workout != null
        ? DateTime.parse(widget.workout!['date'])
        : DateTime.now();
  }

  @override
  void dispose() {
    _exerciseController.dispose();
    _durationController.dispose();
    _caloriesController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _saveWorkout() async {
    if (!_formKey.currentState!.validate()) return;

    final workout = {
      'exercise': _exerciseController.text.trim(),
      'duration': int.parse(_durationController.text.trim()),
      'calories': int.parse(_caloriesController.text.trim()),
      'steps': int.tryParse(_stepsController.text.trim()) ?? 0,
      'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
    };

    if (widget.workout != null) {
      await DatabaseHelper.updateWorkout(widget.workout!['id'], workout);
    } else {
      await DatabaseHelper.insertWorkout(workout);
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF7C4DFF),
              surface: Color(0xFF1A1A2E),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
      prefixIcon: Icon(icon, color: const Color(0xFF7C4DFF), size: 20),
      filled: true,
      fillColor: const Color(0xFF1A1A2E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF7C4DFF)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.workout != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Edit Workout' : 'Log Workout',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Exercise Type Chips
              Text(
                'Choose Exercise',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _exerciseTypes.map((type) {
                  final isSelected = _exerciseController.text == type;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _exerciseController.text = isSelected ? '' : type;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
                              )
                            : null,
                        color: isSelected ? null : const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        type,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _exerciseController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Or type exercise name', Icons.fitness_center_rounded),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an exercise';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              TextFormField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Duration (minutes)', Icons.timer_rounded),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Please enter duration';
                  if (int.tryParse(value.trim()) == null) return 'Enter a valid number';
                  return null;
                },
              ),

              const SizedBox(height: 18),

              TextFormField(
                controller: _caloriesController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Calories Burned', Icons.local_fire_department_rounded),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Please enter calories';
                  if (int.tryParse(value.trim()) == null) return 'Enter a valid number';
                  return null;
                },
              ),

              const SizedBox(height: 18),

              TextFormField(
                controller: _stepsController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Steps (optional)', Icons.directions_walk_rounded),
              ),

              const SizedBox(height: 18),

              // Date Picker
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        color: Color(0xFF7C4DFF),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat('EEEE, MMM d, yyyy').format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Save Button
              GestureDetector(
                onTap: _saveWorkout,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isEditing ? Icons.save_rounded : Icons.add_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isEditing ? 'Update Workout' : 'Save Workout',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}