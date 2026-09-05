import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/proactive_insight.dart';
import '../services/proactive_insights_service.dart';

class ProactiveInsightsScreen extends StatefulWidget {
  const ProactiveInsightsScreen({
    super.key,
    this.loadInsights,
    this.loadAllInsights,
    this.dismissInsight,
  });

  final Future<List<ProactiveInsight>> Function()? loadInsights;
  final Future<List<ProactiveInsight>> Function(bool includeDismissed)?
      loadAllInsights;
  final Future<void> Function(String id)? dismissInsight;

  @override
  State<ProactiveInsightsScreen> createState() =>
      _ProactiveInsightsScreenState();
}

class _ProactiveInsightsScreenState extends State<ProactiveInsightsScreen> {
  List<ProactiveInsight>? _insights;
  Object? _error;
  bool _loading = true;
  bool _includeDismissed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final insights = await (widget.loadAllInsights?.call(_includeDismissed) ??
          (!_includeDismissed && widget.loadInsights != null
              ? widget.loadInsights!.call()
              : ProactiveInsightsService()
                  .load(includeDismissed: _includeDismissed)));
      if (mounted) setState(() => _insights = insights);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dismiss(ProactiveInsight insight) async {
    try {
      await (widget.dismissInsight?.call(insight.id) ??
          ProactiveInsightsService().dismiss(insight.id));
      if (mounted) {
        setState(() {
          _insights =
              _insights?.where((item) => item.id != insight.id).toList();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to dismiss this insight. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending insights'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _includeDismissed = !_includeDismissed);
              _reload();
            },
            child: Text(
              _includeDismissed ? 'Active' : 'History',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 42),
          const SizedBox(height: 12),
          const Text('Insights are unavailable'),
          TextButton(onPressed: _reload, child: const Text('Retry')),
        ]),
      );
    }
    final insights = _insights!;
    if (insights.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.insights_outlined, size: 42),
            SizedBox(height: 12),
            Text('No current insights'),
            SizedBox(height: 6),
            Text('Not enough history yet', textAlign: TextAlign.center),
            Text(
              'No meaningful change was found, or insights need at least '
              'three comparable months.',
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: insights.length,
        itemBuilder: (context, index) => _card(insights[index]),
      ),
    );
  }

  Widget _card(ProactiveInsight insight) {
    final money = NumberFormat.currency(
      symbol: insight.currentAmount.currency == 'INR'
          ? '₹'
          : '${insight.currentAmount.currency} ',
      decimalDigits: 2,
    );
    final refreshed = DateTime.tryParse(insight.freshnessAsOf)?.toLocal();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(insight.title,
                    style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
              tooltip: 'Dismiss insight',
              onPressed: () => _dismiss(insight),
              icon: const Icon(Icons.close),
            ),
          ]),
          Text(insight.message),
          const SizedBox(height: 12),
          Text('${money.format(insight.currentAmount.amount)} compared with '
              '${money.format(insight.baselineAmount.amount)}'),
          Text(insight.baselineLabel),
          Text(
              'Derived insight · ${(insight.confidence * 100).round()}% confidence'),
          if (refreshed != null)
            Text(
                'Fresh as of ${DateFormat.yMMMd().add_jm().format(refreshed)}'),
          if (insight.matchingTransactions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
                'Matching transactions (${insight.matchingTransactions.length})'),
            ...insight.matchingTransactions
                .map((transaction) => Text('• ${transaction.merchantName}')),
          ],
        ]),
      ),
    );
  }
}
