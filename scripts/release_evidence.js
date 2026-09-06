const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { createHash } = require('node:crypto');

const [command, directory, ...args] = process.argv.slice(2);
function write(name, value, flag = 'w') {
  fs.writeFileSync(path.join(directory, name), `${JSON.stringify(value, null, 2)}\n`, { flag, mode: 0o600 });
}
if (command === 'source') {
  const [root, commit, leaseOwner] = args;
  execFileSync('git', ['-C', root, 'archive', '--format=tar', `--output=${directory}/source.tar`, commit]);
  write('source.json', {
    commit,
    tree: execFileSync('git', ['-C', root, 'rev-parse', `${commit}^{tree}`], { encoding: 'utf8' }).trim(),
    sourceSha256: createHash('sha256').update(fs.readFileSync(path.join(directory, 'source.tar'))).digest('hex'),
    leaseOwner,
  }, 'wx');
} else if (command === 'configuration') {
  const source = JSON.parse(fs.readFileSync(path.join(directory, 'source.json')));
  write('provenance.json', {
    ...source, account: process.env.AWS_ACCOUNT_ID, role: process.env.AWS_DEPLOY_ROLE_ARN,
    region: process.env.AWS_REGION, environment: 'dev',
    apiBaseUrl: process.env.API_BASE_URL, websocketUrl: process.env.WEBSOCKET_SYNC_URL,
  }, 'wx');
} else if (command === 'status') {
  const [status, phase, exitCode = '0'] = args;
  if (!['preparing', 'prepared', 'failed', 'verified'].includes(status)) throw new Error('Invalid release status');
  const event = { status, phase, exitCode: Number(exitCode), at: new Date().toISOString() };
  fs.appendFileSync(path.join(directory, 'events.jsonl'), `${JSON.stringify(event)}\n`, { mode: 0o600 });
  write('status.json', event);
} else {
  throw new Error('Unknown release evidence command');
}
