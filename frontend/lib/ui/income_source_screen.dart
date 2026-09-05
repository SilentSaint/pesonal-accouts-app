import 'package:flutter/material.dart';

import '../domain/income_source.dart';
import '../services/backend_api_service.dart';
import 'theme/app_theme.dart';

class IncomeSourceScreen extends StatefulWidget {
  const IncomeSourceScreen({
    super.key,
    this.load,
    this.create,
    this.updateDates,
    this.confirmSuggestion,
    this.rejectSuggestion,
  });

  final Future<IncomeSourceList> Function()? load;
  final Future<IncomeSource> Function(IncomeSource source)? create;
  final Future<IncomeSource> Function(String id, DateTime from, DateTime? to)?
      updateDates;
  final Future<IncomeSource> Function(String id)? confirmSuggestion;
  final Future<IncomeSource> Function(String id)? rejectSuggestion;

  @override
  State<IncomeSourceScreen> createState() => _IncomeSourceScreenState();
}

class _IncomeSourceScreenState extends State<IncomeSourceScreen> {
  IncomeSourceList? _income;
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
      final income = await (widget.load?.call() ??
          BackendApiService().fetchIncomeSources());
      if (!mounted) return;
      setState(() {
        _income = income;
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

  Future<void> _save(IncomeSource source, bool isNew) async {
    try {
      if (isNew) {
        await (widget.create?.call(source) ??
            BackendApiService().createIncomeSource(source));
      } else {
        await (widget.updateDates
                ?.call(source.id, source.effectiveFrom, source.effectiveTo) ??
            BackendApiService().updateIncomeEffectiveDates(
                source.id, source.effectiveFrom, source.effectiveTo));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await _load(preserveData: true);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _respondToSuggestion(String id, bool confirm) async {
    try {
      if (confirm) {
        await (widget.confirmSuggestion?.call(id) ??
            BackendApiService().confirmIncomeSuggestion(id));
      } else {
        await (widget.rejectSuggestion?.call(id) ??
            BackendApiService().rejectIncomeSuggestion(id));
      }
      await _load(preserveData: true);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Unable to update income sources: $error'),
      backgroundColor: AppColors.danger,
    ));
  }

  void _showEditor([IncomeSource? existing]) {
    final name = TextEditingController(text: existing?.name ?? '');
    final amount = TextEditingController(text: existing?.amount ?? '');
    final account =
        TextEditingController(text: existing?.linkedAccountId ?? '');
    final from = TextEditingController(
        text: existing == null ? '' : _date(existing.effectiveFrom));
    final to = TextEditingController(
        text:
            existing?.effectiveTo == null ? '' : _date(existing!.effectiveTo!));
    String type = existing?.type ?? 'FIXED';
    String cadence = existing?.cadence ?? 'MONTHLY';
    String currency = existing?.currency ?? 'INR';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(
              existing == null ? 'Add income source' : 'Edit effective dates'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (existing == null) ...[
                  TextField(
                      controller: name,
                      decoration: const InputDecoration(
                          labelText: 'Income source name')),
                  TextField(
                    controller: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Income type'),
                    items: const ['FIXED', 'VARIABLE', 'ONE_TIME', 'RECURRING']
                        .map((value) => DropdownMenuItem(
                            value: value, child: Text(_title(value))))
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      type = value ?? type;
                      if (type == 'ONE_TIME') cadence = 'ONCE';
                    }),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: cadence,
                    decoration: const InputDecoration(labelText: 'Cadence'),
                    items: const [
                      'ONCE',
                      'WEEKLY',
                      'BIWEEKLY',
                      'MONTHLY',
                      'QUARTERLY',
                      'YEARLY'
                    ]
                        .map((value) => DropdownMenuItem(
                            value: value, child: Text(_title(value))))
                        .toList(),
                    onChanged: type == 'ONE_TIME'
                        ? null
                        : (value) =>
                            setDialogState(() => cadence = value ?? cadence),
                  ),
                  TextField(
                      controller: account,
                      decoration: const InputDecoration(
                          labelText: 'Linked account ID')),
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
                ],
                TextField(
                    controller: from,
                    decoration: const InputDecoration(
                        labelText: 'Effective from (YYYY-MM-DD)')),
                TextField(
                    controller: to,
                    decoration: const InputDecoration(
                        labelText: 'Effective until (YYYY-MM-DD, optional)')),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final start = _parseDate(from.text);
                final end = _parseDate(to.text);
                if (start == null ||
                    (to.text.trim().isNotEmpty && end == null) ||
                    (end != null && end.isBefore(start)) ||
                    (existing == null &&
                        (name.text.trim().isEmpty ||
                            amount.text.trim().isEmpty ||
                            account.text.trim().isEmpty))) {
                  _showError(
                      'Complete valid source details and effective dates.');
                  return;
                }
                final source = existing == null
                    ? IncomeSource(
                        id: '',
                        name: name.text.trim(),
                        type: type,
                        amount: amount.text.trim(),
                        currency: currency,
                        cadence: cadence,
                        effectiveFrom: start,
                        effectiveTo: end,
                        linkedAccountId: account.text.trim(),
                        confirmationStatus: 'CONFIRMED',
                        sourceTransactionIds: const [],
                      )
                    : IncomeSource(
                        id: existing.id,
                        name: existing.name,
                        type: existing.type,
                        amount: existing.amount,
                        currency: existing.currency,
                        cadence: existing.cadence,
                        effectiveFrom: start,
                        effectiveTo: end,
                        linkedAccountId: existing.linkedAccountId,
                        confirmationStatus: existing.confirmationStatus,
                        sourceTransactionIds: existing.sourceTransactionIds,
                      );
                _save(source, existing == null);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      name.dispose();
      amount.dispose();
      account.dispose();
      from.dispose();
      to.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _income;
    final sources = data?.sources ?? const <IncomeSource>[];
    final suggestions = data?.suggestions ?? const <IncomeSuggestion>[];
    final conflicting = suggestions
        .where((suggestion) =>
            suggestions
                .where((other) =>
                    other.source.linkedAccountId ==
                    suggestion.source.linkedAccountId)
                .length >
            1)
        .isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Income sources'),
        actions: [
          IconButton(
            tooltip: 'Refresh income sources',
            onPressed: _loading || _refreshing
                ? null
                : () => _load(preserveData: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showEditor,
        icon: const Icon(Icons.add),
        label: const Text('Add income source'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && data == null
              ? _ErrorState(error: _error!, retry: _load)
              : RefreshIndicator(
                  onRefresh: () => _load(preserveData: true),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('Confirmed income',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text(
                        'Only sources you confirm contribute to expected income. Suggestions remain uncertain.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      if (_refreshing || _error != null) _staleBanner(),
                      if (sources.isEmpty) const _EmptyState(),
                      ...sources.map(_sourceCard),
                      if (suggestions.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: Text('Suggested recurring credits',
                              style: TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.bold)),
                        ),
                        if (conflicting)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Conflicting suggestions share an account. Confirm only the source you recognize.',
                              style: TextStyle(color: AppColors.warningLight),
                            ),
                          ),
                        ...suggestions.map(_suggestionCard),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _staleBanner() => const Padding(
        padding: EdgeInsets.only(top: 14),
        child: Text(
            'Showing stale server data. Refresh to verify the latest income sources.',
            style: TextStyle(color: AppColors.warningLight)),
      );

  Widget _sourceCard(IncomeSource source) => Card(
        color: AppColors.surface,
        margin: const EdgeInsets.only(top: 14),
        child: ListTile(
          title: Text(source.name),
          subtitle: Text(
            '${source.currency} ${source.amount} · ${_title(source.cadence)}\n'
            'Account: ${source.linkedAccountId}${source.isStaleAt(DateTime.now()) ? ' · Stale' : ''}',
          ),
          isThreeLine: true,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (source.isVariable) const Chip(label: Text('Irregular income')),
            IconButton(
              tooltip: 'Edit effective dates',
              icon: const Icon(Icons.edit_calendar_outlined),
              onPressed: () => _showEditor(source),
            ),
          ]),
        ),
      );

  Widget _suggestionCard(IncomeSuggestion suggestion) => Card(
        color: AppColors.surface,
        margin: const EdgeInsets.only(top: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(suggestion.source.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
                '${suggestion.source.currency} ${suggestion.source.amount} · ${_title(suggestion.source.cadence)} · ${(suggestion.confidence * 100).round()}% confidence'),
            Text(
                '${suggestion.source.sourceTransactionIds.length} supporting transactions',
                style: const TextStyle(color: AppColors.textSecondary)),
            Row(children: [
              TextButton(
                  onPressed: () =>
                      _respondToSuggestion(suggestion.source.id, false),
                  child: const Text('Reject')),
              const SizedBox(width: 8),
              ElevatedButton(
                  onPressed: () =>
                      _respondToSuggestion(suggestion.source.id, true),
                  child: const Text('Confirm')),
            ]),
          ]),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 70),
        child: Center(
          child: Text(
              'No confirmed income sources yet. Add one or confirm a suggestion.',
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
          const Text('Income sources are unavailable'),
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

DateTime? _parseDate(String value) {
  if (value.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(value.trim());
  return parsed == null
      ? null
      : DateTime.utc(parsed.year, parsed.month, parsed.day);
}

String _date(DateTime value) =>
    value.toUtc().toIso8601String().substring(0, 10);
