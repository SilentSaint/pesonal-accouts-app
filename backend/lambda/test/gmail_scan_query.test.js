const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const Module = require('node:module');
const path = require('node:path');
const test = require('node:test');

const lambdaDirectory = path.resolve(__dirname, '..');
const archive = path.join(lambdaDirectory, 'lambda.zip');
const deployedModule = new Module(path.join(lambdaDirectory, 'gmail_scan_query.js'));
deployedModule.filename = path.join(lambdaDirectory, 'gmail_scan_query.js');
deployedModule.paths = Module._nodeModulePaths(lambdaDirectory);
deployedModule._compile(
  execFileSync('unzip', ['-p', archive, 'gmail_scan_query.js'], { encoding: 'utf8' }),
  deployedModule.filename,
);
const { buildGmailScanRequest } = deployedModule.exports;

test('a bounded Gmail scan in the deployment artifact preserves its requested Unix-second window', () => {
  const request = buildGmailScanRequest(
    'from:alerts@bank.example',
    {
      afterTimestamp: 1724889600,
      beforeTimestamp: 1724976000,
      maxResults: 250,
    },
  );

  assert.deepEqual(request, {
    query: 'after:1724889600 before:1724976000 from:alerts@bank.example',
    maxResults: 250,
  });
});

test('the deployment artifact defaults unbounded Gmail scans to a 30-day lookback', () => {
  const request = buildGmailScanRequest('', {}, 1727568000000);

  assert.deepEqual(request, {
    query: 'after:1724976000 (alert OR statement OR debited OR credited OR transaction OR "spent" OR "bill" OR "card" OR "vpa" OR "upi" OR "inr" OR "rs")',
    maxResults: 500,
  });
});
