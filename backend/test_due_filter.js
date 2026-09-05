const assert = require('assert');

// Simulate the exact due detection logic added to both parseEmailsWithGemini and fallback parser
function isDueOrBillNotice(fullText) {
  return /\b(?:due\s+date|payment\s+due(?:\s+date)?|amount\s+due|total\s+(?:amount\s+)?due|minimum\s+(?:amount\s+)?due|is\s+due(?:\s+on)?|due\s+on\s+[0-9a-z]|due\s+by\s+[0-9a-z]|due\s+today|overdue|payable\s+by|last\s+date\s+(?:to\s+pay|of\s+payment)|pay\s+before\s+due)\b/i.test(fullText) ||
    /\b(?:due\s*:\s*|due\s+on\s+[0-9a-z]|due\s+date\s*:|total\s+due|min\s+due)\b/i.test(fullText) ||
    /(?:bill\s+(?:is\s+)?due|avoid\s+late\s+fees|pay\s+now\s+on\s+CRED)/i.test(fullText);
}

const testCases = [
  {
    name: 'CRED Airtel Postpaid bill due today',
    text: 'Airtel Postpaid bill due CRED Rakshith, your mobile postpaid bill is due today. biller name Airtel Postpaid total amount due ₹1950.54 avoid late fees',
    expectedDiscard: true
  },
  {
    name: 'Credit card payment due on 15-Aug',
    text: 'Credit card payment due Your credit card payment is due on 15-Aug-26. Total Amount Due: ₹15,400. Minimum Amount Due: ₹500',
    expectedDiscard: true
  },
  {
    name: 'Recurring Deposit instalment is due on 06-AUG',
    text: 'Recurring Deposit instalment Your monthly instalment of INR 2,000.00 for Recurring Deposit RD No.XXXXX7044 is due on 06-AUG-26',
    expectedDiscard: true
  },
  {
    name: 'BESCOM Electricity bill with Due Date',
    text: 'BESCOM Electricity Bill Your BESCOM Electricity bill of Rs. 896.00 has been generated. Due Date: 12-Aug-2026',
    expectedDiscard: true
  },
  {
    name: 'Credit card statement with Payment Due Date',
    text: 'Alert: Bill generated for card ending 9207. Payment Due Date: 20-Aug-2026. Total Due: Rs. 2,350.00',
    expectedDiscard: true
  },
  {
    name: 'Real bank debit alert (HDFC UPI payment to Mohammed Ansar)',
    text: 'Debit Alert Dear Customer, Greetings from HDFC Bank! Rs.360.00 is debited from your account ending 1277 towards VPA gpay-12190485436@okbizaxis (Mr MOHAMMED ANSAR) on 27-08-26. UPI transaction reference no.: 123456',
    expectedDiscard: false
  },
  {
    name: 'Real salary credit',
    text: 'Salary Credit Amount received: INR 1,05,542.00 Account: XX1277 Date: 30-JUL-2026 Reference Details: NEFT Cr-CITI0000002-SIGNIFY INNO I L SALARY TRANSIT AC',
    expectedDiscard: false
  },
  {
    name: 'Real credit card spend at Appayanna Petroleum',
    text: 'Card Alert INR336.11 spent at APPAYANNA PETROLEUM on RBL Bank credit card (9635) on 01-AUG-26',
    expectedDiscard: false
  }
];

console.log('Running test_due_filter.js...');
let passed = 0;
for (const tc of testCases) {
  const isDiscarded = isDueOrBillNotice(tc.text);
  assert.strictEqual(isDiscarded, tc.expectedDiscard, `Test failed for: ${tc.name}`);
  console.log(`✓ ${tc.name}: ${isDiscarded ? 'DISCARDED (Non-transaction)' : 'ACCEPTED (Real transaction)'}`);
  passed++;
}

console.log(`\nAll ${passed} tests passed successfully!`);
