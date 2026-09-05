import 'package:flutter/services.dart';
import 'offline_queue_service.dart';

class SmsReceiverService {
  static const MethodChannel _channel = MethodChannel('com.automaticexpense.tracker/sms');
  static final OfflineQueueService _queueService = OfflineQueueService();

  static Future<void> initializeSmsListener({
    required Function(String sender, String body, DateTime timestamp) onSmsReceived,
    bool isOnline = true,
  }) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSmsReceived') {
        final Map<dynamic, dynamic> args = call.arguments;
        final String sender = args['sender'] ?? '';
        final String body = args['body'] ?? '';
        final int timestampMillis = args['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
        final DateTime timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMillis);

        if (isOnline) {
          onSmsReceived(sender, body, timestamp);
        } else {
          _queueService.enqueueSmsEvent(sender, body, timestamp);
        }
      }
    });
  }

  static Future<bool> isReceiverAvailable() async {
    try {
      final bool? available = await _channel.invokeMethod<bool>('isSmsReceiverAvailable');
      return available ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isFinancialSender(String sender) async {
    try {
      final bool? isFinancial = await _channel.invokeMethod<bool>('checkFinancialSender', {'sender': sender});
      return isFinancial ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> readPast30DaysSms() async {
    try {
      final List<dynamic>? rawList = await _channel.invokeMethod<List<dynamic>>('readPast30DaysSms');
      if (rawList == null) return [];
      return rawList.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static String cleanBankName(String sender) {
    final upper = sender.toUpperCase();
    if (upper.contains('HDFC')) return 'HDFC Bank';
    if (upper.contains('SBI') || upper.contains('SBIN') || upper.contains('STATE BANK')) return 'State Bank of India';
    if (upper.contains('ICICI')) return 'ICICI Bank';
    if (upper.contains('AXIS')) return 'Axis Bank';
    if (upper.contains('KOTAK')) return 'Kotak Mahindra';
    if (upper.contains('IDFC')) return 'IDFC First';
    if (upper.contains('PAYTM')) return 'Paytm Bank';
    if (upper.contains('AMEX')) return 'American Express';
    if (upper.contains('INDUS')) return 'IndusInd Bank';
    if (upper.contains('RBL')) return 'RBL Bank';
    if (upper.contains('YES')) return 'Yes Bank';
    if (upper.contains('PNB') || upper.contains('PUNJAB')) return 'Punjab National Bank';
    if (upper.contains('BOB') || upper.contains('BARODA')) return 'Bank of Baroda';
    if (upper.contains('CANARA') || upper.contains('CANBNK')) return 'Canara Bank';
    if (upper.contains('UNION')) return 'Union Bank';
    if (upper.contains('FED')) return 'Federal Bank';
    if (upper.contains('AUFIN') || upper.contains('AUBANK')) return 'AU Small Finance';
    if (upper.contains('STAN') || upper.contains('SCB')) return 'Standard Chartered';
    if (upper.contains('CRED')) return 'CRED';
    if (upper.contains('PHONEPE')) return 'PhonePe';
    if (upper.contains('GPAY') || upper.contains('GOOGLEPAY')) return 'Google Pay';
    return sender.replaceAll(RegExp(r'^[A-Za-z0-9]{2}-'), '');
  }

  static String inferCategory(String merchant, String body) {
    final text = '$merchant $body'.toLowerCase();
    if (text.contains('swiggy') || text.contains('zomato') || text.contains('eats') ||
        text.contains('restaurant') || text.contains('cafe') || text.contains('starbucks') ||
        text.contains('mcdonald') || text.contains('burger') || text.contains('pizza') ||
        text.contains('subway') || text.contains('domino') || text.contains('kfc') ||
        text.contains('diner') || text.contains('bakery') || text.contains('chai') ||
        text.contains('biryani') || text.contains('barbeque') || text.contains('rebel') ||
        text.contains('eatfit') || text.contains('haldiram') || text.contains('food')) {
      return 'Food & Dining';
    }
    if (text.contains('blinkit') || text.contains('zepto') || text.contains('instamart') ||
        text.contains('bigbasket') || text.contains('supermarket') || text.contains('grocery') ||
        text.contains('dmart') || text.contains('spencer') || text.contains('reliance fresh') ||
        text.contains('jiomart') || text.contains('milkbasket') || text.contains('country delight') ||
        text.contains('vegetables') || text.contains('fruits') || text.contains('provision')) {
      return 'Groceries';
    }
    if (text.contains('amazon') || text.contains('flipkart') || text.contains('myntra') ||
        text.contains('ajio') || text.contains('nykaa') || text.contains('zara') ||
        text.contains('h&m') || text.contains('shopping') || text.contains('retail') ||
        text.contains('tata cliq') || text.contains('meesho') || text.contains('croma') ||
        text.contains('vijay sales') || text.contains('uniqlo') || text.contains('decathlon') ||
        text.contains('lenskart') || text.contains('mall')) {
      return 'Shopping';
    }
    if (text.contains('uber') || text.contains('ola') || text.contains('rapido') ||
        text.contains('petrol') || text.contains('fuel') || text.contains('hpcl') ||
        text.contains('bpcl') || text.contains('iocl') || text.contains('shell') ||
        text.contains('indian oil') || text.contains('bharat petroleum') || text.contains('nayara') ||
        text.contains('fastag') || text.contains('metro') || text.contains('irctc') ||
        text.contains('railway') || text.contains('indigo') || text.contains('air india') ||
        text.contains('makemytrip') || text.contains('cleartrip') || text.contains('flight') ||
        text.contains('toll') || text.contains('parking')) {
      return 'Transport & Fuel';
    }
    if (text.contains('bescom') || text.contains('tneb') || text.contains('msedcl') ||
        text.contains('electricity') || text.contains('water bill') || text.contains('gas bill') ||
        text.contains('airtel') || text.contains('jio') || text.contains('vi ') ||
        text.contains('vodafone') || text.contains('broadband') || text.contains('fibernet') ||
        text.contains('act ') || text.contains('tata play') || text.contains('dish tv') ||
        text.contains('dth') || text.contains('recharge') || text.contains('utility') ||
        text.contains('insurance') || text.contains('lic') || text.contains('premium')) {
      return 'Bills & Utilities';
    }
    if (text.contains('netflix') || text.contains('prime video') || text.contains('spotify') ||
        text.contains('bookmyshow') || text.contains('pvr') || text.contains('inox') ||
        text.contains('hotstar') || text.contains('youtube') || text.contains('sonyliv') ||
        text.contains('cinema') || text.contains('movie') || text.contains('theatre')) {
      return 'Entertainment';
    }
    if (text.contains('zerodha') || text.contains('groww') || text.contains('indmoney') ||
        text.contains('kuvera') || text.contains('upstox') || text.contains('angel one') ||
        text.contains('mutual fund') || text.contains('sip') || text.contains('coin') ||
        text.contains('investment') || text.contains('stock') || text.contains('shares')) {
      return 'Investments';
    }
    if (text.contains('salary') || text.contains('stipend') || text.contains('bonus') ||
        text.contains('payroll') || text.contains('reimbursement')) {
      return 'Income';
    }
    if (text.contains('recurring deposit') || text.contains(' rd ') || text.contains('fixed deposit') ||
        text.contains(' fd ') || text.contains('term deposit')) {
      return 'Investments';
    }
    if (text.contains('credit card') || text.contains('card bill') || text.contains('payment received towards your')) {
      return 'Bills & Utilities';
    }
    if (text.contains('apollo') || text.contains('pharmeasy') || text.contains('1mg') ||
        text.contains('netmeds') || text.contains('medplus') || text.contains('practo') ||
        text.contains('hospital') || text.contains('clinic') || text.contains('pharmacy') ||
        text.contains('diagnostic') || text.contains('medical')) {
      return 'Healthcare';
    }
    return 'General Expenses';
  }

  static String cleanMerchantName(String raw) {
    var name = raw.trim();
    if (name.contains('@')) {
      name = name.split('@')[0];
    }
    name = name.replaceAll(RegExp(r'^(payto|upi|vpa|info|to|at)\s*', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'[._-]+'), ' ').trim();
    if (name.isEmpty) return 'Merchant';
    return name.split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');
  }

  /// Extracts transaction details (amount, type, merchant, account last 4, category) from real SMS text
  static Map<String, dynamic>? parseSmsBody(String body, String sender, DateTime timestamp) {
    // Look for amount (Rs, INR, Rs., ₹, INR.)
    final amountRegex = RegExp(r'(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false);
    final amountMatch = amountRegex.firstMatch(body);
    if (amountMatch == null) return null;

    final rawAmt = amountMatch.group(1)?.replaceAll(',', '');
    final double? amount = double.tryParse(rawAmt ?? '');
    if (amount == null || amount <= 0) return null;

    // Detect Debit vs Credit
    final bool isCredit = RegExp(r'(?:credited|deposited|received|refund|cashback|inward)', caseSensitive: false).hasMatch(body);
    final String type = isCredit ? 'CREDIT' : 'DEBIT';

    // Extract Account/Card last 4 digits (matches ending XX1234, a/c *1234, card ...1234)
    final acctRegex = RegExp(r'(?:a\/c|acct|account|card|ending with|ending in|ending|no\.?|xx|\*+)\s*(?:no\.?)?\s*(?:[xX*]+)?(\d{4})', caseSensitive: false);
    final acctMatch = acctRegex.firstMatch(body);
    final String lastFour = acctMatch?.group(1) ?? '9999';

    // Extract Merchant / Payee
    final payeeRegex = RegExp(r'(?:to|at|vpa|info|merchant|towards)\s+([A-Za-z0-9\s&._@-]+?)(?:\.|\s+on|\s+ref|\s+avail|\s+bal|\s+upi|\s+avl|$)', caseSensitive: false);
    final payeeMatch = payeeRegex.firstMatch(body);
    String rawMerchant = payeeMatch?.group(1)?.trim() ?? '';
    String merchant = (rawMerchant.isNotEmpty && rawMerchant.length >= 2)
        ? cleanMerchantName(rawMerchant)
        : cleanBankName(sender);

    final bankName = cleanBankName(sender);
    final category = inferCategory(merchant, body);

    return {
      'amount': amount,
      'type': type,
      'merchant': merchant,
      'bankName': bankName,
      'lastFour': lastFour,
      'category': category,
      'sender': sender,
      'timestamp': timestamp,
    };
  }
}
