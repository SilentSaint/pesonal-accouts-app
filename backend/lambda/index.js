const { BatchWriteItemCommand, DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const {
  DynamoDBDocumentClient,
  PutCommand,
  QueryCommand,
} = require('@aws-sdk/lib-dynamodb');
const {
  SecretsManagerClient,
  GetSecretValueCommand,
} = require('@aws-sdk/client-secrets-manager');
const https = require('https');
const { parseGeminiApiKey } = require('./runtime_config');
const { resolveGatewayAuthenticatedUserPk } = require('./auth_identity');
const { buildGmailScanRequest } = require('./gmail_scan_query');
const {
  InvalidReportRequestError,
  buildFinancialReport,
  csvForReport,
  pdfForReport,
  reportSelection,
} = require('./analytics_reports');
const {
  decodeCursor,
  deleteUserPartition,
  encodeCursor,
  listTransactions,
  parseTransactionLimit,
  transactionSortKey,
} = require('./dynamodb_pagination');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'ap-south-2' });
const ddbDocClient = DynamoDBDocumentClient.from(client);
const secretsManagerClient = new SecretsManagerClient({
  region: process.env.AWS_REGION || 'ap-south-2',
});
const TABLE_NAME = process.env.TABLE_NAME || 'ExpenseTrackerData';
const GEMINI_SECRET_ARN = process.env.GEMINI_SECRET_ARN;
let geminiApiKeyPromise;

const headers = {
  'Content-Type': 'application/json',
};

function logBackendEvent(level, event, fields = {}) {
  const payload = {
    event,
    service: 'api-handler',
    ...fields,
  };
  const writer = typeof console[level] === 'function' ? console[level] : console.log;
  writer(`[BACKEND] ${JSON.stringify(payload)}`);
}

function formatResponse(statusCode, body) {
  return { statusCode, headers, body: JSON.stringify(body) };
}

function binaryResponse(statusCode, body, contentType, filename) {
  return {
    statusCode,
    headers: {
      'Content-Type': contentType,
      'Content-Disposition': `attachment; filename="${filename}"`,
    },
    isBase64Encoded: true,
    body: Buffer.from(body).toString('base64'),
  };
}

async function publishSyncEvent(userPk, type, entity) {
  try {
    await require('./websocket_sync').publishCanonicalSyncEvent({
      ddb: ddbDocClient,
      tableName: TABLE_NAME,
      userPk,
      event: {
        type,
        entityId: entity.id,
        payload: entity,
      },
    });
    logBackendEvent('info', 'sync_publication', { outcome: 'completed', type });
  } catch (error) {
    logBackendEvent('warn', 'sync_publication', {
      outcome: 'failed',
      type,
      exception: error?.name || 'Error',
    });
  }
}

async function loadCanonicalTransactions(userPk) {
  const items = [];
  let ExclusiveStartKey;
  const seenKeys = new Set();
  do {
    const result = await ddbDocClient.send(new QueryCommand({
      TableName: TABLE_NAME,
      KeyConditionExpression: 'PK = :pk AND begins_with(SK, :skPrefix)',
      ExpressionAttributeValues: { ':pk': userPk, ':skPrefix': 'TXN#' },
      ...(ExclusiveStartKey ? { ExclusiveStartKey } : {}),
    }));
    items.push(...(result.Items || []));
    ExclusiveStartKey = result.LastEvaluatedKey;
    if (ExclusiveStartKey) {
      const serialized = JSON.stringify(ExclusiveStartKey);
      if (seenKeys.has(serialized)) {
        throw new Error('DynamoDB returned a repeated transaction cursor');
      }
      seenKeys.add(serialized);
    }
  } while (ExclusiveStartKey);
  return items;
}

function extractAccountMask(text) {
  if (!text) return '';
  const match = text.match(/(?:ending\s+(?:in\s+|with\s+)?|account\s*(?:no\.?|number|ending)?|a\/c\s*(?:no\.?|number|ending)?|credit\s+card|card|acct)\s*[:\s-]*\(?([xX*.]*\d{2,6})\)?/i) ||
                text.match(/\b(?:XX|xx|\*\*|\.\.\.|••••)\s*(\d{2,4})\b/) ||
                text.match(/\bcard\s*\((\d{4})\)/i) ||
                text.match(/\baccount\s*[:\s]*[xX*]*(\d{4})\b/i);
  if (match) {
    const raw = match[1] || match[0];
    const digits = raw.replace(/[^0-9]/g, '');
    if (digits.length >= 2) {
      return `•••• ${digits.slice(-4)}`;
    }
  }
  return '';
}

function hasBankOrCardIdentifier(text) {
  if (!text) return false;
  return /(?:ending\s+(?:in\s+|with\s+)?|account\s*(?:no\.?|number|ending)?|a\/c\s*(?:no\.?|number|ending)?|credit\s+card|card|acct)\s*[:\s-]*\(?[xX*.]*\d{2,6}\)?/i.test(text) ||
         /\b(?:XX|xx|\*\*|••••)\s*\d{2,4}\b/.test(text) ||
         /\bcard\s*\(\d{4}\)/i.test(text);
}

async function getGeminiApiKey({ correlationId = 'unknown' } = {}) {
  if (!GEMINI_SECRET_ARN) {
    console.error('[GMAIL_SCAN] Gemini configuration missing', { correlationId });
    return null;
  }

  geminiApiKeyPromise ??= secretsManagerClient
      .send(new GetSecretValueCommand({ SecretId: GEMINI_SECRET_ARN }))
      .then((result) => parseGeminiApiKey(result.SecretString))
      .catch((error) => {
        console.error('[GMAIL_SCAN] Gemini secret retrieval failed', {
          correlationId,
          errorName: error.name,
        });
        return null;
      });
  return geminiApiKeyPromise;
}

