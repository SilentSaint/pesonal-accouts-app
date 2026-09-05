import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// Automated Scan Scheduler Service
///
/// Implements the user-specified schedule:
/// 1. Hourly Daytime Scan: Every hour from 6:00 AM to 9:00 PM local time.
/// 2. Morning Overnight Scan: Every morning at 6:00 AM (or on first boot after 6:00 AM),
///    scans the overnight remaining window (yesterday 9:01:00 PM to today 5:59:59 AM).
class AutoScanSchedulerService extends ChangeNotifier {
  static final AutoScanSchedulerService _instance = AutoScanSchedulerService._internal();
  factory AutoScanSchedulerService() => _instance;
  AutoScanSchedulerService._internal();

  Timer? _timer;
  bool _isRunning = false;
  bool _isScanningNow = false;
  DateTime? _lastScanTime;
  String _lastScanType = 'None';
  String _statusSummary = 'Schedule Ready (6 AM – 9 PM Hourly • 6 AM Overnight)';

  Future<void> Function({int? afterTimestamp, int? beforeTimestamp, required String scanType})? onTriggerScan;

  bool get isRunning => _isRunning;
  bool get isScanningNow => _isScanningNow;
  DateTime? get lastScanTime => _lastScanTime;
  String get lastScanType => _lastScanType;
  String get statusSummary => _statusSummary;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _loadState().then((_) {
      if (!_isRunning) return;
      // Check immediately on startup/refresh
      checkScheduleNow();
      // Periodically check every 60 seconds
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => checkScheduleNow());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    notifyListeners();
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt('scheduler_last_scan_ms');
      if (lastMs != null) {
        _lastScanTime = DateTime.fromMillisecondsSinceEpoch(lastMs);
      }
      _lastScanType = prefs.getString('scheduler_last_scan_type') ?? 'None';
    } catch (_) {}
  }

  Future<void> _saveState(String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      _lastScanTime = now;
      _lastScanType = type;
      await prefs.setInt('scheduler_last_scan_ms', now.millisecondsSinceEpoch);
      await prefs.setString('scheduler_last_scan_type', type);
      await prefs.setString('scheduler_last_date_${type.toLowerCase()}', '${now.year}-${now.month}-${now.day}');
    } catch (_) {}
    notifyListeners();
  }

  /// Evaluates current local time and triggers the appropriate scan if due.
  Future<void> checkScheduleNow() async {
    if (_isScanningNow) return;
    final auth = AuthService();
    if (!auth.isAuthenticated || !auth.hasGmailAccess) {
      _statusSummary = 'Paused (Sign in with Gmail required)';
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    final currentHour = now.hour; // 0..23
    final prefs = await SharedPreferences.getInstance();
    final todayDateStr = '${now.year}-${now.month}-${now.day}';

    // 1. Morning Overnight Scan (Covers 9:01:00 PM yesterday to 5:59:59 AM today)
    // Runs when local time >= 6 AM if not yet performed for today.
    final lastOvernightDate = prefs.getString('scheduler_last_date_overnight');
    if (currentHour >= 6 && lastOvernightDate != todayDateStr) {
      _isScanningNow = true;
      _statusSummary = 'Scanning overnight window (9:01 PM – 5:59 AM)…';
      notifyListeners();

      try {
        final yesterday = now.subtract(const Duration(days: 1));
        final overnightStart = DateTime(yesterday.year, yesterday.month, yesterday.day, 21, 1, 0);
        final overnightEnd = DateTime(now.year, now.month, now.day, 5, 59, 59);

        final afterSec = (overnightStart.millisecondsSinceEpoch / 1000).floor();
        final beforeSec = (overnightEnd.millisecondsSinceEpoch / 1000).floor();

        if (onTriggerScan != null) {
          await onTriggerScan!(
            afterTimestamp: afterSec,
            beforeTimestamp: beforeSec,
            scanType: 'OVERNIGHT',
          );
        }
        await _saveState('OVERNIGHT');
        await prefs.setString('scheduler_last_date_overnight', todayDateStr);
        _statusSummary = 'Overnight scan complete (${_formatTime(DateTime.now())})';
      } catch (e) {
        debugPrint('AutoScanScheduler: overnight scan error: $e');
        _statusSummary = 'Overnight scan failed';
      } finally {
        _isScanningNow = false;
        notifyListeners();
      }
      return;
    }

    // 2. Hourly Daytime Scan (Active 6 AM to 9 PM, i.e. hours 6 through 21)
    if (currentHour >= 6 && currentHour <= 21) {
      final lastHourlyHour = prefs.getInt('scheduler_last_hourly_hour');
      final lastHourlyDate = prefs.getString('scheduler_last_hourly_date');

      final alreadyRanThisHour = (lastHourlyDate == todayDateStr && lastHourlyHour == currentHour);
      if (!alreadyRanThisHour) {
        _isScanningNow = true;
        _statusSummary = 'Running hourly daytime scan ($currentHour:00)…';
        notifyListeners();

        try {
          // Scan past 1 hour (or since last scan)
          final oneHourAgo = now.subtract(const Duration(minutes: 65));
          final afterSec = (oneHourAgo.millisecondsSinceEpoch / 1000).floor();

          if (onTriggerScan != null) {
            await onTriggerScan!(
              afterTimestamp: afterSec,
              scanType: 'HOURLY',
            );
          }
          await _saveState('HOURLY');
          await prefs.setInt('scheduler_last_hourly_hour', currentHour);
          await prefs.setString('scheduler_last_hourly_date', todayDateStr);
          _statusSummary = 'Hourly scan completed at ${_formatTime(DateTime.now())}';
        } catch (e) {
          debugPrint('AutoScanScheduler: hourly scan error: $e');
          _statusSummary = 'Hourly scan failed';
        } finally {
          _isScanningNow = false;
          notifyListeners();
        }
        return;
      }
    }

    // Update friendly summary
    if (currentHour > 21 || currentHour < 6) {
      _statusSummary = 'Overnight quiet window • Next scan at 6:00 AM';
    } else {
      final nextHour = currentHour + 1;
      _statusSummary = 'Hourly active (6 AM – 9 PM) • Next scan at $nextHour:00';
    }
    notifyListeners();
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }
}
