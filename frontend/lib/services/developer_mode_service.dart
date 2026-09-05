import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhaseAuditItem {
  final String messageId;
  final String subject;
  final String from;
  final String date;
  final String snippet;
  final bool isCandidate;
  final double? amount;
  final String? merchantName;
  final String? category;
  final String? upiId;
  final String? upiRef;
  final String? status; // 'AUTO_CONFIRMED', 'NEEDS_REVIEW', 'PROMOTIONAL', 'IGNORED'

  PhaseAuditItem({
    required this.messageId,
    required this.subject,
    required this.from,
    required this.date,
    required this.snippet,
    required this.isCandidate,
    this.amount,
    this.merchantName,
    this.category,
    this.upiId,
    this.upiRef,
    this.status,
  });

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'subject': subject,
        'from': from,
        'date': date,
        'snippet': snippet,
        'isCandidate': isCandidate,
        'amount': amount,
        'merchantName': merchantName,
        'category': category,
        'upiId': upiId,
        'upiRef': upiRef,
        'status': status,
      };
}

class PhaseScanAudit {
  final int phaseIndex; // 1, 2, or 3
  final String phaseTitle;
  final DateTime scannedAt;
  final int emailsScanned;
  final int candidatesCount;
  final int autoAccountedCount;
  final int needsReviewCount;
  final List<PhaseAuditItem> items;

  PhaseScanAudit({
    required this.phaseIndex,
    required this.phaseTitle,
    required this.scannedAt,
    required this.emailsScanned,
    required this.candidatesCount,
    required this.autoAccountedCount,
    required this.needsReviewCount,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'phaseIndex': phaseIndex,
        'phaseTitle': phaseTitle,
        'scannedAt': scannedAt.toIso8601String(),
        'emailsScanned': emailsScanned,
        'candidatesCount': candidatesCount,
        'autoAccountedCount': autoAccountedCount,
        'needsReviewCount': needsReviewCount,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

/// Developer Mode & 3-Phase Historical Scanner Service
///
/// Feature flag default: TRUE (Deployed ON by default in production)
class DeveloperModeService extends ChangeNotifier {
  static final DeveloperModeService _instance = DeveloperModeService._internal();
  factory DeveloperModeService() => _instance;

  bool _isEnabled = true; // Default ON as requested
  final Map<int, PhaseScanAudit> _phaseAudits = {};

  bool get isEnabled => _isEnabled;
  Map<int, PhaseScanAudit> get phaseAudits => _phaseAudits;

  DeveloperModeService._internal() {
    _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Default to true if not set
      _isEnabled = prefs.getBool('dev_mode_enabled') ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    _isEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dev_mode_enabled', value);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> toggle() => setEnabled(!_isEnabled);

  // ==========================================
  // PHASE TIMESTAMPS GENERATION
  // ==========================================
  
  /// Phase 1: Days 30 to 21 ago
  Map<String, dynamic> getPhase1Range([DateTime? referenceTime]) {
    final ref = referenceTime ?? DateTime.now();
    final start = ref.subtract(const Duration(days: 30));
    final end = ref.subtract(const Duration(days: 20));
    return {
      'phaseIndex': 1,
      'title': 'Phase 1: Days 30 – 21',
      'startDate': start,
      'endDate': end,
      'afterSec': (start.millisecondsSinceEpoch / 1000).floor(),
      'beforeSec': (end.millisecondsSinceEpoch / 1000).floor(),
    };
  }

  /// Phase 2: Days 20 to 11 ago
  Map<String, dynamic> getPhase2Range([DateTime? referenceTime]) {
    final ref = referenceTime ?? DateTime.now();
    final start = ref.subtract(const Duration(days: 20));
    final end = ref.subtract(const Duration(days: 10));
    return {
      'phaseIndex': 2,
      'title': 'Phase 2: Days 20 – 11',
      'startDate': start,
      'endDate': end,
      'afterSec': (start.millisecondsSinceEpoch / 1000).floor(),
      'beforeSec': (end.millisecondsSinceEpoch / 1000).floor(),
    };
  }

  /// Phase 3: Days 10 to Today
  Map<String, dynamic> getPhase3Range([DateTime? referenceTime]) {
    final ref = referenceTime ?? DateTime.now();
    final start = ref.subtract(const Duration(days: 10));
    final end = ref;
    return {
      'phaseIndex': 3,
      'title': 'Phase 3: Days 10 – Today',
      'startDate': start,
      'endDate': end,
      'afterSec': (start.millisecondsSinceEpoch / 1000).floor(),
      'beforeSec': (end.millisecondsSinceEpoch / 1000).floor(),
    };
  }

  void recordPhaseAudit(PhaseScanAudit audit) {
    _phaseAudits[audit.phaseIndex] = audit;
    notifyListeners();
  }

  void clearAudits() {
    _phaseAudits.clear();
    notifyListeners();
  }

  String exportPhaseAuditJson(int phaseIndex) {
    final audit = _phaseAudits[phaseIndex];
    if (audit == null) return '{}';
    return const JsonEncoder.withIndent('  ').convert(audit.toJson());
  }
}
