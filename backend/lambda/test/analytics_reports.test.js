const assert = require('node:assert/strict');
const test = require('node:test');

const {
  InvalidReportRequestError,
  buildFinancialReport,
  csvForReport,
  pdfForReport,
  reportSelection,
} = require('../analytics_reports');

const selection = { month: '2026-08', currency: 'INR' };
const persistedItems = [
  {
    data: {
      id: 'income-1',
      amount: 1000,
      currency: 'INR',
      type: 'CREDIT',
      merchantName: 'Employer',
      timestamp: '2026-08-01T09:00:00.000Z',
    },
  },
  {
    data: {
      id: 'debit-1',
      amount: 200,
      netPersonalExpense: 150,
      currency: 'INR',
      type: 'DEBIT',
      merchantName: 'Cafe, "Central"',
      categoryId: 'Dining',
      reconciliationStatus: 'CONFIRMED',
      timestamp: '2026-08-02T09:00:00.000Z',
    },
  },
  {
    data: {
      id: 'transfer-1',
      amount: 500,
      currency: 'INR',
      type: 'TRANSFER',
      merchantName: 'Own account',
      categoryId: 'Self Transfer',
      timestamp: '2026-08-02T12:00:00.000Z',
    },
  },
  {
    data: {
      id: 'other-month',
      amount: 99,
      currency: 'INR',
      type: 'DEBIT',
      timestamp: '2026-07-31T23:00:00.000Z',
    },
  },
];

test('builds cash flow, categories, trends, and insights from selected canonical transactions', () => {
  const report = buildFinancialReport(persistedItems, selection);

  assert.deepEqual(report.cashFlow, {
    income: 1000,
    spending: 200,
    netPersonalExpense: 150,
    netSavings: 850,
  });
  assert.equal(report.transactionCount, 3);
  assert.deepEqual(report.categoryTotals, [{
    categoryId: 'Dining',
    total: 150,
    percentageOfTotal: 100,
  }]);
  assert.deepEqual(report.spendingTrend, [
    { date: '2026-08-01', income: 1000, spending: 0, netPersonalExpense: 0 },
    { date: '2026-08-02', income: 0, spending: 200, netPersonalExpense: 150 },
  ]);
  assert.match(report.aiInsights[0], /85%/);
  assert.equal(report.insightSource, 'SERVER_DERIVED_FALLBACK');
});

test('generates downloadable CSV and valid PDF bytes containing persisted report data', () => {
  const csv = csvForReport(persistedItems, selection);
  const pdf = pdfForReport(buildFinancialReport(persistedItems, selection));

  assert.match(csv, /"Cafe, ""Central"""/);
  assert.match(csv, /"150"/);
  assert.equal(Buffer.isBuffer(pdf), true);
  assert.match(pdf.toString('latin1'), /^%PDF-1.4/);
  assert.match(pdf.toString('latin1'), /Net personal expense: INR 150.00/);
});

test('validates report selection before querying data', () => {
  assert.deepEqual(reportSelection({ month: '2026-08', currency: 'inr' }), selection);
  assert.throws(() => reportSelection({ month: 'August' }), InvalidReportRequestError);
  assert.throws(() => reportSelection({ currency: 'RUPEES' }), InvalidReportRequestError);
});
