class GoalAllocation {
  const GoalAllocation({
    required this.reference,
    required this.amount,
    this.linkedAccountId,
  });

  final String reference;
  final String amount;
  final String? linkedAccountId;

  factory GoalAllocation.fromJson(Map<String, dynamic> json) {
    if (json['reference'] is! String || json['amount'] is! String) {
      throw const FormatException('Invalid goal allocation');
    }
    return GoalAllocation(
      reference: json['reference'] as String,
      amount: json['amount'] as String,
      linkedAccountId: json['linkedAccountId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'reference': reference,
        'amount': amount,
        if (linkedAccountId != null) 'linkedAccountId': linkedAccountId,
      };
}

class GoalContributionRule {
  const GoalContributionRule({required this.amount, required this.cadence});

  final String amount;
  final String cadence;

  factory GoalContributionRule.fromJson(Map<String, dynamic> json) {
    if (json['amount'] is! String || json['cadence'] is! String) {
      throw const FormatException('Invalid goal contribution rule');
    }
    return GoalContributionRule(
      amount: json['amount'] as String,
      cadence: json['cadence'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'amount': amount, 'cadence': cadence};
}

class GoalContribution {
  const GoalContribution({
    required this.id,
    required this.amount,
    required this.contributedOn,
    this.evidenceReference,
  });

  final String id;
  final String amount;
  final DateTime contributedOn;
  final String? evidenceReference;

  factory GoalContribution.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        json['amount'] is! String ||
        json['contributedOn'] is! String) {
      throw const FormatException('Invalid goal contribution');
    }
    return GoalContribution(
      id: json['id'] as String,
      amount: json['amount'] as String,
      contributedOn: _date(json['contributedOn'] as String),
      evidenceReference: json['evidenceReference'] as String?,
    );
  }

  Map<String, dynamic> toRequestJson(String currency) => {
        'id': id,
        'amount': amount,
        'currency': currency,
        'contributedOn': _formatDate(contributedOn),
        if (evidenceReference != null) 'evidenceReference': evidenceReference,
      };
}

class FinancialGoalProjection {
  const FinancialGoalProjection({
    required this.amountRemaining,
    required this.currency,
    required this.monthsRemaining,
    required this.requiredMonthlyContribution,
    required this.observedMonthlyContribution,
    required this.projectedCompletionDate,
    required this.monthlyShortfallOrSurplus,
    required this.minimumBalanceBreached,
    required this.status,
    required this.classification,
    required this.formulaId,
    required this.formulaVersion,
    required this.confidence,
    required this.assumptions,
    required this.warnings,
    required this.contributionEvidenceReferences,
  });

  final String amountRemaining;
  final String currency;
  final int monthsRemaining;
  final String requiredMonthlyContribution;
  final String observedMonthlyContribution;
  final DateTime? projectedCompletionDate;
  final String monthlyShortfallOrSurplus;
  final bool minimumBalanceBreached;
  final String status;
  final String classification;
  final String formulaId;
  final String formulaVersion;
  final String confidence;
  final List<String> assumptions;
  final List<String> warnings;
  final List<String> contributionEvidenceReferences;

  factory FinancialGoalProjection.fromJson(Map<String, dynamic> json) {
    final value = json['value'];
    final formula = json['formula'];
    if (value is! Map ||
        formula is! Map ||
        json['classification'] is! String ||
        json['confidence'] is! String ||
        json['assumptions'] is! List ||
        json['warnings'] is! List) {
      throw const FormatException('Invalid financial goal projection');
    }
    final details = Map<String, dynamic>.from(value);
    final formulaValues = Map<String, dynamic>.from(formula);
    if (details['amountRemaining'] is! String ||
        details['currency'] is! String ||
        details['monthsRemaining'] is! int ||
        details['requiredMonthlyContribution'] is! String ||
        details['observedMonthlyContribution'] is! String ||
        details['monthlyShortfallOrSurplus'] is! String ||
        details['minimumBalanceBreached'] is! bool ||
        details['status'] is! String ||
        details['contributionEvidenceReferences'] is! List ||
        formulaValues['id'] is! String ||
        formulaValues['version'] is! String) {
      throw const FormatException('Invalid financial goal projection values');
    }
    return FinancialGoalProjection(
      amountRemaining: details['amountRemaining'] as String,
      currency: details['currency'] as String,
      monthsRemaining: details['monthsRemaining'] as int,
      requiredMonthlyContribution:
          details['requiredMonthlyContribution'] as String,
      observedMonthlyContribution:
          details['observedMonthlyContribution'] as String,
      projectedCompletionDate: details['projectedCompletionDate'] == null
          ? null
          : _date(details['projectedCompletionDate'] as String),
      monthlyShortfallOrSurplus: details['monthlyShortfallOrSurplus'] as String,
      minimumBalanceBreached: details['minimumBalanceBreached'] as bool,
      status: details['status'] as String,
      classification: json['classification'] as String,
      formulaId: formulaValues['id'] as String,
      formulaVersion: formulaValues['version'] as String,
      confidence: json['confidence'] as String,
      assumptions: (json['assumptions'] as List)
          .map((item) => item.toString())
          .toList(growable: false),
      warnings: (json['warnings'] as List)
          .map((item) => item.toString())
          .toList(growable: false),
      contributionEvidenceReferences:
          (details['contributionEvidenceReferences'] as List)
              .map((item) => item.toString())
              .toList(growable: false),
    );
  }
}

class FinancialGoal {
  const FinancialGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currency,
    required this.targetDate,
    required this.priority,
    required this.lifecycle,
    required this.allocations,
    required this.contributions,
    required this.contributionRule,
    this.projection,
  });

