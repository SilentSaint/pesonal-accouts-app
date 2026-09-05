const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { existsSync, readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const lambdaDirectory = path.resolve(__dirname, '..');
const archive = path.join(lambdaDirectory, 'lambda.zip');
const packagedSources = [
  'analytics_reports.js',
  'auth_identity.js',
  'dynamodb_pagination.js',
  'gmail_scan_query.js',
  'index.js',
  'runtime_config.js',
  'websocket_authorizer.js',
  'websocket_sync.js',
];

test('Lambda archive is built through the checked-in packaging script', () => {
  const buildScript = path.join(lambdaDirectory, 'build.sh');
  assert.equal(existsSync(buildScript), true);
  assert.doesNotThrow(() => execFileSync(buildScript, ['--check']));
});

test('deployed Lambda archive contains exactly the reviewed handler sources', () => {
  assert.equal(existsSync(archive), true);

  const archiveEntries = execFileSync('unzip', ['-Z', '-1', archive], {
    encoding: 'utf8',
  }).trim().split('\n').sort();
  assert.deepEqual(archiveEntries, packagedSources);

  for (const source of packagedSources) {
    const archivedSource = execFileSync('unzip', ['-p', archive, source]);
    assert.deepEqual(
      archivedSource,
      readFileSync(path.join(lambdaDirectory, source)),
      `${source} in the deployment artifact differs from its reviewed source`,
    );
  }
});