/** Calls Gemini Flash to intelligently classify and extract structured transaction evidence. */
async function parseEmailsWithGemini(rawEmails, { correlationId = 'unknown' } = {}) {
  if (rawEmails.length === 0) {
    console.log('[GMAIL_SCAN] AI skipped: no email content', { correlationId });
    return { items: null, fallbackReason: 'no_email_content' };
  }
  const geminiApiKey = await getGeminiApiKey({ correlationId });
  if (!geminiApiKey) {
    console.warn('[GMAIL_SCAN] AI fallback: Gemini API key unavailable', {
      correlationId,
    });
    return { items: null, fallbackReason: 'gemini_api_key_unavailable' };
  }

  const prompt = `You are a financial transaction and account balance extractor for Indian banking emails.
Your task: Analyze each email and determine if it represents:
1. A COMPLETED MONETARY TRANSACTION (money was debited, credited, transferred, or spent on a card).
2. OR an ACCOUNT BALANCE NOTIFICATION (e.g. "Available balance in your account ending XX1277 is Rs. INR 50,868.64 as on 03-AUG-26").
If an email is neither of these (e.g. general notice, promotional offer, bill due reminder, statement notice, or merchant receipt), mark isFinancialTransaction: false, isBalanceUpdate: false.

CRITICAL RULES:
1. COMPLETED MONETARY TRANSACTIONS (isFinancialTransaction: true, isBalanceUpdate: false):
   - Set isFinancialTransaction: true ONLY if an actual past monetary movement occurred (debited, credited, spent on card, UPI payment, NEFT, IMPS, RTGS, transfer).
   - The email must reference an account or card.
   - For credit card spend: accountType: "CREDIT_CARD", accountMask: "•••• <last4>", type: "DEBIT".
   - For self transfer / between own accounts: type: "TRANSFER", category: "Self Transfer", subCategory: "Account to Account Transfer".
   - For salary / credits: type: "CREDIT", category: "Income".

2. ACCOUNT BALANCE NOTIFICATIONS (isFinancialTransaction: false, isBalanceUpdate: true):
   - If an email states an available account balance without money moving (e.g. "Available balance in your account ending XX1277 is Rs. INR 50,868.64 as on 03-AUG-26"):
     Set isFinancialTransaction: false, isBalanceUpdate: true, balance: numeric, accountMask: "•••• <last4>", transactionDate: "YYYY-MM-DD".

3. NOT TRANSACTIONS (isFinancialTransaction: false, isBalanceUpdate: false, amount: 0):
   - EMAILS WITH DUE DATES OR MENTION OF "DUE" (bill reminders, upcoming dues, credit card statements):
     Any email mentioning "due date", "payment due date", "amount due", "is due", "minimum amount due", "due on", "overdue", "payable by" is an upcoming notice/reminder or statement, NOT a completed transaction. Set isFinancialTransaction: false, isBalanceUpdate: false, amount: 0.
   - MERCHANT PAYMENT RECEIPTS (Airtel, Swiggy, BillPay confirmation receipts without a bank debit alert): Set isFinancialTransaction: false.

Return ONLY valid JSON matching this schema:
{
  "items": [
    {
      "id": "messageId",
      "isFinancialTransaction": boolean,
      "isBalanceUpdate": boolean,
      "balance": number,
      "merchant": string,
      "amount": number,
      "type": "DEBIT" | "CREDIT" | "TRANSFER",
      "category": string,
      "subCategory": string,
      "accountMask": string,
      "accountType": "SAVINGS" | "CREDIT_CARD" | "LOAN",
      "upiId": string,
      "transactionDate": string
    }
  ]
}

Emails to analyze:
${JSON.stringify(rawEmails.map((e, idx) => ({ id: e.messageId, index: idx, subject: e.subject, from: e.from, snippet: (e.snippet || '').slice(0, 450) })))}`;

  try {
    const requestBody = JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: "application/json"
      }
    });

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=${encodeURIComponent(geminiApiKey)}`;
    const resp = await httpsPostJson(url, requestBody, { 'Content-Type': 'application/json' }, 12000);

    if (resp.statusCode === 200 && resp.body?.candidates?.[0]?.content?.parts?.[0]?.text) {
      const text = resp.body.candidates[0].content.parts[0].text;
      const clean = text.replace(/^```json\s*|\s*```$/g, '').trim();
      const parsed = JSON.parse(clean);
      if (Array.isArray(parsed.items) && parsed.items.length > 0) {
        console.log('[GMAIL_SCAN] AI extraction succeeded', {
          correlationId,
          classifiedEmailCount: parsed.items.length,
        });
        return { items: parsed.items, fallbackReason: null };
      }
      console.warn('[GMAIL_SCAN] AI fallback: empty classification result', {
        correlationId,
      });
      return { items: null, fallbackReason: 'gemini_empty_classification' };
    } else {
      console.warn('[GMAIL_SCAN] AI fallback: Gemini response unusable', {
        correlationId,
        statusCode: resp.statusCode,
        hasCandidates: Boolean(resp.body?.candidates),
      });
      return { items: null, fallbackReason: 'gemini_response_unusable' };
    }
  } catch (err) {
    console.warn('[GMAIL_SCAN] AI fallback: Gemini response parse failed', {
      correlationId,
      errorName: err.name,
    });
    return { items: null, fallbackReason: 'gemini_response_parse_failed' };
  }
}

/** Call Gmail API to scan for bank alert / statement emails. */
async function scanGmailInbox(accessToken, customQuery, options = {}, { correlationId = 'unknown' } = {}) {
  const { query: finalQuery, maxResults: queryMax } = buildGmailScanRequest(
    customQuery,
    options,
  );
  const listUrl = `https://gmail.googleapis.com/gmail/v1/users/me/messages?q=${encodeURIComponent(finalQuery)}&maxResults=${queryMax}`;

  const listResp = await httpsGetJson(listUrl, { Authorization: `Bearer ${accessToken}` });
  if (listResp.statusCode !== 200) {
    console.warn('[GMAIL_SCAN] Gmail API message list failed', {
      correlationId,
      statusCode: listResp.statusCode,
      errorReason: listResp.body?.error?.reason || 'unknown',
      errorCode: listResp.body?.error?.code || null,
    });
    const errMsg = listResp.body?.error?.message || `Gmail API returned HTTP ${listResp.statusCode}`;
    return {
      success: false,
      error: errMsg,
      failureStage: 'gmail_message_list',
      emailsScanned: 0,
      transactionCandidates: [],
      rawScannedEmails: [],
      queryUsed: finalQuery,
    };
  }

  const messages = listResp.body?.messages || [];
  if (messages.length === 0) {
    console.log('[GMAIL_SCAN] Gmail query returned no messages', {
      correlationId,
    });
    return {
      success: true,
      correlationId,
      extractionMode: 'none',
      fallbackReason: null,
      emailsScanned: 0,
      transactionCandidates: [],
      rawScannedEmails: [],
      queryUsed: finalQuery,
    };
  }

  // Scan ALL messages returned for this timeframe in concurrent batches of 20
  const targetMessages = messages;
  const rawEmailsResults = [];
  const chunkSize = 20;

  for (let i = 0; i < targetMessages.length; i += chunkSize) {
    const chunk = targetMessages.slice(i, i + chunkSize);
    const chunkResults = await Promise.all(
      chunk.map(async (msg) => {
        try {
          const msgUrl = `https://gmail.googleapis.com/gmail/v1/users/me/messages/${msg.id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date`;
          const msgResp = await httpsGetJson(msgUrl, { Authorization: `Bearer ${accessToken}` }, 4500);
          if (msgResp.statusCode !== 200 || !msgResp.body) return null;

          const msgData = msgResp.body;
          const headers = msgData.payload?.headers || [];
          const subject = headers.find(h => h.name === 'Subject')?.value || '';
          const from = headers.find(h => h.name === 'From')?.value || '';
          const dateHeader = headers.find(h => h.name === 'Date')?.value || '';
          const snippet = msgData.snippet || '';

          let isoDate = '';
          if (msgData.internalDate) {
            try {
              isoDate = new Date(parseInt(msgData.internalDate, 10)).toISOString();
            } catch (_) {}
          }
          if (!isoDate && dateHeader) {
            try {
              isoDate = new Date(dateHeader).toISOString();
            } catch (_) {}
          }

          return {
            messageId: msg.id,
            subject,
            from,
            date: isoDate || dateHeader,
            snippet,
          };
        } catch (e) {
          console.warn('Error fetching message details:', e.message);
          return null;
        }
      })
    );
    rawEmailsResults.push(...chunkResults);
  }

  const rawEmails = rawEmailsResults.filter(Boolean);
  const scanned = rawEmails.length;

  // --- Stage 2: Intelligence Processing via Gemini Flash ---
  const aiParseResult = await parseEmailsWithGemini(rawEmails, { correlationId });
  const aiResults = aiParseResult.items;
  const extractionMode = aiResults && aiResults.length > 0
    ? 'gemini'
    : 'deterministic_fallback';
  const fallbackReason = aiResults && aiResults.length > 0
    ? null
    : aiParseResult.fallbackReason;
  const candidates = [];
  const balanceSnapshots = [];

  if (aiResults && aiResults.length > 0) {
    console.log('[GMAIL_SCAN] Using Gemini classifications', {
      correlationId,
      classifiedEmailCount: aiResults.length,
    });
    const aiMap = new Map();
    for (const item of aiResults) {
      if (item.id) aiMap.set(String(item.id), item);
    }

    for (const email of rawEmails) {
      const fullText = `${email.subject} ${email.snippet}`;
      const aiItem = aiMap.get(String(email.messageId));
      if (!aiItem) continue;

      // Handle balance snapshot updates
      if (aiItem.isBalanceUpdate && aiItem.balance > 0) {
        let mask = (aiItem.accountMask || '').trim();
        if (!mask || mask.length < 4) mask = extractAccountMask(fullText);
        const dateMatch = fullText.match(/\bas\s+on\s+(\d{1,2}-[A-Za-z]{3}-\d{2,4})/i);
        balanceSnapshots.push({
          messageId: email.messageId,
          accountMask: mask,
          balance: parseFloat(aiItem.balance),
          asOfDate: dateMatch ? dateMatch[1] : (aiItem.transactionDate || email.date),
        });
        continue;
      }

      if (!aiItem.isFinancialTransaction || !(aiItem.amount > 0)) continue;

      // Deterministic safeguard 1: Emails with due dates or mention of due are NOT completed transactions
      const hasDueMention = /\b(?:due\s+date|payment\s+due(?:\s+date)?|amount\s+due|total\s+(?:amount\s+)?due|minimum\s+(?:amount\s+)?due|is\s+due(?:\s+on)?|due\s+on\s+[0-9a-z]|due\s+by\s+[0-9a-z]|due\s+today|overdue|payable\s+by|last\s+date\s+(?:to\s+pay|of\s+payment)|pay\s+before\s+due)\b/i.test(fullText) ||
        /\b(?:due\s*:\s*|due\s+on\s+[0-9a-z]|due\s+date\s*:|total\s+due|min\s+due)\b/i.test(fullText) ||
        /(?:bill\s+(?:is\s+)?due|avoid\s+late\s+fees|pay\s+now\s+on\s+CRED)/i.test(fullText);
      if (hasDueMention) {
        console.log('Discarding email with due date / mention of due (safeguard):', email.subject);
        continue;
      }

      // Deterministic safeguard 2: BillPay / Merchant payment receipt without a bank/card account
      const isReceipt = /(?:has\s+been\s+processed\s+successfully\s+via\s+(?:on\s+)?BillPay|BillPay\s+Dear\s+Customer|bill\s+(?:payment\s+)?has\s+been\s+processed\s+successfully|processed\s+successfully\s+via\s+BillPay|we\s+have\s+received\s+(?:a\s+)?payment|thank\s+you\s+for\s+(?:your\s+)?payment|payment\s+receipt)/i.test(fullText);
      if (isReceipt && !hasBankOrCardIdentifier(fullText)) {
        console.log('Discarding bill payment receipt without bank account (safeguard):', email.subject);
        continue;
      }

      let accountMask = (aiItem.accountMask || '').trim();
      if (!accountMask || accountMask.length < 4) {
        accountMask = extractAccountMask(fullText);
      }

      const isCreditCard = /credit\s+card|\bcard\s+ending|\bspent\s+on\s+.*card|\bon\s+.*credit\s+card/i.test(fullText) ||
                           aiItem.accountType === 'CREDIT_CARD' ||
                           /9207|9635/.test(accountMask);

      candidates.push({
        messageId: email.messageId,
        subject: email.subject,
        from: email.from,
        date: aiItem.transactionDate || email.date,
        amount: parseFloat(aiItem.amount),
        snippet: email.snippet,
        merchantName: aiItem.merchant && aiItem.merchant.trim().length > 0 ? aiItem.merchant.trim() : (email.subject || 'Bank Alert'),
        type: aiItem.type || 'DEBIT',
        category: aiItem.category || 'General Expenses',
        subCategory: aiItem.subCategory || '',
        accountMask,
        accountType: isCreditCard ? 'CREDIT_CARD' : (aiItem.accountType || 'SAVINGS'),
        upiId: aiItem.upiId || '',
        needsReview: true,
        source: 'EMAIL',
        aiParsed: true,
      });
    }
  } else {
    // Deterministic Fallback Parser (Strict Filter + Indian Bank Pattern Extraction)
    console.warn('[GMAIL_SCAN] Using deterministic fallback parser', {
      correlationId,
      emailCount: rawEmails.length,
      fallbackReason,
    });
    const spamRegex = /(?:easy\s*emi|lighten\s*your|gift|discount|offer|flat\s*\d+%|apply\s*now|rewards?|crore\s*project|cr\s*project|sensex|nifty|market\s*watch|win\s*(?:₹|rs|\d+)|cashback|chance\s*to\s*win|get\s*a\s*chance|lucky\s*draw|scratch\s*card|bonus|coupon|voucher|festive|deal\s*of|sale\s*is\s*live|recharge\s*.*get|recharge\s*&|promo|promocode|fastag\s*🚗)/i;

    for (const email of rawEmails) {
      if (spamRegex.test(email.subject) || spamRegex.test(email.snippet)) {
        console.log('Discarding promotional email:', email.subject);
        continue;
      }

      const fullText = `${email.subject} ${email.snippet}`;

      // Check 1: Balance Update notification (No money moved)
      const balMatch = fullText.match(/(?:available\s+balance\s+in\s+your\s+account|available\s+bal\s+in\s+your\s+a\/c|available\s+balance\s+is).*?(?:rs\.?|inr)\s*([0-9,]+(?:\.\d{2})?)/i);
      if (balMatch && !/(?:debited|spent|paid|transferred\s+to)/i.test(fullText)) {
        const rawBal = balMatch[1].replace(/,/g, '');
        const bal = parseFloat(rawBal);
        const mask = extractAccountMask(fullText);
        const dateMatch = fullText.match(/\bas\s+on\s+(\d{1,2}-[A-Za-z]{3}-\d{2,4})/i);
        const asOf = dateMatch ? dateMatch[1] : email.date;
        if (!isNaN(bal) && bal > 0 && mask) {
          balanceSnapshots.push({
            messageId: email.messageId,
            accountMask: mask,
            balance: bal,
            asOfDate: asOf,
          });
        }
        console.log('Captured balance snapshot:', mask, bal, asOf);
        continue;
      }

      // Check 2: Merchant Payment Receipt (Airtel, Swiggy, etc. - bank alerts will come separately)
      if (/(?:thank\s+you\s+for\s+choosing|payment\s+receipt\s+attached|find\s+the\s+payment\s+receipt\s+attached|e-receipt|tax\s+invoice)/i.test(fullText)) {
        console.log('Discarding merchant receipt (bank/billpay alert will be processed separately):', email.subject);
        continue;
      }

      // Check 2b: BillPay confirmation receipt emails (the real debit is the HDFCBP* bank alert)
      // Uses the KEY DIFFERENTIATOR: processed successfully via BillPay BUT no bank account number → receipt
      const hasBankAccountInText = hasBankOrCardIdentifier(fullText);
      if (/(?:has\s+been\s+processed\s+successfully\s+via\s+(?:on\s+)?BillPay|BillPay\s+Dear\s+Customer|bill\s+(?:payment\s+)?has\s+been\s+processed\s+successfully|processed\s+successfully\s+via\s+BillPay)/i.test(fullText) &&
          !hasBankAccountInText) {
        console.log('Discarding BillPay confirmation receipt (no bank account — merchant receipt):', email.subject);
        continue;
      }

      // Check 2c: Emails with due dates or mention of due — NOT a real transaction
      const hasDueMention = /\b(?:due\s+date|payment\s+due(?:\s+date)?|amount\s+due|total\s+(?:amount\s+)?due|minimum\s+(?:amount\s+)?due|is\s+due(?:\s+on)?|due\s+on\s+[0-9a-z]|due\s+by\s+[0-9a-z]|due\s+today|overdue|payable\s+by|last\s+date\s+(?:to\s+pay|of\s+payment)|pay\s+before\s+due)\b/i.test(fullText) ||
        /\b(?:due\s*:\s*|due\s+on\s+[0-9a-z]|due\s+date\s*:|total\s+due|min\s+due)\b/i.test(fullText) ||
        /(?:bill\s+(?:is\s+)?due|avoid\s+late\s+fees|pay\s+now\s+on\s+CRED)/i.test(fullText);
      if (hasDueMention) {
        console.log('Discarding bill-due reminder notification / statement with due date:', email.subject);
        continue;
      }

      // Check 2d: Bank-account-presence test — any email that talks about payment/processing
      // but has NO bank account or credit card number is likely a merchant receipt or notification
      // Allow investment notifications (RD/FD) through without account numbers if actual movement
      const isInvestmentNotif = /(?:recurring\s+deposit|fixed\s+deposit|\brd\b|\bfd\b)/i.test(fullText);
      if (!hasBankAccountInText && !isInvestmentNotif &&
          /(?:processed\s+successfully|payment\s+received|we\s+have\s+received\s+(?:a\s+)?payment|thank\s+you\s+for\s+(?:your\s+)?payment)/i.test(fullText)) {
        console.log('Discarding payment confirmation without bank account (merchant receipt):', email.subject);
        continue;
      }

      // A real transaction alert MUST contain an explicit financial movement verb
      const hasExecutionVerb = /(?:\bdebited\b|\bcredited\b|\bspent\b|\bpaid\b|\bwithdrawn\b|\btransferred\b|\bpurchased\b|\bdeducted\b|\breceived\b|credit\s+in|credit\s+to|neft|imps|rtgs|bbps)/i.test(fullText);
      if (!hasExecutionVerb) {
        console.log('Discarding non-transaction email (no financial movement verb):', email.subject);
        continue;
      }

      const amountMatch = fullText.match(/(?:(?:Amount|Payment)\s*(?:received|paid|debited|credited)?:?\s*(?:INR|Rs\.?|₹)?\s*|INR\s*|Rs\.?\s*|₹\s*)([\d,]+(?:\.\d{1,2})?)/i);
      let amount = amountMatch ? parseFloat(amountMatch[1].replace(/,/g, '')) : null;

      // Hard constraint: MUST have amount > 0 for standard transactions
      if (!amount || amount <= 0) continue;

      let isCredit = false;
      if (/successfully\s+credited|received\s+a\s+credit|credit\s+in\s+your|amount\s+received|amount\s+credited|neft\s+cr|credited\s+to|deposited/i.test(fullText)) {
        isCredit = true;
      }
      const isCreditCardRepayment = /payment\s+.*?\s+received\s+towards\s+your\s+.*?(?:credit\s*card)|credit\s+card\s+payment\s+was\s+successful/i.test(fullText);

      let merchant = '';
      let category = 'General Expenses';
      let subCategory = '';
      let accountMask = '';
      let upiId = '';

      // Extract reference / UTR number
      const refMatch = fullText.match(/(?:UPI\s+Reference\s+No\.?|UTR\s+No\.?|Transaction\s+Reference\s+No\.?|reference\s*no\.?)\s*:?\s*([A-Za-z0-9]+)/i);
      if (refMatch) upiId = refMatch[1];

      // Case A0: HDFC BillPay Credit Card Debits (towards HDFCBP*/HDFCBP* VPA codes)
      // e.g. "Rs. 706.82 has been debited from your HDFC Bank Credit Card ending 9207 towards HDFCBPBAND"
      // e.g. "Rs. 1950.54 has been debited from your HDFC Bank Credit Card ending 9207 towards HDFCBPMOBPO"
      const hdfcBpMatch = fullText.match(/towards\s+(HDFC(?:BP)?[A-Z0-9]+)/i);
      if (hdfcBpMatch) {
        const vpaCode = hdfcBpMatch[1].toUpperCase();
        category = 'Bills & Utilities';
        if (/HDFCBPBAND|HDFCBAND|BAND/.test(vpaCode)) {
          merchant = 'ACT Fibernet';
          subCategory = 'Broadband & Internet';
        } else if (/HDFCBPMOBPO|HDFCMOBPO|MOBPO/.test(vpaCode)) {
          merchant = 'Airtel Postpaid';
          subCategory = 'Mobile Recharge & Postpaid';
        } else if (/HDFCBPELEC|HDFCBPBESCOM|BESCOM|ELEC/.test(vpaCode)) {
          merchant = 'BESCOM Electricity';
          subCategory = 'Electricity Bill';
        } else if (/HDFCBPGAS|HDFCBPINDANE|INDANE|GAS/.test(vpaCode)) {
          merchant = 'Gas Bill Payment';
          subCategory = 'Gas & LPG';
        } else if (/HDFCBPWTR|WATER/.test(vpaCode)) {
          merchant = 'Water Bill';
          subCategory = 'Utility Bill';
        } else {
          // Generic HDFCBP* — keep VPA as merchant label for user to alias
          merchant = vpaCode;
          subCategory = 'Utility Bill';
        }
      }
      // Case A: Recurring Deposit / RD / FD Investment
      else if (/recurring\s+deposit|\brd\b|fixed\s+deposit|\bfd\b/i.test(fullText)) {
        category = 'Investments';
        subCategory = 'Recurring Deposit';
        const rdMatch = fullText.match(/(?:RD|FD)\s*No\.?\s*([xX*]*\d{4})/i);
        if (rdMatch) {
          accountMask = '•••• ' + rdMatch[1].slice(-4);
          merchant = 'Recurring Deposit (RD ' + accountMask + ')';
        } else {
          merchant = 'Bank Recurring Deposit';
        }
      }
      // Case A2: Loan EMI Deduction (e.g. HDFC Bank added to EMI 150250733)
      else if (/(?:added\s+to\s+EMI|towards\s+EMI|loan\s+account|EMI\s+account|\bEMI\s+\d{4,16})/i.test(fullText)) {
        category = 'Loans & Debt';
        subCategory = 'Personal Loan EMI';
        const emiMatch = fullText.match(/(?:added\s+to\s+EMI|towards\s+EMI|\bEMI)\s*([xX*]*\d{4,16})/i);
        let loanMask = '';
        if (emiMatch) {
          loanMask = '•••• ' + emiMatch[1].slice(-4);
        }
        const bankMatch = fullText.match(/\b(HDFC|ICICI|SBI|AXIS|KOTAK|RBL|YES|IDFC|BOB|PNB|CANARA|INDUSIND)\s+Bank/i);
        const bankName = bankMatch ? bankMatch[1] + ' Bank' : 'Bank';
        merchant = loanMask ? `${bankName} Loan EMI (${loanMask})` : `${bankName} Loan EMI`;
      }
      // Case A3: Platform Aggregators with Sub-Service VPAs (e.g. CRED FASTag, Rent)
      else if (/cred\.fastag|\bfastag\b/i.test(fullText)) {
        category = 'Transport & Fuel';
        subCategory = 'FASTag & Tolls';
        merchant = /dreamplug|cred/i.test(fullText) ? 'CRED (FASTag Recharge)' : 'FASTag Recharge';
      }
      else if (/cred\.rent/i.test(fullText)) {
        category = 'Bills & Utilities';
        subCategory = 'House Rent';
        merchant = 'CRED (House Rent)';
      }
      // Case A4: Self Transfer / Debit towards Own VPA or Name
      else if (/towards\s+VPA\s+[A-Za-z0-9._@-]+(?:\s*\([A-Za-z0-9\s]+?\))?/i.test(fullText)) {
        const vpaMatch = fullText.match(/towards\s+VPA\s+([A-Za-z0-9._@-]+)(?:\s*\(([A-Za-z0-9\s]+?)\))?/i);
        if (vpaMatch) {
          const payeeVpa = vpaMatch[1];
          const payeeName = vpaMatch[2] ? vpaMatch[2].trim() : '';
          if (/RAKSHITH/i.test(payeeName) || /7813004130/i.test(payeeVpa)) {
            category = 'Self Transfer';
            subCategory = 'Account to Account Transfer';
            merchant = 'Self Transfer';
          }
        }
      }
      // Case B: HDFC Bank Credit with explicit Sender name (inline or lettered-list format)
      // Handles: "Sender: RAKSHITH GOWDA G (VPA: 7813004130@axl)"
      // Also handles: "b. Sender: RAKSHITH GOWDA G (VPA: 7813004130@axl)" (lettered list format in newer HDFC emails)
      else if (/(?:b\.\s*)?Sender\s*:\s*[A-Za-z0-9\s]+?(?:\s*\(VPA:|\n|\r|$)/i.test(fullText) ||
               /successfully\s+credited\s+to\s+your\s+(?:HDFC|ICICI|SBI|AXIS|RBL)\s+Bank\s+account/i.test(fullText)) {
        // Try lettered-list format first: "b. Sender: NAME (VPA: vpa@upi)"
        const letteredSenderMatch = fullText.match(/b\.\s*Sender\s*:\s*([A-Za-z0-9\s]+?)(?:\s*\(VPA:\s*([A-Za-z0-9._@-]+)\)|\n|\r|$)/i);
        // Then try inline format: "Sender: NAME (VPA: vpa@upi)"
        const inlineSenderMatch = !letteredSenderMatch && fullText.match(/Sender\s*:\s*([A-Za-z0-9\s]+?)(?:\s*\(VPA:\s*([A-Za-z0-9._@-]+)\)|\n|\r|$)/i);
        const senderMatch = letteredSenderMatch || inlineSenderMatch;

        if (senderMatch) {
          const sName = senderMatch[1].trim();
          const sVpa = senderMatch[2] ? senderMatch[2].trim() : '';
          if (/RAKSHITH/i.test(sName) || /7813004130/i.test(sVpa)) {
            merchant = 'Self Transfer';
            category = 'Self Transfer';
            subCategory = 'Account to Account Transfer';
          } else {
            merchant = sName;
            category = 'Personal Transfers';
            subCategory = 'Friends & Family';
          }
          if (sVpa) upiId = upiId || sVpa;
        } else if (/successfully\s+credited/i.test(fullText)) {
          // HDFC credit notification without sender info yet — use a sensible fallback
          // Try to extract sender from "c. UPI Reference" or "Reference Details:"
          const refDetailsMatch = fullText.match(/Reference\s+Details?\s*:?\s*([A-Za-z0-9\s\-]+?)(?:\n|\r|$)/i);
          if (refDetailsMatch) {
            const rd = refDetailsMatch[1].trim();
            if (!/NEFT|IMPS|RTGS|Cr-/i.test(rd)) {
              merchant = rd.length > 2 ? rd : 'Bank Credit';
            }
          }
          if (!merchant || merchant === 'Bank Alert') {
            merchant = 'Bank Credit';
          }
          category = 'Personal Transfers';
          subCategory = 'Friends & Family';
        }
      }
      // Case B2: Summary / Account Number XX... Credit
      else if (/Amount\s+Credited|summary\s+of\s+your\s+transaction/i.test(fullText)) {
        if (/RAKSHITH/i.test(fullText)) {
          merchant = 'Self Transfer';
          category = 'Self Transfer';
          subCategory = 'Account to Account Transfer';
        } else {
          merchant = 'Bank Credit';
          category = 'Income';
          subCategory = 'Other Income';
        }
      }
      // Case C: NEFT / IMPS / RTGS Salary or Inflow (e.g. HDFC Bank)
      else if (/NEFT\s+Cr|IMPS\s+Cr|SALARY\s+TRANSIT/i.test(fullText)) {
        category = 'Income';
        const neftMatch = fullText.match(/(?:NEFT\s+Cr-[A-Za-z0-9]+-|Cr-)([A-Za-z0-9\s&]+?)(?:-[A-Za-z0-9\s]+-[A-Za-z0-9]+|$)/i);
        if (neftMatch) {
          let rawName = neftMatch[1].trim();
          if (/SALARY/i.test(rawName)) {
            subCategory = 'Salary';
            rawName = rawName.replace(/\s*SALARY\s*TRANSIT\s*AC|\s*TRANSIT\s*AC/i, '').trim();
          }
          merchant = rawName.length > 2 ? rawName : 'NEFT Credit';
        } else {
          merchant = 'Bank NEFT Credit';
        }
      }
      // Case D: BillPay processed (e.g. Airtel Postpaid Fetch and Pay via BillPay)
      else if (/processed\s+successfully\s+via.*?BillPay|via\s+on\s+BillPay/i.test(fullText)) {
        category = 'Bills & Utilities';
        const billerMatch = fullText.match(/Biller\s*Name\s*:?\s*([A-Za-z0-9\s&._-]+?)(?:\s+Mobile|\s+Bill|\s+Payment|\n|\r|$)/i) ||
                            fullText.match(/bill\s+payment\s+for\s+([A-Za-z0-9\s&._-]+?)\s+has\s+been\s+processed/i);
        if (billerMatch) {
          let rawBiller = billerMatch[1].trim();
          rawBiller = rawBiller.replace(/\s*Fetch\s*and\s*Pay/i, '').trim();
          merchant = rawBiller;
        } else {
          merchant = 'BillPay Utility';
        }
        if (/airtel|jio|vi\b|vodafone|postpaid|mobile/i.test(merchant)) {
          subCategory = 'Mobile Recharge & Postpaid';
        }
      }
      // Case E: Credit Card Bill Payment (e.g. CRED or RBL Bank BBPS)
      else if (isCreditCardRepayment) {
        category = 'Bills & Utilities';
        subCategory = 'Credit Card Bill';
        const cardMatch = fullText.match(/towards\s+your\s+([A-Za-z0-9\s&]+?Credit\s+Card)/i);
        const credCardMatch = fullText.match(/\b([A-Z][A-Za-z0-9\s]{1,15}?Bank)\s*•+\s*(\d{4})/i);
        if (cardMatch) {
          merchant = cardMatch[1].trim();
        } else if (credCardMatch) {
          merchant = credCardMatch[1].trim() + ' Credit Card';
          accountMask = '•••• ' + credCardMatch[2];
        } else {
          merchant = 'Credit Card Bill Payment';
        }
      }
      // Case F: Card Spend at Merchant (e.g. INR336.11 spent at APPAYANNA PETROLEUM on RBL Bank credit card (9635))
      else if (/spent\s+at\s+/i.test(fullText)) {
        const spentMatch = fullText.match(/spent\s+at\s+([A-Za-z0-9_.\-&/ ]+?)\s+on\s+([A-Za-z0-9\s]+?credit\s+card(?:\s*\(\d+\))?|[A-Za-z0-9\s]+?card)/i);
        if (spentMatch) {
          merchant = spentMatch[1].trim();
          if (/petroleum|petrol|fuel|hpcl|bpcl|iocl/i.test(merchant)) {
            category = 'Transport & Fuel';
            subCategory = 'Fuel & Petrol';
          }
        }
      }
      // Case G: Standard UPI or Card spent
      else {
        const upiMatch = fullText.match(/towards\s+(?:VPA\s+)?([A-Za-z0-9._@-]+)(?:\s*\(([^)]+)\))?/i);
        if (upiMatch) {
          upiId = upiMatch[1];
          merchant = upiMatch[2] ? upiMatch[2].trim() : upiMatch[1].split('@')[0];
        }

        if (!merchant || merchant === 'Bank Alert') {
          const merchantMatch = fullText.match(/(?:at|to|info:?|towards|vpa|paid\s+to|on\s+BillPay\s+for:?)\s+([A-Za-z0-9_.\-&/]{2,32}?)(?:\s+on\s+\d|\s+dated|\.|\,|$)/i);
          if (merchantMatch && merchantMatch[1].trim().length > 1) {
            const raw = merchantMatch[1].trim();
            if (!/^(your|the|an|a|vpa|bank)$/i.test(raw)) {
              merchant = raw;
            }
          }
        }

        if (!merchant || merchant === 'Bank Alert') {
          const spentAtMatch = fullText.match(/spent\s+.*?\s+at\s+([A-Za-z0-9_.\-&/]{2,32}?)(?:\s+on|\.|\,|$)/i);
          if (spentAtMatch && spentAtMatch[1].trim().length > 1) {
            merchant = spentAtMatch[1].trim();
          }
        }

        if (!merchant || merchant === 'Bank Alert') {
          if (/BillPay/i.test(fullText)) {
            merchant = 'BillPay Utility';
          } else {
            const cleanSubject = email.subject.replace(/alert|statement|transaction|notification|update/gi, '').trim();
            merchant = cleanSubject.length > 2 ? cleanSubject : 'Bank Alert';
          }
        }
      }

      // Extract account mask
      if (!accountMask) {
        accountMask = extractAccountMask(fullText);
      }

      const isCreditCard = /credit\s+card|\bcard\s+ending|\bspent\s+on\s+.*card|\bon\s+.*credit\s+card/i.test(fullText) ||
                           /9207|9635/.test(accountMask);

      candidates.push({
        messageId: email.messageId,
        subject: email.subject,
        from: email.from,
        date: email.date,
        amount,
        snippet: email.snippet,
        merchantName: merchant,
        type: isCredit ? 'CREDIT' : 'DEBIT',
        category,
        subCategory,
        accountMask,
        accountType: isCreditCard ? 'CREDIT_CARD' : 'SAVINGS',
        upiId,
        needsReview: true,
        source: 'EMAIL',
        aiParsed: false,
      });
    }
  }

  // De-duplicate balance snapshots to pick the LATEST balance per account mask
  const latestBalancesByMask = {};
  for (const snap of balanceSnapshots) {
    if (!snap.accountMask) continue;
    const existing = latestBalancesByMask[snap.accountMask];
    if (!existing || new Date(snap.asOfDate || 0) >= new Date(existing.asOfDate || 0)) {
      latestBalancesByMask[snap.accountMask] = snap;
    }
  }

  return {
    success: true,
    correlationId,
    extractionMode,
    fallbackReason,
    emailsScanned: scanned,
    transactionCandidates: candidates,
    balanceSnapshots: Object.values(latestBalancesByMask),
    rawScannedEmails: rawEmails,
    queryUsed: finalQuery,
  };
}

