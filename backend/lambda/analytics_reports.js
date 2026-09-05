const REPORT_MONTH = /^\d{4}-(0[1-9]|1[0-2])$/;
const CURRENCY = /^[A-Z]{3}$/;

class InvalidReportRequestError extends Error {}

function reportSelection(query = {}, now = new Date()) {
  const month = query.month || now.toISOString().slice(0, 7);
  const currency = String(query.currency || 'INR').toUpperCase();
  if (typeof month !== 'string' || !REPORT_MONTH.test(month)) {
    throw new InvalidReportRequestError('month must use YYYY-MM format');
  }
  if (!CURRENCY.test(currency)) {
    throw new InvalidReportRequestError('currency must be a three-letter ISO code');
  }
  return { month, currency };
}

function canonicalTransactions(items, selection) {
  return items
    .map((item) => item?.data || item)
    .filter((transaction) => transaction && typeof transaction === 'object')
    .map((transaction) => ({ ...transaction, date: transactionDate(transaction.timestamp) }))
    .filter((transaction) => transaction.date)
    .filter((transaction) => transaction.date.toISOString().slice(0, 7) === selection.month)
    .filter((transaction) => String(transaction.currency || 'INR').toUpperCase() === selection.currency)
    .sort((left, right) => left.date - right.date);
}

function buildFinancialReport(items, selection) {
  const transactions = canonicalTransactions(items, selection);
  let totalIncome = 0;
  let totalDebits = 0;
  let netPersonalExpense = 0;
  const categories = new Map();
  const merchants = new Map();
  const days = new Map();

  for (const transaction of transactions) {
    const amount = positiveAmount(transaction.amount);
    const day = transaction.date.toISOString().slice(0, 10);
    const totals = days.get(day) || { date: day, income: 0, spending: 0, netPersonalExpense: 0 };
    if (transaction.type === 'CREDIT') {
      totalIncome += amount;
      totals.income += amount;
    } else if (transaction.type === 'DEBIT') {
      const personalExpense = netPersonalAmount(transaction.netPersonalExpense, amount);
      totalDebits += amount;
      netPersonalExpense += personalExpense;
      totals.spending += amount;
      totals.netPersonalExpense += personalExpense;
      const category = textOr(transaction.categoryId, 'Uncategorized');
      const merchant = textOr(transaction.merchantName, 'Unknown merchant');
      categories.set(category, (categories.get(category) || 0) + personalExpense);
      merchants.set(merchant, (merchants.get(merchant) || 0) + personalExpense);
    }
    days.set(day, totals);
  }

  const categoryTotals = [...categories.entries()]
    .map(([categoryId, total]) => ({
      categoryId,
      total: round(total),
      percentageOfTotal: netPersonalExpense === 0 ? 0 : round((total / netPersonalExpense) * 100),
    }))
    .sort((left, right) => right.total - left.total || left.categoryId.localeCompare(right.categoryId));
  const topMerchant = largestEntry(merchants);
  const cashFlow = {
    income: round(totalIncome),
    spending: round(totalDebits),
    netPersonalExpense: round(netPersonalExpense),
    netSavings: round(totalIncome - netPersonalExpense),
  };
  const report = {
    month: selection.month,
    currency: selection.currency,
    transactionCount: transactions.length,
    cashFlow,
    categoryTotals,
    spendingTrend: [...days.values()].map(roundTrend),
    aiInsights: [],
    insightSource: 'SERVER_DERIVED_FALLBACK',
  };
  report.aiInsights = insightsFor(report, topMerchant);
  return report;
}

