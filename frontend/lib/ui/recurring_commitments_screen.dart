import 'package:flutter/material.dart';

import '../domain/recurring_commitment.dart';
import '../services/recurring_commitments_api_service.dart';
import 'theme/app_theme.dart';

class RecurringCommitmentsScreen extends StatefulWidget {
  const RecurringCommitmentsScreen({
    super.key,
    this.load,
    this.confirm,
    this.ignore,
    this.cancel,
    this.restore,
    this.update,
  });

  final Future<RecurringCommitmentList> Function()? load;
  final Future<RecurringCommitment> Function(String id)? confirm;
  final Future<RecurringCommitment> Function(String id)? ignore;
  final Future<RecurringCommitment> Function(String id)? cancel;
  final Future<RecurringCommitment> Function(String id)? restore;
  final Future<RecurringCommitment> Function(RecurringCommitment commitment)?
      update;

  @override
  State<RecurringCommitmentsScreen> createState() =>
      _RecurringCommitmentsScreenState();
}

class _RecurringCommitmentsScreenState
    extends State<RecurringCommitmentsScreen> {
  RecurringCommitmentList? _data;
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
      _error = null;
      _loading = !preserveData;
      _refreshing = preserveData;
    });
    try {
      final result = await (widget.load?.call() ??
          RecurringCommitmentsApiService().fetch());
      if (!mounted) return;
      setState(() {
        _data = result;
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

  Future<void> _operate(
      String id, Future<RecurringCommitment> Function(String) action) async {
    try {
      await action(id);
      await _load(preserveData: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Unable to update commitment: $error'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  void _showEditor(RecurringCommitment commitment) {
    final minimum = TextEditingController(text: commitment.minimumAmount);
    final maximum = TextEditingController(text: commitment.maximumAmount);
    final nextPayment =
        TextEditingController(text: _date(commitment.nextPaymentDate));
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${commitment.name}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: minimum,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Minimum expected amount'),
            ),
            TextField(
              controller: maximum,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Maximum expected amount'),
            ),
            TextField(
              controller: nextPayment,
              decoration:
                  const InputDecoration(labelText: 'Next payment (YYYY-MM-DD)'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final date = DateTime.tryParse(nextPayment.text.trim());
              final min = double.tryParse(minimum.text.trim());
              final max = double.tryParse(maximum.text.trim());
              if (date == null ||
                  min == null ||
                  max == null ||
                  min <= 0 ||
                  max < min) {
                _showEditError(
                    'Enter a valid amount range and next payment date.');
                return;
              }
              final updated = RecurringCommitment(
                id: commitment.id,
                name: commitment.name,
                classification: commitment.classification,
                cadence: commitment.cadence,
                minimumAmount: minimum.text.trim(),
                maximumAmount: maximum.text.trim(),
                currency: commitment.currency,
                nextPaymentDate: DateTime.utc(date.year, date.month, date.day),
                confidence: commitment.confidence,
                supportingTransactionIds: commitment.supportingTransactionIds,
                status: commitment.status,
                state: commitment.state,
                origin: commitment.origin,
                authoritativeReference: commitment.authoritativeReference,
              );
              try {
                await (widget.update?.call(updated) ??
                    RecurringCommitmentsApiService().update(updated));
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                await _load(preserveData: true);
              } catch (error) {
                if (mounted)
                  _showEditError('Unable to update commitment: $error');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(() {
      minimum.dispose();
      maximum.dispose();
      nextPayment.dispose();
    });
  }

  void _showEditError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final commitments = _data?.commitments ?? const <RecurringCommitment>[];
    final candidates = commitments.where((item) => item.isCandidate).toList();
    final obligations = commitments.where((item) => !item.isCandidate).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Recurring commitments'),
        actions: [
          IconButton(
            tooltip: 'Refresh recurring commitments',
            onPressed: _loading || _refreshing
                ? null
                : () => _load(preserveData: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
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
                      const Text('Confirmed obligations',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text(
                        'Only confirmed obligations contribute to fixed-cost planning. '
                        'Authoritative bills and EMIs are shown once.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      if (_refreshing || _error != null)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                              'Showing stale server data. Refresh to verify the latest commitments.',
                              style: TextStyle(color: AppColors.warningLight)),
                        ),
                      if (obligations.isEmpty) const _EmptyObligationsState(),
                      ...obligations.map(_obligationCard),
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Text('Possible recurring commitments',
                            style: TextStyle(
                                fontSize: 19, fontWeight: FontWeight.bold)),
                      ),
                      const Text(
                        'Candidates are never treated as obligations until you confirm them.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      if (candidates.isEmpty) const _InsufficientHistoryState(),
                      ...candidates.map(_candidateCard),
                    ],
                  ),
                ),
    );
  }

  Widget _obligationCard(RecurringCommitment commitment) => Card(
        color: AppColors.surface,
        margin: const EdgeInsets.only(top: 12),
        child: ListTile(
          title: Text(commitment.name),
          subtitle: Text('${_title(commitment.classification)} · '
              '${commitment.currency} ${commitment.minimumAmount}${commitment.isVariableAmount ? '–${commitment.maximumAmount}' : ''} · '
              '${_title(commitment.cadence)}\n${_stateLabel(commitment)} · Next ${_date(commitment.nextPaymentDate)}'),
          isThreeLine: true,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (commitment.isVariableAmount)
              const Chip(label: Text('Variable amount')),
            if (commitment.status == 'CANCELLED')
              TextButton(
                  onPressed: () => _operate(
                      commitment.id,
                      widget.restore ??
                          RecurringCommitmentsApiService().restore),
                  child: const Text('Restore'))
            else if (commitment.isAuthoritative)
              const Chip(label: Text('Authoritative'))
            else
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: 'Edit commitment',
                    onPressed: () => _showEditor(commitment),
                    icon: const Icon(Icons.edit_outlined)),
                TextButton(
                    onPressed: () => _operate(
                        commitment.id,
                        widget.cancel ??
                            RecurringCommitmentsApiService().cancel),
                    child: const Text('Cancel')),
              ]),
          ]),
        ),
      );

  Widget _candidateCard(RecurringCommitment commitment) => Card(
        color: AppColors.surface,
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(commitment.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
                '${commitment.currency} ${commitment.minimumAmount} · ${_title(commitment.cadence)} · '
                '${(commitment.confidence * 100).round()}% confidence'),
            Text(
                '${commitment.supportingTransactionIds.length} supporting transactions',
                style: const TextStyle(color: AppColors.textSecondary)),
            Row(children: [
              TextButton(
                onPressed: () => _operate(commitment.id,
                    widget.ignore ?? RecurringCommitmentsApiService().ignore),
                child: const Text('Ignore'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _operate(commitment.id,
                    widget.confirm ?? RecurringCommitmentsApiService().confirm),
                child: const Text('Confirm'),
              ),
            ]),
          ]),
        ),
      );
}

class _EmptyObligationsState extends StatelessWidget {
  const _EmptyObligationsState();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 42),
        child: Center(child: Text('No confirmed recurring commitments yet.')),
      );
}

class _InsufficientHistoryState extends StatelessWidget {
  const _InsufficientHistoryState();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 34),
        child: Center(
          child: Text(
              'Need at least two matching reviewed debit transactions before a candidate can be suggested.',
              textAlign: TextAlign.center),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.retry});
  final Object error;
  final Future<void> Function({bool preserveData}) retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Recurring commitments are unavailable'),
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

String _stateLabel(RecurringCommitment commitment) {
  if (commitment.state == 'VARIABLE_AMOUNT') return 'Variable amount';
  if (commitment.state == 'LATE') return 'Late expected occurrence';
  if (commitment.state == 'MISSED') return 'Missed expected occurrence';
  return 'On track';
}

String _date(DateTime value) =>
    value.toUtc().toIso8601String().substring(0, 10);