function httpsPostJson(url, postData, extraHeaders = {}, timeoutMs = 7000) {
  return new Promise((resolve) => {
    const urlObj = new URL(url);
    const options = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData),
        ...extraHeaders,
      },
      timeout: timeoutMs,
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        try {
          resolve({ statusCode: res.statusCode, body: JSON.parse(data) });
        } catch (e) {
          resolve({ statusCode: res.statusCode, body: data });
        }
      });
    });
    req.on('timeout', () => {
      req.destroy();
      resolve({ statusCode: 408, body: { error: 'Request timeout' } });
    });
    req.on('error', (err) => resolve({ statusCode: 500, body: { error: err.message } }));
    req.write(postData);
    req.end();
  });
}

function httpsGetJson(url, extraHeaders = {}, timeoutMs = 4000) {
  return new Promise((resolve) => {
    const urlObj = new URL(url);
    const options = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      headers: { Accept: 'application/json', ...extraHeaders },
      timeout: timeoutMs,
    };
    const req = https.get(options, (res) => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        try {
          resolve({ statusCode: res.statusCode, body: JSON.parse(data) });
        } catch (e) {
          resolve({ statusCode: res.statusCode, body: data });
        }
      });
    });
    req.on('timeout', () => {
      req.destroy();
      resolve({ statusCode: 408, body: { error: 'Request timeout' } });
    });
    req.on('error', (err) => resolve({ statusCode: 500, body: { error: err.message } }));
  });
}

