import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/analytics_report.dart';
import '../domain/transaction_item.dart';
import '../services/backend_api_service.dart';
import '../services/report_download.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({
    super.key,
    this.loadReport,
    this.exportReport,
    this.loadEvidence,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<AnalyticsReport> Function(String month)? loadReport;
  final Future<void> Function(String month, String format)? exportReport;
  final Future<AnalyticsEvidencePage> Function(
    String month,
    String currency,
    String? cursor,
  )? loadEvidence;
  final DateTime Function() _now;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late String _selectedMonth;
  AnalyticsReport? _report;
  Object? _error;
  bool _isLoading = true;
  String? _exportingFormat;
  final List<TransactionItem> _evidence = [];
  String? _evidenceCursor;
  Object? _evidenceError;
  bool _isLoadingEvidence = false;

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateFormat('yyyy-MM').format(widget._now());
    _loadAnalytics();
  }

  List<String> get _months => List.generate(12, (index) {
        final current = widget._now();
        final date = DateTime(current.year, current.month - index);
        return DateFormat('yyyy-MM').format(date);
      });

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _evidence.clear();
      _evidenceCursor = null;
      _evidenceError = null;
    });
    try {
      final report = await (widget.loadReport?.call(_selectedMonth) ??
          BackendApiService().fetchAnalyticsReport(month: _selectedMonth));
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadEvidence({bool append = false}) async {
    final report = _report;
    if (report == null || _isLoadingEvidence) return;
    setState(() {
      _isLoadingEvidence = true;
      _evidenceError = null;
      if (!append) {
        _evidence.clear();
        _evidenceCursor = null;
      }
    });
    try {
      final page = await (widget.loadEvidence?.call(
            _selectedMonth,
            report.currency,
            append ? _evidenceCursor : null,
          ) ??
          BackendApiService().fetchAnalyticsEvidence(
            month: _selectedMonth,
            currency: report.currency,
            cursor: append ? _evidenceCursor : null,
            asOf: report.asOf,
          ));
      if (mounted) {
        setState(() {
          _evidence.addAll(page.items);
          _evidenceCursor = page.nextCursor;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _evidenceError = error);
    } finally {
      if (mounted) setState(() => _isLoadingEvidence = false);
    }
  }

  Future<void> _exportData(String format) async {
    final report = _report;
    if (report == null || report.transactionCount == 0) return;
    setState(() => _exportingFormat = format);
    try {
      if (widget.exportReport != null) {
        await widget.exportReport!(_selectedMonth, format);
      } else {
        final export = await BackendApiService().exportAnalyticsReport(
          month: _selectedMonth,
          format: format,
          currency: report.currency,
        );
        downloadReport(export.bytes,
            filename: export.filename, mimeType: export.mimeType);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${format.toUpperCase()} report downloaded.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFB91C1C),
            content: Text('Unable to export report: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingFormat = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Analytics & AI Insights',
            style: TextStyle(color: Colors.white)),
        actions: [
          _exportButton('csv', Icons.table_view_outlined, 'Export CSV'),
          _exportButton('pdf', Icons.picture_as_pdf_outlined, 'Export PDF'),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
      );
    }
    if (_error != null) {
      return _messageState(
        icon: Icons.cloud_off_outlined,
        title: 'Analytics are unavailable',
        message: 'We could not load your server-derived financial report.',
        action: ElevatedButton.icon(
          onPressed: _loadAnalytics,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      );
    }
    final report = _report!;
    if (report.transactionCount == 0) {
      return _messageState(
        icon: Icons.insights_outlined,
        title: 'No spending analytics yet',
        message:
            'There are no persisted transactions for ${_monthLabel(_selectedMonth)}.',
        action: OutlinedButton.icon(
          onPressed: _loadAnalytics,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _monthSelector(),
          const SizedBox(height: 16),
          _cashFlowCards(report),
          const SizedBox(height: 20),
          _insights(report),
          if (!report.isSpendingAnalytics) ...[
            const SizedBox(height: 20),
            _trend(report),
          ],
          const SizedBox(height: 20),
          _categoryBreakdown(report),
          if (report.isSpendingAnalytics) ...[
            const SizedBox(height: 20),
            _evidencePanel(report),
          ],
        ],
      ),
    );
  }

  Widget _exportButton(String format, IconData icon, String tooltip) {
    final enabled = !_isLoading &&
        _error == null &&
        !(_report?.isSpendingAnalytics ?? false) &&
        (_report?.transactionCount ?? 0) > 0;
    final exporting = _exportingFormat == format;
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled && _exportingFormat == null ? () => _exportData(format) : null,
      icon: exporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, color: const Color(0xFF38BDF8)),
    );
  }

  Widget _monthSelector() => Row(
        children: [
          const Text('Report period', style: TextStyle(color: Colors.white70)),
          const Spacer(),
          DropdownButton<String>(
            value: _selectedMonth,
            dropdownColor: const Color(0xFF1E293B),
            style: const TextStyle(color: Colors.white),
            underline: const SizedBox(),
            items: _months
                .map((month) => DropdownMenuItem(
                      value: month,
                      child: Text(_monthLabel(month)),
                    ))
                .toList(growable: false),
            onChanged: (month) {
              if (month == null || month == _selectedMonth) return;
              setState(() => _selectedMonth = month);
              _loadAnalytics();
            },
          ),
        ],
      );

  Widget _cashFlowCards(AnalyticsReport report) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (!report.isSpendingAnalytics)
            _metricCard('Income', _money(report.cashFlow.income, report.currency),
                const Color(0xFF34D399)),
          _metricCard('Net personal expense',
              _money(report.cashFlow.netPersonalExpense, report.currency),
              const Color(0xFFF87171)),
          if (!report.isSpendingAnalytics)
            _metricCard('Net savings',
                _money(report.cashFlow.netSavings, report.currency),
                const Color(0xFF38BDF8)),
        ],
      );

  Widget _metricCard(String label, String value, Color color) => SizedBox(
        width: 170,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: _panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white60, fontSize: 11)),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
        ),
      );

  Widget _insights(AnalyticsReport report) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _panelDecoration(color: const Color(0xFF312E81)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.auto_awesome, color: Color(0xFFFBBF24), size: 20),
              const SizedBox(width: 8),
              Text(report.isSpendingAnalytics ? 'Calculation details' : 'AI Financial Insights',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 10),
            ...report.aiInsights.map((insight) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $insight',
                      style: const TextStyle(color: Colors.white70, height: 1.35)),
                )),
          ],
        ),
      );

  Widget _evidencePanel(AnalyticsReport report) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _panelDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Evidence',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          if (report.formulaId != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Formula: ${report.formulaId} v${report.formulaVersion ?? ''}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          if (_evidence.isEmpty && !_isLoadingEvidence && _evidenceError == null)
            OutlinedButton.icon(
              onPressed: _loadEvidence,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View calculation evidence'),
            ),
          if (_isLoadingEvidence)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
            ),
          if (_evidenceError != null)
            TextButton(
              onPressed: _loadEvidence,
              child: const Text('Retry loading evidence'),
            ),
          ..._evidence.map((transaction) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(transaction.merchantName,
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(transaction.timestamp.toLocal().toString(),
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
                trailing: Text(
                  _money(transaction.effectivePersonalExpense, report.currency),
                  style: const TextStyle(color: Color(0xFF38BDF8)),
                ),
              )),
          if (_evidenceCursor != null && !_isLoadingEvidence)
            TextButton(
              onPressed: () => _loadEvidence(append: true),
              child: const Text('Load more'),
            ),
        ]),
      );

  Widget _trend(AnalyticsReport report) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cash Flow Trend',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _panelDecoration(),
            child: Column(
              children: report.spendingTrend
                  .map((day) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          SizedBox(
                              width: 86,
                              child: Text(day.date,
                                  style: const TextStyle(color: Colors.white60, fontSize: 12))),
                          Expanded(
                            child: Text(
                              'In ${_money(day.income, report.currency)} · Out ${_money(day.netPersonalExpense, report.currency)}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ]),
                      ))
                  .toList(growable: false),
            ),
          ),
        ],
      );

  Widget _categoryBreakdown(AnalyticsReport report) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Spending by Category',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          ...report.categoryTotals.map((category) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: _panelDecoration(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(category.categoryId,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    Text(
                      '${_money(category.total, report.currency)} (${category.percentageOfTotal.toStringAsFixed(1)}%)',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value:
                        (category.percentageOfTotal / 100).clamp(0, 1).toDouble(),
                    backgroundColor: const Color(0xFF334155),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF38BDF8)),
                  ),
                ]),
              )),
        ],
      );

  Widget _messageState({
    required IconData icon,
    required String title,
    required String message,
    required Widget action,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white38, size: 42),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 16),
            action,
          ]),
        ),
      );

  BoxDecoration _panelDecoration({Color color = const Color(0xFF1E293B)}) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      );

  String _money(double amount, String currency) =>
      NumberFormat.currency(symbol: currency == 'INR' ? '₹' : '$currency ', decimalDigits: 2)
          .format(amount);

  String _monthLabel(String month) =>
      DateFormat('MMMM yyyy').format(DateTime.parse('$month-01'));
}
