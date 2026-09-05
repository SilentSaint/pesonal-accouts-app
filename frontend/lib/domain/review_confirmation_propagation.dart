import 'transaction_item.dart';

class ReviewConfirmationPropagation {
  const ReviewConfirmationPropagation._();

  static TransactionItem apply(
    TransactionItem confirmed,
    TransactionItem matchingReview,
  ) {
    return matchingReview.copyWith(
      merchantName: confirmed.merchantName,
      categoryId: confirmed.categoryId,
      subCategory: confirmed.subCategory,
      reconciliationStatus: confirmed.reconciliationStatus,
    );
  }
}