exports.handler = async (event) => {
  const httpMethod = event.requestContext?.http?.method || event.httpMethod || 'GET';
  const rawPath = event.rawPath || event.path || '/';
  const requestId = event.requestContext?.requestId || 'unknown';
  logBackendEvent('info', 'request', {
    outcome: 'started',
    requestId,
    method: httpMethod,
    path: rawPath,
  });

  if (httpMethod === 'OPTIONS') {
    return formatResponse(200, { message: 'OK' });
  }

  const reqHeaders = event.headers || {};

  try {
    // Health check
    if (rawPath === '/api/health' || rawPath === '/health') {
      return formatResponse(200, { status: 'HEALTHY', timestamp: new Date().toISOString() });
    }

    const userPk = resolveGatewayAuthenticatedUserPk(event);
    if (!userPk) {
      return formatResponse(401, { error: 'A valid Google ID token is required.' });
    }

    // Gmail Inbox Scan
    if ((rawPath === '/api/gmail/scan' || rawPath.endsWith('/gmail/scan')) && httpMethod === 'POST') {
      const gmailToken = reqHeaders['x-gmail-token'] || reqHeaders['X-Gmail-Token'];
      if (!gmailToken) {
        return formatResponse(401, { error: 'Gmail access token required. Grant gmail.readonly permission to scan your inbox.' });
      }
      let customQuery = '';
      let scanOptions = {};
      try {
        const bodyObj = JSON.parse(event.body || '{}');
        customQuery = bodyObj.query || '';
        if (bodyObj.afterTimestamp || bodyObj.after) {
          scanOptions.afterTimestamp = bodyObj.afterTimestamp || bodyObj.after;
        }
        if (bodyObj.beforeTimestamp || bodyObj.before) {
          scanOptions.beforeTimestamp = bodyObj.beforeTimestamp || bodyObj.before;
        }
        if (bodyObj.maxResults) {
          scanOptions.maxResults = parseInt(bodyObj.maxResults, 10);
        }
      } catch (_) {}

      const correlationId = event.requestContext?.requestId || 'unknown';
      const result = await scanGmailInbox(
        gmailToken,
        customQuery,
        scanOptions,
        { correlationId },
      );
      if (!result.success) {
        return formatResponse(502, {
          error: result.error,
          message: `Gmail scan error: ${result.error}`,
          failureStage: result.failureStage || 'gmail_scan',
          correlationId,
          emailsScanned: 0,
          transactionCandidates: [],
        });
      }

      return formatResponse(200, {
        ...result,
        correlationId,
        message: `Scanned ${result.emailsScanned} financial emails, found ${result.transactionCandidates.length} bank transactions`,
      });
    }

    // Financial Accounts
    if (rawPath === '/api/accounts' || rawPath.endsWith('/accounts')) {
      if (httpMethod === 'GET') {
        const result = await ddbDocClient.send(new QueryCommand({
          TableName: TABLE_NAME,
          KeyConditionExpression: 'PK = :pk AND begins_with(SK, :skPrefix)',
          ExpressionAttributeValues: { ':pk': userPk, ':skPrefix': 'ACC#' },
        }));
        return formatResponse(200, (result.Items || []).map(item => item.data || item));
      }
      if (httpMethod === 'POST') {
        const account = JSON.parse(event.body || '{}');
        account.id = account.id || `acc-${Date.now()}`;
        await ddbDocClient.send(new PutCommand({
          TableName: TABLE_NAME,
          Item: { PK: userPk, SK: `ACC#${account.id}`, data: account, createdAt: new Date().toISOString() },
        }));
        await publishSyncEvent(userPk, 'ACCOUNT_UPSERTED', account);
        return formatResponse(201, account);
      }
    }

    // Counterparty Entities & UPI Alias Mapping
    if (rawPath === '/api/entities' || rawPath.endsWith('/entities')) {
      if (httpMethod === 'GET') {
        const result = await ddbDocClient.send(new QueryCommand({
          TableName: TABLE_NAME,
          KeyConditionExpression: 'PK = :pk AND begins_with(SK, :skPrefix)',
          ExpressionAttributeValues: { ':pk': userPk, ':skPrefix': 'ENTITY#' },
        }));
        return formatResponse(200, (result.Items || []).map(item => item.data || item));
      }
      if (httpMethod === 'POST') {
        const entity = JSON.parse(event.body || '{}');
        entity.id = entity.id || `entity-${Date.now()}-${Math.random().toString(36).substring(7)}`;
        entity.updatedAt = new Date().toISOString();
        await ddbDocClient.send(new PutCommand({
          TableName: TABLE_NAME,
          Item: { PK: userPk, SK: `ENTITY#${entity.id}`, data: entity, createdAt: entity.createdAt || new Date().toISOString() },
        }));
        await publishSyncEvent(userPk, 'ENTITY_UPSERTED', entity);
        return formatResponse(201, entity);
      }
    }

    // Transactions
    if (rawPath === '/api/transactions' || rawPath.endsWith('/transactions')) {
      if (httpMethod === 'GET') {
        let limit;
        let cursor;
        try {
          limit = parseTransactionLimit(event.queryStringParameters?.limit);
          cursor = decodeCursor(event.queryStringParameters?.cursor, userPk);
        } catch (error) {
          return formatResponse(400, { error: error.message });
        }
        const result = await listTransactions({
          limit,
          exclusiveStartKey: cursor,
          queryPage: ({ limit: pageLimit, exclusiveStartKey }) =>
            ddbDocClient.send(new QueryCommand({
              TableName: TABLE_NAME,
              KeyConditionExpression: 'PK = :pk AND begins_with(SK, :skPrefix)',
              ExpressionAttributeValues: { ':pk': userPk, ':skPrefix': 'TXN#' },
              ScanIndexForward: false,
              Limit: pageLimit,
              ...(exclusiveStartKey ? { ExclusiveStartKey: exclusiveStartKey } : {}),
            })),
        });
        return formatResponse(200, {
          items: result.items,
          ...(result.lastEvaluatedKey
            ? { nextCursor: encodeCursor(result.lastEvaluatedKey) }
            : {}),
        });
      }
      if (httpMethod === 'POST') {
        const body = JSON.parse(event.body || '{}');
        if (Array.isArray(body)) {
          for (const txn of body) {
            txn.id = txn.id || `txn-${Date.now()}-${Math.random().toString(36).substring(7)}`;
            const createdAt = new Date().toISOString();
            await ddbDocClient.send(new PutCommand({
              TableName: TABLE_NAME,
              Item: {
                PK: userPk,
                SK: transactionSortKey(txn, createdAt),
                data: txn,
                createdAt,
              },
            }));
            await publishSyncEvent(userPk, 'TRANSACTION_UPSERTED', txn);
          }
          return formatResponse(201, { count: body.length, message: 'Batch inserted' });
        } else {
          body.id = body.id || `txn-${Date.now()}`;
          const createdAt = new Date().toISOString();
          await ddbDocClient.send(new PutCommand({
            TableName: TABLE_NAME,
            Item: {
              PK: userPk,
              SK: transactionSortKey(body, createdAt),
              data: body,
              createdAt,
            },
          }));
          await publishSyncEvent(userPk, 'TRANSACTION_UPSERTED', body);
          return formatResponse(201, body);
        }
      }
    }

    // Peer Debts
    if (rawPath === '/api/debts' || rawPath.endsWith('/debts')) {
      if (httpMethod === 'GET') {
        const result = await ddbDocClient.send(new QueryCommand({
          TableName: TABLE_NAME,
          KeyConditionExpression: 'PK = :pk AND begins_with(SK, :skPrefix)',
          ExpressionAttributeValues: { ':pk': userPk, ':skPrefix': 'DEBT#' },
        }));
        return formatResponse(200, (result.Items || []).map(item => item.data || item));
      }
      if (httpMethod === 'POST') {
        const debt = JSON.parse(event.body || '{}');
        debt.id = debt.id || `debt-${Date.now()}`;
        await ddbDocClient.send(new PutCommand({
          TableName: TABLE_NAME,
          Item: { PK: userPk, SK: `DEBT#${debt.id}`, data: debt, createdAt: new Date().toISOString() },
        }));
        await publishSyncEvent(userPk, 'PEER_DEBT_UPSERTED', debt);
        return formatResponse(201, debt);
      }
    }

    // Bills
    if (rawPath === '/api/bills' || rawPath.endsWith('/bills')) {
      if (httpMethod === 'GET') {
        const result = await ddbDocClient.send(new QueryCommand({
          TableName: TABLE_NAME,
          KeyConditionExpression: 'PK = :pk AND begins_with(SK, :skPrefix)',
          ExpressionAttributeValues: { ':pk': userPk, ':skPrefix': 'BILL#' },
        }));
        return formatResponse(200, (result.Items || []).map(item => item.data || item));
      }
      if (httpMethod === 'POST') {
        const bill = JSON.parse(event.body || '{}');
        bill.id = bill.id || `bill-${Date.now()}`;
        await ddbDocClient.send(new PutCommand({
          TableName: TABLE_NAME,
          Item: { PK: userPk, SK: `BILL#${bill.id}`, data: bill, createdAt: new Date().toISOString() },
        }));
        return formatResponse(201, bill);
      }
    }

    // Budgets
    if (rawPath === '/api/budgets' || rawPath.endsWith('/budgets')) {
      if (httpMethod === 'GET') {
        const result = await ddbDocClient.send(new QueryCommand({
          TableName: TABLE_NAME,
          KeyConditionExpression: 'PK = :pk AND begins_with(SK, :skPrefix)',
          ExpressionAttributeValues: { ':pk': userPk, ':skPrefix': 'BUDGET#' },
        }));
        return formatResponse(200, (result.Items || []).map(item => item.data || item));
      }
      if (httpMethod === 'POST') {
        const budget = JSON.parse(event.body || '{}');
        budget.id = budget.id || `budget-${Date.now()}`;
        await ddbDocClient.send(new PutCommand({
          TableName: TABLE_NAME,
          Item: { PK: userPk, SK: `BUDGET#${budget.id}`, data: budget, createdAt: new Date().toISOString() },
        }));
        await publishSyncEvent(userPk, 'BUDGET_UPSERTED', budget);
        return formatResponse(201, budget);
      }
    }

    // Loans
    if (rawPath === '/api/loans' || rawPath.endsWith('/loans')) {
      if (httpMethod === 'GET') {
        const result = await ddbDocClient.send(new QueryCommand({
          TableName: TABLE_NAME,
          KeyConditionExpression: 'PK = :pk AND begins_with(SK, :skPrefix)',
          ExpressionAttributeValues: { ':pk': userPk, ':skPrefix': 'LOAN#' },
        }));
        return formatResponse(200, (result.Items || []).map(item => item.data || item));
      }
      if (httpMethod === 'POST') {
        const loan = JSON.parse(event.body || '{}');
        loan.id = loan.id || `loan-${Date.now()}`;
        await ddbDocClient.send(new PutCommand({
          TableName: TABLE_NAME,
          Item: { PK: userPk, SK: `LOAN#${loan.id}`, data: loan, createdAt: new Date().toISOString() },
        }));
        await publishSyncEvent(userPk, 'LOAN_UPSERTED', loan);
        return formatResponse(201, loan);
      }
    }

    // Card EMIs
    if (rawPath === '/api/card-emis' || rawPath.endsWith('/card-emis')) {
      if (httpMethod === 'GET') {
        const result = await ddbDocClient.send(new QueryCommand({
          TableName: TABLE_NAME,
          KeyConditionExpression: 'PK = :pk AND begins_with(SK, :skPrefix)',
          ExpressionAttributeValues: { ':pk': userPk, ':skPrefix': 'EMI#' },
        }));
        return formatResponse(200, (result.Items || []).map(item => item.data || item));
      }
      if (httpMethod === 'POST') {
        const emi = JSON.parse(event.body || '{}');
        emi.id = emi.id || `emi-${Date.now()}`;
        await ddbDocClient.send(new PutCommand({
          TableName: TABLE_NAME,
          Item: { PK: userPk, SK: `EMI#${emi.id}`, data: emi, createdAt: new Date().toISOString() },
        }));
        await publishSyncEvent(userPk, 'CARD_EMI_UPSERTED', emi);
        return formatResponse(201, emi);
      }
    }

    // Vendor Rules
    if (rawPath === '/api/rules' || rawPath.endsWith('/rules')) {
      if (httpMethod === 'GET') {
        const result = await ddbDocClient.send(new QueryCommand({
          TableName: TABLE_NAME,
          KeyConditionExpression: 'PK = :pk AND begins_with(SK, :skPrefix)',
          ExpressionAttributeValues: { ':pk': userPk, ':skPrefix': 'RULE#' },
        }));
        return formatResponse(200, (result.Items || []).map(item => item.data || item));
      }
      if (httpMethod === 'POST') {
        const rule = JSON.parse(event.body || '{}');
        const pattern = rule.merchantPattern || `rule-${Date.now()}`;
        await ddbDocClient.send(new PutCommand({
          TableName: TABLE_NAME,
          Item: { PK: userPk, SK: `RULE#${pattern}`, data: rule, createdAt: new Date().toISOString() },
        }));
        await publishSyncEvent(userPk, 'VENDOR_RULE_UPSERTED', rule);
        return formatResponse(201, rule);
      }
    }

    // Analytics and exports always derive from the authenticated user's canonical DynamoDB records.
    if (rawPath === '/api/analytics/export' || rawPath.endsWith('/analytics/export')) {
      let selection;
      try {
        selection = reportSelection(event.queryStringParameters);
      } catch (error) {
        if (error instanceof InvalidReportRequestError) {
          return formatResponse(400, { error: error.message });
        }
        throw error;
      }
      const items = await loadCanonicalTransactions(userPk);
      const format = String(event.queryStringParameters?.format || '').toLowerCase();
      if (format === 'csv') {
        return binaryResponse(
          200,
          csvForReport(items, selection),
          'text/csv; charset=utf-8',
          `financial-report-${selection.month}.csv`,
        );
      }
      if (format === 'pdf') {
        return binaryResponse(
          200,
          pdfForReport(buildFinancialReport(items, selection)),
          'application/pdf',
          `financial-report-${selection.month}.pdf`,
        );
      }
      return formatResponse(400, { error: 'format must be csv or pdf' });
    }

    if (rawPath === '/api/analytics' || rawPath.endsWith('/analytics')) {
      let selection;
      try {
        selection = reportSelection(event.queryStringParameters);
      } catch (error) {
        if (error instanceof InvalidReportRequestError) {
          return formatResponse(400, { error: error.message });
        }
        throw error;
      }
      return formatResponse(
        200,
        buildFinancialReport(await loadCanonicalTransactions(userPk), selection),
      );
    }

    // Factory Reset
    if (rawPath === '/api/data' && httpMethod === 'DELETE') {
      const report = await deleteUserPartition({
        tableName: TABLE_NAME,
        queryPage: (ExclusiveStartKey) =>
          ddbDocClient.send(new QueryCommand({
            TableName: TABLE_NAME,
            KeyConditionExpression: 'PK = :pk',
            ExpressionAttributeValues: { ':pk': userPk },
            ...(ExclusiveStartKey ? { ExclusiveStartKey } : {}),
          })),
        batchWrite: (requests) =>
          client.send(new BatchWriteItemCommand({
            RequestItems: { [TABLE_NAME]: requests },
          })),
      });
      return formatResponse(report.complete ? 200 : 207, {
        message: report.complete
          ? 'Cloud database cleared successfully'
          : 'Cloud database clearing completed with failures',
        ...(report.complete ? {} : { error: 'Cloud database clearing was incomplete' }),
        deletedCount: report.deletedCount,
        failures: report.failures,
      });
    }

    return formatResponse(404, { error: 'Route not found', path: rawPath, method: httpMethod });
  } catch (err) {
    logBackendEvent('error', 'request', {
      outcome: 'failed',
      requestId,
      method: httpMethod,
      path: rawPath,
      exception: err?.name || 'Error',
    });
    return formatResponse(500, { error: err.message });
  }
};
