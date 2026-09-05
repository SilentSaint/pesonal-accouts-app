import 'package:flutter/material.dart';

import '../domain/financial_context_item.dart';
import '../services/backend_api_service.dart';
import 'theme/app_theme.dart';

class FinancialContextScreen extends StatefulWidget {
  const FinancialContextScreen({
    super.key,
    this.load,
    this.create,
    this.update,
    this.deactivate,
    this.delete,
  });

  final Future<FinancialContextList> Function()? load;
  final Future<FinancialContextItem> Function(FinancialContextItem item)?
      create;
  final Future<FinancialContextItem> Function(FinancialContextItem item)?
      update;
  final Future<FinancialContextItem> Function(String id)? deactivate;
  final Future<void> Function(String id)? delete;

  @override
  State<FinancialContextScreen> createState() => _FinancialContextScreenState();
}

class _FinancialContextScreenState extends State<FinancialContextScreen> {
  FinancialContextList? _context;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;

  static const _specifications = <String, _ContextSpecification>{
    'PREFERRED_MINIMUM_CASH_BALANCE': _ContextSpecification(
      'Preferred minimum cash balance',
      ['amount', 'currency'],
      ['CASH_FLOW_FORECAST', 'FINANCIAL_HEALTH'],
    ),
    'RELATIONSHIP_ALIAS': _ContextSpecification(
      'Relationship alias',
      ['alias', 'relationship'],
      ['SHARED_EXPENSE_ANALYSIS'],
    ),
    'SHARED_EXPENSE_RULE': _ContextSpecification(
      'Shared-expense rule',
      ['appliesTo', 'splitPercentage'],
      ['SHARED_EXPENSE_ANALYSIS'],
    ),
    'MAJOR_PURCHASE_INTENTION': _ContextSpecification(
      'Major-purchase intention',
      ['plannedAmount', 'currency', 'targetDate'],
      ['CASH_FLOW_FORECAST', 'FINANCIAL_HEALTH'],
    ),
    'ANALYSIS_PREFERENCE': _ContextSpecification(
      'Analysis preference',
      ['analysisMode'],
      ['FINANCIAL_ANALYSIS'],
    ),
  };

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
          BackendApiService().fetchFinancialContext());
      if (mounted) {
        setState(() {
          _context = result;
          _loading = false;
          _refreshing = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _save(FinancialContextItem item, bool isNew) async {
    try {
      if (isNew) {
        await (widget.create?.call(item) ??
            BackendApiService().createFinancialContext(item));
      } else {
        await (widget.update?.call(item) ??
            BackendApiService().updateFinancialContext(item));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await _load(preserveData: true);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _deactivate(String id) async {
    try {
      await (widget.deactivate?.call(id) ??
          BackendApiService().deactivateFinancialContext(id));
      await _load(preserveData: true);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await (widget.delete?.call(id) ??
          BackendApiService().deleteFinancialContext(id));
      await _load(preserveData: true);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Unable to save financial context: $error'),
      backgroundColor: AppColors.danger,
    ));
  }

  void _showEditor([FinancialContextItem? existing]) {
    String selectedType = existing?.type ?? _specifications.keys.first;
    final label = TextEditingController(text: existing?.label ?? '');
    final effectiveFrom = TextEditingController(
        text: existing?.effectiveFrom == null
            ? ''
            : _date(existing!.effectiveFrom!));
    final effectiveUntil = TextEditingController(
        text: existing?.effectiveUntil == null
            ? ''
            : _date(existing!.effectiveUntil!));
    String provenance = existing?.provenance ?? 'USER_DECLARED';
    Set<String> capabilities = Set<String>.from(
        existing?.capabilities ?? _specifications[selectedType]!.capabilities);
    final fields = <String, TextEditingController>{};
    void resetFields() {
      for (final controller in fields.values) {
        controller.dispose();
      }
      fields
        ..clear()
        ..addEntries(_specifications[selectedType]!.fields.map((name) =>
            MapEntry(name,
                TextEditingController(text: existing?.values[name] ?? ''))));
    }

    resetFields();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
              existing == null
                  ? 'Add financial context'
                  : 'Edit financial context',
              style: const TextStyle(color: AppColors.textPrimary)),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedType),
                    initialValue: selectedType,
                    dropdownColor: AppColors.surfaceElevated,
                    decoration:
                        const InputDecoration(labelText: 'Context type'),
                    items: _specifications.entries
                        .map((entry) => DropdownMenuItem(
                            value: entry.key, child: Text(entry.value.title)))
                        .toList(),
                    onChanged: existing != null
                        ? null
                        : (value) {
                            if (value == null) return;
                            setDialogState(() {
                              selectedType = value;
                              capabilities = Set<String>.from(
                                  _specifications[value]!.capabilities);
                              resetFields();
                            });
                          },
                  ),
                  TextField(
                    controller: label,
                    decoration: const InputDecoration(labelText: 'Label'),
                  ),
                  ...fields.entries.map((entry) => TextField(
                        controller: entry.value,
                        decoration:
                            InputDecoration(labelText: _fieldLabel(entry.key)),
                      )),
                  if (existing == null)
                    DropdownButtonFormField<String>(
                      initialValue: provenance,
                      dropdownColor: AppColors.surfaceElevated,
                      decoration:
                          const InputDecoration(labelText: 'Provenance'),
                      items: const [
                        DropdownMenuItem(
                            value: 'USER_DECLARED',
                            child: Text('User declared')),
                        DropdownMenuItem(
                            value: 'USER_CONFIRMED',
                            child: Text('User confirmed')),
                        DropdownMenuItem(
                            value: 'IMPORTED_USER_CONFIRMED',
                            child: Text('Imported and user confirmed')),
                      ],
                      onChanged: (value) => setDialogState(
                          () => provenance = value ?? provenance),
                    ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Capabilities that may use this item',
                        style: Theme.of(dialogContext).textTheme.labelLarge),
                  ),
                  ..._specifications[selectedType]!
                      .capabilities
                      .map((capability) => CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(_title(capability)),
                            value: capabilities.contains(capability),
                            onChanged: (selected) => setDialogState(() {
                              selected == true
                                  ? capabilities.add(capability)
                                  : capabilities.remove(capability);
                            }),
                          )),
                  TextField(
                    controller: effectiveFrom,
                    decoration: const InputDecoration(
                        labelText: 'Effective from (YYYY-MM-DD, optional)'),
                  ),
                  TextField(
                    controller: effectiveUntil,
                    decoration: const InputDecoration(
                        labelText: 'Effective until (YYYY-MM-DD, optional)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final values = Map<String, String>.fromEntries(fields.entries
                    .map((entry) =>
                        MapEntry(entry.key, entry.value.text.trim())));
                if (label.text.trim().isEmpty ||
                    values.values.any((value) => value.isEmpty) ||
                    capabilities.isEmpty) {
                  _showError(
                      'Complete all type-specific fields and choose a capability.');
                  return;
                }
                final starts = _parseDate(effectiveFrom.text);
                final ends = _parseDate(effectiveUntil.text);
                if ((effectiveFrom.text.trim().isNotEmpty && starts == null) ||
                    (effectiveUntil.text.trim().isNotEmpty && ends == null)) {
                  _showError('Effective dates must use YYYY-MM-DD.');
                  return;
                }
                final now = DateTime.now().toUtc();
                final item = FinancialContextItem(
                  id: existing?.id ?? '',
                  type: selectedType,
                  label: label.text.trim(),
                  values: values,
                  capabilities: capabilities.toList()..sort(),
                  provenance: provenance,
                  active: existing?.active ?? true,
                  createdAt: existing?.createdAt ?? now,
                  updatedAt: now,
                  effectiveFrom: starts,
                  effectiveUntil: ends,
                );
                _save(item, existing == null);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      label.dispose();
      effectiveFrom.dispose();
      effectiveUntil.dispose();
      for (final controller in fields.values) {
        controller.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _context?.items ?? const <FinancialContextItem>[];
    final noEligible =
        items.isNotEmpty && !items.any((item) => item.isEligible);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Financial context'),
        actions: [
          IconButton(
            tooltip: 'Refresh financial context',
            onPressed: _loading || _refreshing
                ? null
                : () => _load(preserveData: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add context'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _context == null
              ? _ErrorState(error: _error!, retry: _load)
              : RefreshIndicator(
                  onRefresh: () => _load(preserveData: true),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Explicit financial context',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Only items you declare or confirm are used. Conflicting and expired items are never selected automatically.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      if (_refreshing || _error != null) _staleBanner(),
                      if (items.isEmpty) const _EmptyState(),
                      if (noEligible) const _InsufficientState(),
                      ...items.map(_itemCard),
                    ],
                  ),
                ),
    );
  }

  Widget _staleBanner() => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(8)),
        child: Text(
          _refreshing
              ? 'Showing stale server data while refreshing.'
              : 'Showing stale server data. Refresh failed; try again.',
          style: const TextStyle(color: AppColors.warningLight),
        ),
      );

  Widget _itemCard(FinancialContextItem item) {
    final conflict = item.status == 'CONFLICTING';
    final color = conflict
        ? AppColors.dangerLight
        : item.isEligible
            ? AppColors.successLight
            : AppColors.warningLight;
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(item.label,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold))),
            _StatusChip(label: item.status, color: color),
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') _showEditor(item);
                if (action == 'deactivate') _deactivate(item.id);
                if (action == 'delete') _confirmDelete(item);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (item.active)
                  const PopupMenuItem(
                      value: 'deactivate', child: Text('Deactivate')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          Text(_title(item.type),
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(label: Text('Provenance: ${_title(item.provenance)}')),
              ...item.capabilities
                  .map((capability) => Chip(label: Text(_title(capability)))),
            ],
          ),
          const SizedBox(height: 10),
          ...item.values.entries.map(
              (entry) => Text('${_fieldLabel(entry.key)}: ${entry.value}')),
          Text(
              'Effective: ${_dateOrAny(item.effectiveFrom)} – ${_dateOrAny(item.effectiveUntil)}',
              style: const TextStyle(color: AppColors.textSecondary)),
          Text('Updated: ${item.updatedAt.toLocal()}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          if (conflict)
            Text('Resolve conflict with: ${item.conflictIds.join(', ')}',
                style: const TextStyle(color: AppColors.dangerLight)),
        ]),
      ),
    );
  }

  void _confirmDelete(FinancialContextItem item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete financial context?'),
        content: Text(
            '${item.label} will no longer be eligible for future calculations.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _delete(item.id);
              },
              child: const Text('Delete')),
        ],
      ),
    );
  }
}

