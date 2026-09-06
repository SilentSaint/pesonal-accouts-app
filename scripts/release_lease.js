const { execFileSync } = require('node:child_process');

const [command, owner, commit] = process.argv.slice(2);
if (!['acquire', 'check', 'release'].includes(command) || !owner) {
  throw new Error('Release lease requires acquire/check/release and an ownership token');
}
const key = { PK: { S: 'RELEASE#production' }, SK: { S: 'LEASE' } };
const shared = ['--table-name', 'ExpenseTrackerData', '--region', 'ap-south-2'];
function aws(operation, args) {
  return execFileSync('aws', ['dynamodb', operation, ...shared, ...args], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'],
  });
}
if (command === 'acquire') {
  if (!/^[a-f0-9]{40}$/.test(commit || '')) throw new Error('Release lease requires a source SHA');
  aws('put-item', [
    '--item', JSON.stringify({
      ...key, owner: { S: owner }, commit: { S: commit },
      acquiredAt: { S: new Date().toISOString() },
    }),
    '--condition-expression', 'attribute_not_exists(PK)',
  ]);
  console.log(`Release lease acquired: ${owner}`);
} else if (command === 'check') {
  const lease = JSON.parse(aws('get-item', [
    '--key', JSON.stringify(key), '--consistent-read', '--output', 'json',
  ]));
  if (lease.Item?.owner?.S !== owner) throw new Error('Release lease ownership changed or is missing');
} else {
  aws('delete-item', [
    '--key', JSON.stringify(key),
    '--condition-expression', '#owner = :owner',
    '--expression-attribute-names', JSON.stringify({ '#owner': 'owner' }),
    '--expression-attribute-values', JSON.stringify({ ':owner': { S: owner } }),
  ]);
}