function csvForReport(items, selection) {
  const transactions = canonicalTransactions(items, selection);
  const columns = [
    'Id', 'Date', 'Amount', 'Currency', 'Type', 'Merchant', 'Category',
    'Net Personal Expense', 'Reconciliation Status',
  ];
  const rows = transactions.map((transaction) => [
    transaction.id,
    transaction.date.toISOString(),
    positiveAmount(transaction.amount),
    selection.currency,
    textOr(transaction.type, ''),
    textOr(transaction.merchantName, ''),
    textOr(transaction.categoryId, 'Uncategorized'),
    transaction.type === 'DEBIT'
      ? netPersonalAmount(transaction.netPersonalExpense, positiveAmount(transaction.amount))
      : '',
    textOr(transaction.reconciliationStatus, ''),
  ]);
  return [columns, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
}

function pdfForReport(report) {
  const lines = [
    `Financial report: ${report.month}`,
    `Currency: ${report.currency}`,
    '',
    'Cash flow',
    `Income: ${money(report.cashFlow.income, report.currency)}`,
    `Debits: ${money(report.cashFlow.spending, report.currency)}`,
    `Net personal expense: ${money(report.cashFlow.netPersonalExpense, report.currency)}`,
    `Net savings: ${money(report.cashFlow.netSavings, report.currency)}`,
    `Transactions: ${report.transactionCount}`,
    '',
    'Category totals',
    ...(report.categoryTotals.length
      ? report.categoryTotals.map((category) =>
        `${category.categoryId}: ${money(category.total, report.currency)} (${category.percentageOfTotal}%)`)
      : ['No debit transactions in this period.']),
    '',
    'Server-derived insights',
    ...(report.aiInsights.length ? report.aiInsights.map((insight) => `- ${insight}`) : ['No insights available.']),
  ];
  return renderPdf(lines);
}

function insightsFor(report, topMerchant) {
  if (report.transactionCount === 0) return [];
  const insights = [];
  if (report.cashFlow.income > 0) {
    insights.push(`You saved ${round((report.cashFlow.netSavings / report.cashFlow.income) * 100)}% of income this month.`);
  }
  if (report.categoryTotals[0]) {
    const category = report.categoryTotals[0];
    insights.push(`${category.categoryId} is the largest category at ${category.percentageOfTotal}% of personal spending.`);
  }
  if (topMerchant) {
    insights.push(`${topMerchant.key} is the highest-spend merchant at ${money(topMerchant.value, report.currency)}.`);
  }
  if (report.cashFlow.income > 0 && report.cashFlow.netPersonalExpense > report.cashFlow.income) {
    insights.push('Personal spending exceeded recorded income for this period.');
  }
  return insights;
}

function transactionDate(value) {
  const date = typeof value === 'number' || (typeof value === 'string' && /^\d+$/.test(value))
    ? new Date(Number(value))
    : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function positiveAmount(value) {
  const amount = Number(value);
  return Number.isFinite(amount) && amount > 0 ? amount : 0;
}

function netPersonalAmount(value, fallback) {
  const amount = Number(value);
  return Number.isFinite(amount) && amount >= 0 ? amount : fallback;
}

function textOr(value, fallback) {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

function largestEntry(entries) {
  let largest;
  for (const [key, value] of entries) {
    if (!largest || value > largest.value) largest = { key, value };
  }
  return largest;
}

function round(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function roundTrend(trend) {
  return {
    date: trend.date,
    income: round(trend.income),
    spending: round(trend.spending),
    netPersonalExpense: round(trend.netPersonalExpense),
  };
}

function csvCell(value) {
  let text = String(value ?? '');
  if (/^[=+\-@]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

function money(amount, currency) {
  return `${currency} ${Number(amount).toFixed(2)}`;
}

function renderPdf(lines) {
  const pageLines = [];
  for (let index = 0; index < lines.length; index += 42) pageLines.push(lines.slice(index, index + 42));
  if (pageLines.length === 0) pageLines.push(['Financial report']);

  const fontObject = 3 + pageLines.length * 2;
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    `<< /Type /Pages /Kids [ ${pageLines.map((_, index) => `${3 + index * 2} 0 R`).join(' ')} ] /Count ${pageLines.length} >>`,
  ];
  pageLines.forEach((page, index) => {
    const pageObject = 3 + index * 2;
    const contentObject = pageObject + 1;
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 ${fontObject} 0 R >> >> /Contents ${contentObject} 0 R >>`);
    const content = `BT\n/F1 11 Tf\n50 750 Td\n14 TL\n${page.map((line) => `(${pdfEscape(line)}) Tj\nT*`).join('\n')}\nET`;
    objects.push(`<< /Length ${Buffer.byteLength(content, 'ascii')} >>\nstream\n${content}\nendstream`);
  });
  objects.push('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

  let document = '%PDF-1.4\n%\xE2\xE3\xCF\xD3\n';
  const offsets = [0];
  objects.forEach((object, index) => {
    offsets.push(Buffer.byteLength(document, 'latin1'));
    document += `${index + 1} 0 obj\n${object}\nendobj\n`;
  });
  const xrefOffset = Buffer.byteLength(document, 'latin1');
  document += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  offsets.slice(1).forEach((offset) => { document += `${String(offset).padStart(10, '0')} 00000 n \n`; });
  document += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`;
  return Buffer.from(document, 'latin1');
}

function pdfEscape(value) {
  return String(value)
    .replace(/[^\x20-\x7E]/g, '?')
    .replaceAll('\\', '\\\\')
    .replaceAll('(', '\\(')
    .replaceAll(')', '\\)');
}

module.exports = {
  InvalidReportRequestError,
  buildFinancialReport,
  csvForReport,
  pdfForReport,
  reportSelection,
};