class _ContextSpecification {
  const _ContextSpecification(this.title, this.fields, this.capabilities);
  final String title;
  final List<String> fields;
  final List<String> capabilities;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 72),
        child: Center(
            child: Text(
                'No financial context yet. Add an explicit fact or preference.',
                textAlign: TextAlign.center)),
      );
}

class _InsufficientState extends StatelessWidget {
  const _InsufficientState();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 18),
        child: Text(
          'Insufficient eligible context for analysis. Reactivate, update, or resolve the items below.',
          style: TextStyle(color: AppColors.warningLight),
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
          const Text('Financial context is unavailable'),
          const SizedBox(height: 8),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => retry(), child: const Text('Retry')),
        ]),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Chip(
      label: Text(_title(label)),
      backgroundColor: color.withValues(alpha: 0.18));
}

String _title(String value) => value
    .toLowerCase()
    .split('_')
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
String _fieldLabel(String value) => _title(value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)}_${match.group(2)}'));
DateTime? _parseDate(String value) {
  if (value.trim().isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final parsed = DateTime.tryParse(value.trim());
  return parsed == null
      ? null
      : DateTime.utc(parsed.year, parsed.month, parsed.day);
}

String _date(DateTime value) =>
    value.toUtc().toIso8601String().substring(0, 10);
String _dateOrAny(DateTime? value) => value == null ? 'Any date' : _date(value);
