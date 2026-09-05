import 'transaction_item.dart';

class ReviewPayeeIdentity {
  const ReviewPayeeIdentity._();

  static bool matches(TransactionItem source, TransactionItem candidate) {
    final sourceVpa = _extractVpa(source);
    final candidateVpa = _extractVpa(candidate);
    if (sourceVpa != null || candidateVpa != null) {
      return sourceVpa != null && sourceVpa == candidateVpa;
    }
    final sourceMerchant = _normalize(source.merchantName);
    final candidateMerchant = _normalize(candidate.merchantName);
    return sourceMerchant.isNotEmpty &&
        sourceMerchant == candidateMerchant &&
        !_genericLabels.contains(sourceMerchant);
  }

  static String? _extractVpa(TransactionItem transaction) {
    final text = '${transaction.referenceNumber} ${transaction.rawSnippet ?? ''}';
    final match = RegExp(
      r'(?:towards\s+(?:vpa\s+)?|\bvpa\s*:?\s*)([a-z0-9._-]+@[a-z0-9.-]+)',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(1)?.toLowerCase();
  }

  static String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static const _genericLabels = {
    'bank alert',
    'bank transfer',
    'email transaction',
    'transaction alert',
    'upi transaction',
  };
}
