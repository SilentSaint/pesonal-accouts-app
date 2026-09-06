const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const directory = process.argv[2];
const { lambdas } = JSON.parse(fs.readFileSync(path.join(directory, 'plan-review.json'), 'utf8'));
if (!Array.isArray(lambdas) || lambdas.length === 0) throw new Error('No candidate Lambda identities');
const verified = [];
for (const lambda of lambdas) {
  const actual = JSON.parse(execFileSync('aws', [
    'lambda', 'get-function-configuration', '--function-name', lambda.name,
    '--region', 'ap-south-2',
    '--query', '{CodeSha256:CodeSha256,State:State,LastUpdateStatus:LastUpdateStatus}', '--output', 'json',
  ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] }));
  if (actual.CodeSha256 !== Buffer.from(lambda.sha256, 'hex').toString('base64')) {
    throw new Error(`Lambda ${lambda.name} does not match the candidate archive`);
  }
  if (actual.State !== 'Active' || actual.LastUpdateStatus !== 'Successful') {
    throw new Error(`Lambda ${lambda.name} is not ready`);
  }
  verified.push({ ...lambda, state: actual.State, lastUpdateStatus: actual.LastUpdateStatus });
}
fs.writeFileSync(path.join(directory, 'verified-lambdas.json'), `${JSON.stringify(verified, null, 2)}\n`, {
  mode: 0o600,
});