  final String id;
  final String name;
  final String targetAmount;
  final String currency;
  final DateTime targetDate;
  final String priority;
  final String lifecycle;
  final List<GoalAllocation> allocations;
  final List<GoalContribution> contributions;
  final GoalContributionRule? contributionRule;
  final FinancialGoalProjection? projection;

  double get progress {
    final target = double.tryParse(targetAmount) ?? 0;
    if (target <= 0) return 0;
    final allocated = allocations.fold<double>(
        0,
        (total, allocation) =>
            total + (double.tryParse(allocation.amount) ?? 0));
    final contributionsTotal = contributions.fold<double>(
        0,
        (total, contribution) =>
            total + (double.tryParse(contribution.amount) ?? 0));
    return ((allocated + contributionsTotal) / target).clamp(0, 1).toDouble();
  }

  factory FinancialGoal.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        json['name'] is! String ||
        json['targetAmount'] is! String ||
        json['currency'] is! String ||
        json['targetDate'] is! String ||
        json['priority'] is! String ||
        json['lifecycle'] is! String ||
        json['allocations'] is! List ||
        json['contributions'] is! List) {
      throw const FormatException('Invalid financial goal');
    }
    return FinancialGoal(
      id: json['id'] as String,
      name: json['name'] as String,
      targetAmount: json['targetAmount'] as String,
      currency: json['currency'] as String,
      targetDate: _date(json['targetDate'] as String),
      priority: json['priority'] as String,
      lifecycle: json['lifecycle'] as String,
      allocations: (json['allocations'] as List)
          .map((item) =>
              GoalAllocation.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      contributions: (json['contributions'] as List)
          .map((item) =>
              GoalContribution.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      contributionRule: json['contributionRule'] == null
          ? null
          : GoalContributionRule.fromJson(
              Map<String, dynamic>.from(json['contributionRule'] as Map)),
      projection: json['projection'] == null
          ? null
          : FinancialGoalProjection.fromJson(
              Map<String, dynamic>.from(json['projection'] as Map)),
    );
  }

  Map<String, dynamic> toRequestJson() => {
        'name': name,
        'targetAmount': targetAmount,
        'currency': currency,
        'targetDate': _formatDate(targetDate),
        'priority': priority,
        'allocations': allocations
            .map((allocation) => allocation.toJson())
            .toList(growable: false),
        if (contributionRule != null)
          'contributionRule': contributionRule!.toJson(),
      };
}

class FinancialGoalList {
  const FinancialGoalList({required this.asOf, required this.goals});

  final DateTime asOf;
  final List<FinancialGoal> goals;

  factory FinancialGoalList.fromJson(Map<String, dynamic> json) {
    if (json['asOf'] is! String || json['goals'] is! List) {
      throw const FormatException('Invalid financial goal response');
    }
    return FinancialGoalList(
      asOf: _date(json['asOf'] as String),
      goals: (json['goals'] as List)
          .map((item) =>
              FinancialGoal.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
    );
  }
}

DateTime _date(String value) {
  final parsed = DateTime.parse(value.split('T').first);
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

String _formatDate(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day)
        .toIso8601String()
        .substring(0, 10);
