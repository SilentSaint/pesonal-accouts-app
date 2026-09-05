const assert = require('node:assert/strict');
const test = require('node:test');

const {
  decodeCursor,
  deleteUserPartition,
  encodeCursor,
  listTransactions,
  transactionSortKey,
} = require('../dynamodb_pagination');

test('transaction sort keys order newer timestamps first with descending DynamoDB queries', () => {
  const older = transactionSortKey({
    id: 'txn-a',
    timestamp: 1724911200000,
  });
  const newer = transactionSortKey({
    id: 'txn-b',
    timestamp: 1724911260000,
  });

  assert.equal(older, 'TXN#2024-08-29T06:00:00.000Z#txn-a');
  assert.equal(newer, 'TXN#2024-08-29T06:01:00.000Z#txn-b');
  assert.ok(newer > older);
});

test('transaction pagination cursor is opaque and bound to the authenticated partition', () => {
  const cursor = encodeCursor({
    PK: 'USER#owner',
    SK: 'TXN#2024-08-29T06:00:00.000Z#txn-a',
  });

  assert.match(cursor, /^[A-Za-z0-9_-]+$/);
  assert.deepEqual(decodeCursor(cursor, 'USER#owner'), {
    PK: 'USER#owner',
    SK: 'TXN#2024-08-29T06:00:00.000Z#txn-a',
  });
  assert.throws(
    () => decodeCursor(cursor, 'USER#another-user'),
    /cursor is invalid/,
  );
});

test('transaction history follows LastEvaluatedKey until the requested result is complete', async () => {
  const queryRequests = [];
  const pages = [
    {
      Items: [{ data: { id: 'newest' } }],
      LastEvaluatedKey: { PK: 'USER#owner', SK: 'TXN#2026-08-29T12:01:00.000Z#newest' },
    },
    {
      Items: [{ data: { id: 'older' } }],
    },
  ];

  const result = await listTransactions({
    limit: 2,
    queryPage: async (request) => {
      queryRequests.push(request);
      return pages.shift();
    },
  });

  assert.deepEqual(result.items.map((item) => item.id), ['newest', 'older']);
  assert.deepEqual(queryRequests, [
    { limit: 2, exclusiveStartKey: undefined },
    {
      limit: 1,
      exclusiveStartKey: {
        PK: 'USER#owner',
        SK: 'TXN#2026-08-29T12:01:00.000Z#newest',
      },
    },
  ]);
  assert.equal(result.lastEvaluatedKey, undefined);
});

test('cloud reset consumes every query page and retries unprocessed batch deletes', async () => {
  const items = Array.from({ length: 27 }, (_, index) => ({
    PK: 'USER#owner',
    SK: `TXN#2026-08-29T12:00:${String(index).padStart(2, '0')}.000Z#${index}`,
  }));
  const queryRequests = [];
  const batches = [];
  let queryPage = 0;
  let firstBatchAttempt = true;

  const report = await deleteUserPartition({
    tableName: 'ExpenseTrackerData',
    queryPage: async (exclusiveStartKey) => {
      queryRequests.push(exclusiveStartKey);
      if (queryPage++ === 0) {
        return {
          Items: items.slice(0, 25),
          LastEvaluatedKey: items[24],
        };
      }
      return { Items: items.slice(25) };
    },
    batchWrite: async (requestItems) => {
      batches.push(requestItems);
      if (firstBatchAttempt) {
        firstBatchAttempt = false;
        return { UnprocessedItems: { ExpenseTrackerData: [requestItems[0]] } };
      }
      return { UnprocessedItems: {} };
    },
    wait: async () => {},
  });

  assert.deepEqual(queryRequests, [undefined, items[24]]);
  assert.equal(report.deletedCount, 27);
  assert.deepEqual(report.failures, []);
  assert.deepEqual(batches.map((batch) => batch.length), [25, 1, 2]);
});
