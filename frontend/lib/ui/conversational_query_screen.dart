import 'package:flutter/material.dart';

import '../domain/conversational_finance_query.dart';
import '../services/conversational_query_service.dart';

class ConversationalQueryScreen extends StatefulWidget {
  const ConversationalQueryScreen({
    super.key,
    this.askQuestion,
    this.onEvidenceRequested,
  });

  final Future<ConversationalFinanceQueryResponse> Function(String question)?
      askQuestion;
  final ValueChanged<ConversationDrillDown>? onEvidenceRequested;

  @override
  State<ConversationalQueryScreen> createState() =>
      _ConversationalQueryScreenState();
}

class _ConversationalQueryScreenState extends State<ConversationalQueryScreen> {
  final _questionController = TextEditingController();
  ConversationalFinanceQueryResponse? _response;
  Object? _error;
  bool _isLoading = false;
  String? _lastQuestion;

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _ask([String? retryQuestion]) async {
    final question = (retryQuestion ?? _questionController.text).trim();
    if (question.isEmpty || _isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _lastQuestion = question;
    });
    try {
      final response = await (widget.askQuestion?.call(question) ??
          ConversationalQueryService().ask(question));
      if (mounted) setState(() => _response = response);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask about spending')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ask about your recorded spending. Answers use canonical ledger evidence.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _questionController,
              minLines: 1,
              maxLines: 3,
              enabled: !_isLoading,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _ask(),
              decoration: const InputDecoration(
                labelText: 'Spending question',
                hintText: 'How much did I spend this month?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Ask spending question',
              button: true,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _ask,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Ask'),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 40),
          const SizedBox(height: 8),
          const Text('Your question could not be answered.'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _lastQuestion == null ? null : () => _ask(_lastQuestion),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ]),
      );
    }
    final response = _response;
    if (response == null) {
      return const Center(
        child: Text(
            'Try a spending total, merchant, category, purchase, or comparison question.'),
      );
    }
    if (response.status == ConversationalFinanceQueryStatus.clarification) {
      return _resultCard(
        icon: Icons.help_outline,
        title: 'More detail needed',
        child: Text(response.clarification!),
      );
    }
    return _resultCard(
      icon: Icons.insights_outlined,
      title: 'Evidence-backed answer',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(response.observation!),
        const SizedBox(height: 12),
        Text('${response.sourceCount} canonical transactions',
            style: Theme.of(context).textTheme.bodySmall),
        if (response.hasEvidence) ...[
          const SizedBox(height: 8),
          Semantics(
            label: 'View supporting transactions',
            button: true,
            child: TextButton.icon(
              onPressed: response.drillDown == null
                  ? null
                  : () => widget.onEvidenceRequested?.call(response.drillDown!),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View supporting transactions'),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _resultCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}
