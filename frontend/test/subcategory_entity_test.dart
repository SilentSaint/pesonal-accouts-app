import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:automatic_expense_tracker/domain/transaction_item.dart';
import 'package:automatic_expense_tracker/domain/merchant_entity.dart';
import 'package:automatic_expense_tracker/services/entity_service.dart';
import 'package:automatic_expense_tracker/services/auth_service.dart';
import 'package:automatic_expense_tracker/services/auto_scan_scheduler_service.dart';
import 'package:automatic_expense_tracker/ui/dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('SubCategory and Entity Tests', () {
    test('TransactionItem holds and serializes subCategory', () {
      final txn = TransactionItem(
        id: 'txn-101',
        amount: 25.0,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Tea Stall',
        accountId: 'acc-1',
        categoryId: 'Food & Dining',
        subCategory: 'Tea & Snacks',
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime(2026, 8, 27, 14, 0),
      );

      final json = txn.toJson();
      expect(json['categoryId'], 'Food & Dining');
      expect(json['subCategory'], 'Tea & Snacks');

      final deserialized = TransactionItem.fromJson(json);
      expect(deserialized.categoryId, 'Food & Dining');
      expect(deserialized.subCategory, 'Tea & Snacks');
    });

    test('MerchantEntity holds and serializes defaultSubCategory', () {
      final entity = MerchantEntity(
        id: 'ent-101',
        name: 'Tea Stall',
        defaultCategory: 'Food & Dining',
        defaultSubCategory: 'Tea & Snacks',
        vendorAliases: ['Saira Banu'],
        upiAliases: ['paytm.s1yxlpq@pty'],
        createdAt: DateTime.now(),
        lastUsedAt: DateTime.now(),
      );

      final json = entity.toJson();
      expect(json['name'], 'Tea Stall');
      expect(json['defaultSubCategory'], 'Tea & Snacks');
      expect(json['vendorAliases'], contains('Saira Banu'));

      final deserialized = MerchantEntity.fromJson(json);
      expect(deserialized.name, 'Tea Stall');
      expect(deserialized.defaultSubCategory, 'Tea & Snacks');
      expect(deserialized.vendorAliases, contains('Saira Banu'));
    });

    test('EntityService maps and matches custom alias with subCategory', () async {
      final auth = AuthService.forTesting(googleOAuthClient: _TestOAuthClient());
      await auth.ensureInitialized();
      final entityService = EntityService.forTesting(authService: auth);

      // Map "Saira Banu" & "paytm.s1yxlpq@pty" to custom alias "Tea Stall" with subCategory "Tea & Snacks"
      final entity = await entityService.mapTransactionToEntity(
        entityName: 'Tea Stall',
        rawVendorName: 'Saira Banu',
        upiId: 'paytm.s1yxlpq@pty',
        accountMask: '•••• 1277',
        category: 'Food & Dining',
        subCategory: 'Tea & Snacks',
      );

      expect(entity.name, 'Tea Stall');
      expect(entity.defaultCategory, 'Food & Dining');
      expect(entity.defaultSubCategory, 'Tea & Snacks');
      expect(entity.vendorAliases, contains('Saira Banu'));
      expect(entity.upiAliases, contains('paytm.s1yxlpq@pty'));

      // Simulate a future transaction with only UPI handle
      final matchedByUpi = entityService.matchEntity(upiId: 'paytm.s1yxlpq@pty');
      expect(matchedByUpi, isNotNull);
      expect(matchedByUpi!.name, 'Tea Stall');
      expect(matchedByUpi.defaultSubCategory, 'Tea & Snacks');

      // Simulate a future transaction with only Vendor name
      final matchedByVendor = entityService.matchEntity(rawName: 'Saira Banu');
      expect(matchedByVendor, isNotNull);
      expect(matchedByVendor!.name, 'Tea Stall');
      expect(matchedByVendor.defaultSubCategory, 'Tea & Snacks');
    });

    test('Maps multiple UPI QR codes and vendor aliases to the same shop (Chicken shop)', () async {
      final auth = AuthService.forTesting(googleOAuthClient: _TestOAuthClient());
      await auth.ensureInitialized();
      final entityService = EntityService.forTesting(authService: auth);

      // First QR code / transaction: aliased to "Chicken shop"
      await entityService.mapTransactionToEntity(
        entityName: 'Chicken shop',
        rawVendorName: 'CHICKEN CENTER',
        upiId: 'chickencenter@paytm',
        category: 'Groceries',
        subCategory: 'Meat & Seafood',
      );

      // Second QR code / transaction for the same shopkeeper: "Mr MOHAMMED ANSAR" with GPay UPI
      final updatedEntity = await entityService.mapTransactionToEntity(
        entityName: 'Chicken shop',
        rawVendorName: 'Mr MOHAMMED ANSAR',
        upiId: 'gpay-12190485436@okbizaxis',
        category: 'Groceries',
        subCategory: 'Meat & Seafood',
      );

      expect(updatedEntity.name, 'Chicken shop');
      expect(updatedEntity.upiAliases, contains('chickencenter@paytm'));
      expect(updatedEntity.upiAliases, contains('gpay-12190485436@okbizaxis'));
      expect(updatedEntity.vendorAliases, contains('CHICKEN CENTER'));
      expect(updatedEntity.vendorAliases, contains('Mr MOHAMMED ANSAR'));

      // Assert future transactions from EITHER UPI QR code match "Chicken shop"
      final matchQr1 = entityService.matchEntity(upiId: 'chickencenter@paytm');
      expect(matchQr1?.name, 'Chicken shop');
      expect(matchQr1?.defaultCategory, 'Groceries');
      expect(matchQr1?.defaultSubCategory, 'Meat & Seafood');

      final matchQr2 = entityService.matchEntity(upiId: 'gpay-12190485436@okbizaxis');
      expect(matchQr2?.name, 'Chicken shop');
      expect(matchQr2?.defaultCategory, 'Groceries');
      expect(matchQr2?.defaultSubCategory, 'Meat & Seafood');

      // Assert future transactions with vendor name also match
      final matchVendor = entityService.matchEntity(rawName: 'Mr MOHAMMED ANSAR');
      expect(matchVendor?.name, 'Chicken shop');
    });

    testWidgets('Clicking recent transaction tile opens transaction details dialog', (WidgetTester tester) async {
      final txn = TransactionItem(
        id: 'txn-details-1',
        amount: 410.0,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Chicken shop',
        accountId: 'acc-1',
        accountMask: '•••• 8173',
        categoryId: 'Groceries',
        subCategory: 'Meat & Seafood',
        referenceNumber: 'gpay-12190485436@okbizaxis',
        rawSnippet: 'Rs.410.00 debited from account ending 8173 to Chicken shop',
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime(2026, 8, 3, 19, 53),
      );

      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        AutoScanSchedulerService().stop();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(initialPendingTransactions: const []),
          ),
        ),
      );
      await tester.pump();

      // Find the dashboard state and add our test transaction
      final state = tester.state(find.byType(DashboardScreen)) as dynamic;
      state.setState(() {
        state.recentTransactions.add(txn);
      });
      await tester.pumpAndSettle();

      // Ensure visible and tap on the Chicken shop transaction tile
      expect(find.text('Chicken shop'), findsOneWidget);
      await tester.ensureVisible(find.text('Chicken shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chicken shop'));
      await tester.pumpAndSettle();

      // Verify the Transaction Details modal opened
      expect(find.text('Transaction Amount'), findsOneWidget);
      expect(find.text('-₹410.00'), findsNWidgets(2));
      expect(find.text('DEBIT / OUTFLOW'), findsOneWidget);
      expect(find.text('Groceries › Meat & Seafood'), findsWidgets);
      expect(find.text('Edit Shop / Category'), findsOneWidget);
      expect(find.text('Split Expense'), findsOneWidget);
      expect(find.text('Rs.410.00 debited from account ending 8173 to Chicken shop'), findsOneWidget);

      AutoScanSchedulerService().stop();
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _TestOAuthClient implements GoogleOAuthClient {
  final _TestOAuthAccount _account = _TestOAuthAccount();

  @override
  GoogleOAuthAccount? get currentUser => _account;

  @override
  Stream<GoogleOAuthAccount?> get onCurrentUserChanged => const Stream.empty();

  @override
  Future<GoogleOAuthAccount?> signIn() async => _account;

  @override
  Future<GoogleOAuthAccount?> signInSilently() async => _account;

  @override
  Future<bool> canAccessScopes(List<String> scopes) async => false;

  @override
  Future<bool> requestScopes(List<String> scopes) async => false;

  @override
  Future<void> signOut() async {}
}

class _TestOAuthAccount implements GoogleOAuthAccount {
  @override
  String get email => 'entity-test@example.test';

  @override
  String get displayName => 'Entity Test';

  @override
  String? get photoUrl => null;

  @override
  Future<GoogleOAuthCredentials> get authentication async =>
      const GoogleOAuthCredentials(idToken: 'entity-test-id-token');
}
