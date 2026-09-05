const DEFAULT_TRANSACTION_LIMIT = 100;
const MAX_TRANSACTION_LIMIT = 100;
const MAX_BATCH_WRITE_ATTEMPTS = 3;
const MAX_CURSOR_LENGTH = 4096;

class InvalidPaginationRequestError extends Error {}

function parseTransactionLimit(value) {
  if (value === undefined || value === null || value === '') {
    return DEFAULT_TRANSACTION_LIMIT;
  }
  if (typeof value !== 'string' || !/^[1-9]\d*$/.test(value)) {
    throw new InvalidPaginationRequestError('limit must be a positive integer');
  }
  const limit = Number(value);
  if (!Number.isSafeInteger(limit) || limit > MAX_TRANSACTION_LIMIT) {
    throw new InvalidPaginationRequestError(
      `limit must be between 1 and ${MAX_TRANSACTION_LIMIT}`,
    );
  }
  return limit;
}

function encodeCursor(lastEvaluatedKey) {
  if (!lastEvaluatedKey) return undefined;
  return Buffer.from(JSON.stringify(lastEvaluatedKey)).toString('base64url');
}

function decodeCursor(cursor, userPk) {
  if (cursor === undefined || cursor === null || cursor === '') return undefined;
  if (
    typeof cursor !== 'string' ||
    cursor.length > MAX_CURSOR_LENGTH ||
    !/^[A-Za-z0-9_-]+$/.test(cursor)
  ) {
    throw new InvalidPaginationRequestError('cursor is invalid');
  }

  let key;
  try {
    key = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
  } catch (error) {
    throw new InvalidPaginationRequestError('cursor is invalid');
  }

  if (
    !key ||
    Object.getPrototypeOf(key) !== Object.prototype ||
    Object.keys(key).length !== 2 ||
    typeof key.PK !== 'string' ||
    typeof key.SK !== 'string' ||
    !key.PK ||
    !key.SK ||
    key.PK !== userPk
  ) {
    throw new InvalidPaginationRequestError('cursor is invalid');
  }
  return key;
}

function normalizeTransactionItem(item) {
  const transaction = {
    ...(item && typeof item.data === 'object' && item.data !== null
      ? item.data
      : item),
  };
  if (!transaction.id && typeof transaction.txnId === 'string') {
    transaction.id = transaction.txnId;
  }
  for (const field of ['amount', 'netPersonalExpense']) {
    if (typeof transaction[field] === 'string' && transaction[field].trim() !== '') {
      const numericValue = Number(transaction[field]);
      if (Number.isFinite(numericValue)) transaction[field] = numericValue;
    }
  }
  return transaction;
}

async function listTransactions({ limit, exclusiveStartKey, queryPage }) {
  const items = [];
  let nextKey = exclusiveStartKey;

  while (items.length < limit) {
    const result = await queryPage({
      limit: limit - items.length,
      exclusiveStartKey: nextKey,
    });
    const pageItems = result.Items || [];
    items.push(...pageItems.map(normalizeTransactionItem));
    nextKey = result.LastEvaluatedKey;
    if (!nextKey) break;
  }

  return {
    items,
    lastEvaluatedKey: nextKey,
  };
}

function deleteRequestFor(item) {
  if (!item || typeof item.PK !== 'string' || typeof item.SK !== 'string') {
    throw new Error('DynamoDB query returned an item without a string PK and SK');
  }
  return {
    DeleteRequest: {
      Key: {
        PK: { S: item.PK },
        SK: { S: item.SK },
      },
    },
  };
}

function failure(operation, count, error) {
  return {
    operation,
    count,
    error: error instanceof Error ? error.message : String(error),
  };
}

async function deleteBatchWithRetries({
  tableName,
  requests,
  batchWrite,
  wait,
}) {
  let remaining = requests;
  let deletedCount = 0;

  for (let attempt = 1; attempt <= MAX_BATCH_WRITE_ATTEMPTS; attempt++) {
    try {
      const result = await batchWrite(remaining);
      const unprocessed = result.UnprocessedItems?.[tableName] || [];
      deletedCount += remaining.length - unprocessed.length;
      remaining = unprocessed;
    } catch (error) {
      return {
        deletedCount,
        failures: [failure('batchWrite', remaining.length, error)],
      };
    }

    if (remaining.length === 0) {
      return { deletedCount, failures: [] };
    }
    if (attempt < MAX_BATCH_WRITE_ATTEMPTS) {
      await wait(25 * attempt);
    }
  }

  return {
    deletedCount,
    failures: [
      failure(
        'batchWrite',
        remaining.length,
        `DynamoDB left ${remaining.length} delete request(s) unprocessed after ${MAX_BATCH_WRITE_ATTEMPTS} attempts`,
      ),
    ],
  };
}

async function deleteUserPartition({
  tableName,
  queryPage,
  batchWrite,
  wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)),
}) {
  const report = { deletedCount: 0, failures: [] };
  let exclusiveStartKey;
  const seenKeys = new Set();

  do {
    let page;
    try {
      page = await queryPage(exclusiveStartKey);
    } catch (error) {
      report.failures.push(failure('query', 0, error));
      break;
    }

    const items = page.Items || [];
    for (let offset = 0; offset < items.length; offset += 25) {
      const batch = items.slice(offset, offset + 25).map(deleteRequestFor);
      const batchReport = await deleteBatchWithRetries({
        tableName,
        requests: batch,
        batchWrite,
        wait,
      });
      report.deletedCount += batchReport.deletedCount;
      report.failures.push(...batchReport.failures);
    }

    exclusiveStartKey = page.LastEvaluatedKey;
    if (exclusiveStartKey) {
      const serializedKey = JSON.stringify(exclusiveStartKey);
      if (seenKeys.has(serializedKey)) {
        report.failures.push(
          failure('query', 0, 'DynamoDB returned a repeated LastEvaluatedKey'),
        );
        break;
      }
      seenKeys.add(serializedKey);
    }
  } while (exclusiveStartKey);

  return {
    ...report,
    complete: report.failures.length === 0,
  };
}

function transactionSortKey(transaction, fallbackTimestamp = new Date().toISOString()) {
  const sourceTimestamp = transaction?.timestamp ?? fallbackTimestamp;
  const timestamp =
    typeof sourceTimestamp === 'number' ||
    (typeof sourceTimestamp === 'string' && /^\d+$/.test(sourceTimestamp))
      ? new Date(Number(sourceTimestamp))
      : new Date(sourceTimestamp);
  const canonicalTimestamp = Number.isNaN(timestamp.getTime())
    ? fallbackTimestamp
    : timestamp.toISOString();
  return `TXN#${canonicalTimestamp}#${encodeURIComponent(String(transaction.id))}`;
}

module.exports = {
  InvalidPaginationRequestError,
  decodeCursor,
  deleteUserPartition,
  encodeCursor,
  listTransactions,
  parseTransactionLimit,
  transactionSortKey,
};
