import 'package:flutter/material.dart';

import '../domain/financial_goal.dart';
import '../services/backend_api_service.dart';
import 'theme/app_theme.dart';

class FinancialGoalScreen extends StatefulWidget {
  const FinancialGoalScreen({
    super.key,
    this.load,
    this.create,
    this.update,
    this.pause,
    this.resume,
    this.complete,
    this.delete,
    this.recordContribution,
  });

  final Future<FinancialGoalList> Function()? load;
  final Future<FinancialGoal> Function(FinancialGoal goal)? create;
  final Future<FinancialGoal> Function(FinancialGoal goal)? update;
  final Future<FinancialGoal> Function(String id)? pause;
  final Future<FinancialGoal> Function(String id)? resume;
  final Future<FinancialGoal> Function(String id)? complete;
  final Future<void> Function(String id)? delete;
  final Future<FinancialGoal> Function(
      String id, GoalContribution contribution)? recordContribution;

  @override
  State<FinancialGoalScreen> createState() => _FinancialGoalScreenState();
}

class _FinancialGoalScreenState extends State<FinancialGoalScreen> {
  FinancialGoalList? _data;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool preserveData = false}) async {
    setState(() {
      _loading = !preserveData;
      _refreshing = preserveData;
      _error = null;
    });
    try {
      final data = await (widget.load?.call() ??
          BackendApiService().fetchFinancialGoals());
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _mutate(Future<void> Function() action) async {
    try {
      await action();
      await _load(preserveData: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Unable to update goal: $error'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  void _showEditor([FinancialGoal? goal]) {
    final name = TextEditingController(text: goal?.name ?? '');
    final target = TextEditingController(text: goal?.targetAmount ?? '');
    final due = TextEditingController(
        text: goal == null ? '' : _formatDate(goal.targetDate));
    final existingAllocation = goal != null && goal.allocations.isNotEmpty
        ? goal.allocations.first
        : null;
    final allocationReference =
        TextEditingController(text: existingAllocation?.reference ?? '');
    final allocationAmount =
        TextEditingController(text: existingAllocation?.amount ?? '');
    final account =
        TextEditingController(text: existingAllocation?.linkedAccountId ?? '');
    final plannedAmount =
        TextEditingController(text: goal?.contributionRule?.amount ?? '');
    String priority = goal?.priority ?? 'MEDIUM';
    String cadence = goal?.contributionRule?.cadence ?? 'MONTHLY';
    String currency = goal?.currency ?? 'INR';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(
              goal == null ? 'Create financial goal' : 'Edit financial goal'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Goal name')),
                TextField(
                  controller: target,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Target amount'),
                ),
                TextField(
                    controller: due,
                    decoration: const InputDecoration(
                        labelText: 'Target date (YYYY-MM-DD)')),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const ['LOW', 'MEDIUM', 'HIGH']
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text(_title(value))))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => priority = value ?? priority),
                ),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: const ['INR', 'USD', 'EUR']
                      .map((value) =>
                          DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => currency = value ?? currency),
                ),
                const Divider(),
                TextField(
                  controller: allocationReference,
                  decoration: const InputDecoration(
                      labelText: 'Explicit savings allocation reference'),
                ),
                TextField(
                  controller: allocationAmount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Explicitly allocated savings'),
                ),
                TextField(
                    controller: account,
                    decoration: const InputDecoration(
                        labelText: 'Linked account ID (optional)')),
                const Divider(),
                TextField(
                  controller: plannedAmount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Planned contribution (optional)'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: cadence,
                  decoration:
                      const InputDecoration(labelText: 'Contribution cadence'),
                  items: const [
                    'WEEKLY',
                    'BIWEEKLY',
                    'MONTHLY',
                    'QUARTERLY',
                    'YEARLY'
                  ]
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text(_title(value))))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => cadence = value ?? cadence),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final targetDate = DateTime.tryParse(due.text.trim());
                final allocation = allocationReference.text.trim().isEmpty &&
                        allocationAmount.text.trim().isEmpty
                    ? (goal?.allocations ?? const <GoalAllocation>[])
                    : [
                        GoalAllocation(
                          reference: allocationReference.text.trim(),
                          amount: allocationAmount.text.trim(),
                          linkedAccountId: account.text.trim().isEmpty
                              ? null
                              : account.text.trim(),
                        ),
                        ...?goal?.allocations.skip(1),
                      ];
                if (name.text.trim().isEmpty ||
                    target.text.trim().isEmpty ||
                    targetDate == null ||
                    allocation.any((item) =>
                        item.reference.isEmpty || item.amount.isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Enter a name, valid target amount/date, and complete allocation details.')));
                  return;
                }
                final edited = FinancialGoal(
                  id: goal?.id ?? '',
                  name: name.text.trim(),
                  targetAmount: target.text.trim(),
                  currency: currency,
                  targetDate: DateTime.utc(
                      targetDate.year, targetDate.month, targetDate.day),
                  priority: priority,
                  lifecycle: goal?.lifecycle ?? 'ACTIVE',
                  allocations: allocation,
                  contributions: goal?.contributions ?? const [],
                  contributionRule: plannedAmount.text.trim().isEmpty
                      ? null
                      : GoalContributionRule(
                          amount: plannedAmount.text.trim(), cadence: cadence),
                );
                _mutate(() async {
                  if (goal == null) {
                    await (widget.create?.call(edited) ??
                        BackendApiService().createFinancialGoal(edited));
                  } else {
                    await (widget.update?.call(edited) ??
                        BackendApiService().updateFinancialGoal(edited));
                  }
                });
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      name.dispose();
      target.dispose();
      due.dispose();
      allocationReference.dispose();
      allocationAmount.dispose();
      account.dispose();
      plannedAmount.dispose();
    });
  }

  void _showContributionEditor(FinancialGoal goal) {
    final amount = TextEditingController();
    final date = TextEditingController(text: _formatDate(DateTime.now()));
    final evidence = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Record contribution to ${goal.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: amount,
              decoration: const InputDecoration(labelText: 'Amount')),
          TextField(
              controller: date,
              decoration:
                  const InputDecoration(labelText: 'Date (YYYY-MM-DD)')),
          TextField(
              controller: evidence,
              decoration: const InputDecoration(
                  labelText: 'Transaction evidence ID (optional)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final parsedDate = DateTime.tryParse(date.text.trim());
              if (amount.text.trim().isEmpty || parsedDate == null) return;
              final contribution = GoalContribution(
                id: '${parsedDate.toUtc().microsecondsSinceEpoch}-${amount.text.trim()}',
                amount: amount.text.trim(),
                contributedOn: DateTime.utc(
                    parsedDate.year, parsedDate.month, parsedDate.day),
                evidenceReference:
                    evidence.text.trim().isEmpty ? null : evidence.text.trim(),
              );
              _mutate(() async {
                await (widget.recordContribution?.call(goal.id, contribution) ??
                    BackendApiService().recordFinancialGoalContribution(
                        goal.id, contribution, goal.currency));
              });
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Record'),
          ),
        ],
      ),
    ).whenComplete(() {
      amount.dispose();
      date.dispose();
      evidence.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final goals = _data?.goals ?? const <FinancialGoal>[];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Financial goals'),
        actions: [
          IconButton(
            tooltip: 'Refresh financial goals',
            onPressed: _loading || _refreshing
                ? null
                : () => _load(preserveData: true),
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showEditor,
        icon: const Icon(Icons.add),
        label: const Text('Add goal'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data == null
              ? _ErrorState(error: _error!, retry: _load)
              : RefreshIndicator(
                  onRefresh: () => _load(preserveData: true),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('Savings goals',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text(
                        'Only explicitly assigned savings are counted. Projection results are predictions, not guarantees.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      if (_refreshing || _error != null)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                              'Showing stale server data. Refresh to verify the latest goals.',
                              style: TextStyle(color: AppColors.warningLight)),
                        ),
                      if (goals.isEmpty) const _EmptyState(),
                      ...goals.map(_goalCard),
                    ],
                  ),
                ),
    );
  }

  Widget _goalCard(FinancialGoal goal) {
    final projection = goal.projection;
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(goal.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Chip(label: Text(_title(goal.lifecycle))),
          ]),
          Text(
              '${goal.currency} ${goal.targetAmount} by ${_formatDate(goal.targetDate)} · ${_title(goal.priority)}'),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: goal.progress),
          if (projection != null) ...[
            const SizedBox(height: 10),
            Text(
                '${projection.currency} ${projection.amountRemaining} remaining'),
            Text(
                '${projection.currency} ${projection.requiredMonthlyContribution} / month required'),
            Text(
                'Observed: ${projection.currency} ${projection.observedMonthlyContribution} / month'),
            Text(projection.projectedCompletionDate == null
                ? 'Projection needs contribution data'
                : 'Expected completion: ${_formatDate(projection.projectedCompletionDate!)}'),
            Text(
                'Monthly ${projection.monthlyShortfallOrSurplus.startsWith('-') ? 'shortfall' : 'surplus'}: '
                '${projection.currency} ${projection.monthlyShortfallOrSurplus}'),
            if (projection.minimumBalanceBreached)
              const Text(
                  'Required pace would breach your preferred minimum balance.',
                  style: TextStyle(color: AppColors.danger)),
            if (projection.warnings.isNotEmpty)
              Text('Warnings: ${projection.warnings.map(_title).join(', ')}',
                  style: const TextStyle(color: AppColors.warningLight)),
          ],
          Wrap(spacing: 4, children: [
            IconButton(
                tooltip: 'Edit goal',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _showEditor(goal)),
            if (goal.lifecycle == 'ACTIVE')
              IconButton(
                tooltip: 'Record contribution',
                icon: const Icon(Icons.savings_outlined),
                onPressed: () => _showContributionEditor(goal),
              ),
            if (goal.lifecycle == 'ACTIVE')
              TextButton(
                onPressed: () => _mutate(() async {
                  await (widget.pause?.call(goal.id) ??
                      BackendApiService().pauseFinancialGoal(goal.id));
                }),
                child: const Text('Pause'),
              ),
            if (goal.lifecycle == 'PAUSED')
              TextButton(
                onPressed: () => _mutate(() async {
                  await (widget.resume?.call(goal.id) ??
                      BackendApiService().resumeFinancialGoal(goal.id));
                }),
                child: const Text('Resume'),
              ),
            if (goal.lifecycle != 'COMPLETED')
              TextButton(
                onPressed: () => _mutate(() async {
                  await (widget.complete?.call(goal.id) ??
                      BackendApiService().completeFinancialGoal(goal.id));
                }),
                child: const Text('Complete'),
              ),
            TextButton(
              onPressed: () => _mutate(() async {
                await (widget.delete?.call(goal.id) ??
                    BackendApiService().deleteFinancialGoal(goal.id));
              }),
              child: const Text('Delete'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 70),
        child: Center(
            child: Text(
                'No financial goals yet. Add a goal and explicitly assign savings.')),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.retry});
  final Object error;
  final Future<void> Function({bool preserveData}) retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Financial goals are unavailable'),
          const SizedBox(height: 8),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => retry(), child: const Text('Retry')),
        ]),
      );
}

String _title(String value) => value
    .toLowerCase()
    .split('_')
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _formatDate(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day)
        .toIso8601String()
        .substring(0, 10);
