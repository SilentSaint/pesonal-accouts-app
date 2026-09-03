import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/security_service.dart';
import 'services/auth_service.dart';
import 'ui/dashboard_screen.dart';
import 'ui/proactive_insights_screen.dart';
import 'ui/recurring_commitments_screen.dart';
import 'ui/security_lock_screen.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    final int schemaVersion = prefs.getInt('app_data_version') ?? 0;
    if (schemaVersion < 5) {
      await prefs.clear();
      await prefs.setInt('app_data_version', 5);
    }
  } catch (_) {}

  // Complete silent Google restoration before constructing the dashboard so a
  // browser refresh does not briefly look like a signed-out session.
  await AuthService().ensureInitialized();
  await SecurityState().initialize();
  runApp(const ExpenseTrackerApp());
}

class ExpenseTrackerApp extends StatefulWidget {
  const ExpenseTrackerApp({super.key});

  @override
  State<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends State<ExpenseTrackerApp>
    with WidgetsBindingObserver {
  final SecurityState _securityState = SecurityState();
  final FocusNode _activityFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _securityState.addListener(_onSecurityChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _securityState.removeListener(_onSecurityChange);
    _activityFocusNode.dispose();
    super.dispose();
  }

  void _onSecurityChange() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _securityState.onAppLifecycleChanged(state);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Automatic Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routes: {
        '/insights': (_) => const ProactiveInsightsScreen(),
        '/recurring-commitments': (_) => const RecurringCommitmentsScreen(),
      },
      home: Focus(
        focusNode: _activityFocusNode,
        autofocus: true,
        onKeyEvent: (_, __) {
          _securityState.userActivityDetected();
          return KeyEventResult.ignored;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _securityState.userActivityDetected(),
          onPointerMove: (_) => _securityState.userActivityDetected(),
          onPointerSignal: (_) => _securityState.userActivityDetected(),
          child: _securityState.isLocked
              ? SecurityLockScreen(
                  onUnlocked: () => setState(() {}),
                  onWebReauthenticate: kIsWeb
                      ? AuthService().signInWithGoogle
                      : null,
                )
              : const DashboardScreen(),
        ),
      ),
    );
  }
}
