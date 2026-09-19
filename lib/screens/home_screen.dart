import 'package:flutter/material.dart';
import '../models/student.dart';
import '../models/sign_in_result.dart';
import '../services/database_service.dart';
import '../services/attendance_service.dart';
import '../widgets/student_tile.dart';
import 'add_student_screen.dart';
import 'scanner_screen.dart';
import 'student_list_screen.dart';

/// Main home screen - the daily-use attendance signing interface.
class HomeScreen extends StatefulWidget {
  final DatabaseService dbService;

  const HomeScreen({super.key, required this.dbService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Student> _students = [];
  Set<int> _selectedStudentIds = {};
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();
  bool _otpFocused = false;
  bool _isSigning = false;

  @override
  void initState() {
    super.initState();
    _otpFocusNode.addListener(() {
      if (_otpFocusNode.hasFocus != _otpFocused) {
        setState(() => _otpFocused = _otpFocusNode.hasFocus);
      }
    });
    _loadStudents();
  }

  @override
  void dispose() {
    _otpFocusNode.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    final students = await widget.dbService.getAllStudents();
    setState(() {
      _students = students;
      _selectedStudentIds = students.map((s) => s.id!).toSet();
    });
  }

  void _toggleStudent(int id) {
    setState(() {
      if (_selectedStudentIds.contains(id)) {
        _selectedStudentIds.remove(id);
      } else {
        _selectedStudentIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedStudentIds = _students.map((s) => s.id!).toSet();
    });
  }

  void _deselectAll() {
    setState(() => _selectedStudentIds.clear());
  }

  Future<void> _scanQR() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (code != null && code.length == 3 && mounted) {
      setState(() {
        _otpController.text = code;
        _otpController.selection = TextSelection.fromPosition(
          TextPosition(offset: code.length),
        );
      });
    }
  }

  Future<void> _navigateToAddStudent() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AddStudentScreen(dbService: widget.dbService),
      ),
    );
    if (result == true) _loadStudents();
  }

  Future<void> _navigateToStudentList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StudentListScreen(dbService: widget.dbService),
      ),
    );
    _loadStudents();
  }

  Future<void> _performSignIn(List<Student> selectedStudents) async {
    final otp = _otpController.text;

    setState(() => _isSigning = true);

    try {
      final results = await AttendanceService.batchSignIn(selectedStudents, otp);

      for (final student in selectedStudents) {
        await widget.dbService.updateLastUsed(student.userId);
      }

      if (mounted) _showResultsDialog(results);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigning = false);
    }
  }

  void _showResultsDialog(List<SignInResult> results) {
    showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign-In Results'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: results.length,
            itemBuilder: (context, index) {
              final r = results[index];
              final needsReauth = r.status == SignInStatus.tokenExpired;
              return ListTile(
                leading: Icon(
                  r.isSuccess ? Icons.check_circle : Icons.error,
                  color: r.isSuccess ? Colors.green : Colors.orange,
                ),
                title: Text(r.displayName),
                subtitle: Text(r.message),
                dense: true,
                trailing: needsReauth
                    ? TextButton(
                        onPressed: () {
                          // Close the results dialog, then jump straight
                          // back into the OAuth flow. Logging in with the
                          // same Microsoft account re-issues the token for
                          // this user_id (AddStudentScreen updates on match).
                          Navigator.of(dialogContext).pop();
                          _navigateToAddStudent();
                        },
                        child: const Text('Re-Authorize'),
                      )
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedStudents = _students
        .where((s) => _selectedStudentIds.contains(s.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('APU Auto Signer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            onPressed: _navigateToStudentList,
            tooltip: 'Manage Students',
          ),
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: _navigateToAddStudent,
            tooltip: 'Add Student',
          ),
        ],
      ),
      body: _students.isEmpty
          ? _buildEmptyState(theme)
          : _buildMainContent(theme, selectedStudents),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.school_outlined,
              size: 80,
              color: theme.colorScheme.primary.withAlpha(120),
            ),
            const SizedBox(height: 16),
            Text('No Students Yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Add your first student account to get started with batch attendance signing.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _navigateToAddStudent,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Student'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(ThemeData theme, List<Student> selectedStudents) {
    final canSignIn = !_isSigning &&
        selectedStudents.isNotEmpty &&
        _otpController.text.length == 3;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // OTP input card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Enter OTP Code', style: theme.textTheme.titleMedium),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: 'Scan OTP QR',
                        onPressed: _scanQR,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _otpController,
                      focusNode: _otpFocusNode,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 3,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        // Show the bold "000" placeholder only while the
                        // field is unfocused; hide it as soon as the user
                        // taps in so it doesn't linger while typing.
                        hintText: _otpFocused ? null : '000',
                        hintStyle: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                        ),
                      ),
                      onChanged: (value) {
                        final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                        if (digits != value) {
                          _otpController.text = digits;
                          _otpController.selection = TextSelection.fromPosition(
                            TextPosition(offset: digits.length),
                          );
                        }
                        setState(() {}); // Refresh button state
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Student selection header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Students (${selectedStudents.length}/${_students.length})',
                style: theme.textTheme.titleSmall,
              ),
              Row(
                children: [
                  TextButton(onPressed: _selectAll, child: const Text('Select All')),
                  TextButton(onPressed: _deselectAll, child: const Text('Clear')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Student list
          Expanded(
            child: ListView.builder(
              itemCount: _students.length,
              itemBuilder: (context, index) {
                final student = _students[index];
                final isSelected = _selectedStudentIds.contains(student.id);
                return StudentTile(
                  student: student,
                  isSelected: isSelected,
                  onTap: () => _toggleStudent(student.id!),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Sign in button
          FilledButton.icon(
            onPressed: canSignIn
                ? () => _performSignIn(selectedStudents)
                : null,
            icon: _isSigning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.flash_on),
            label: Text(
              _isSigning
                  ? 'Signing In...'
                  : 'Sign In (${selectedStudents.length})',
            ),
          ),
        ],
      ),
    );
  }
}
