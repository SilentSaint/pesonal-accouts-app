const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');

function sha256(file) {
  return createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function webFingerprint(directory, prefix = '') {
  const entries = [];
  for (const name of fs.readdirSync(directory).sort()) {
    const relative = `${prefix}${name}`;
    const file = path.join(directory, name);
    const stat = fs.lstatSync(file);
    if (relative === 'deployment-version.json') {
      if (!stat.isFile()) throw new Error(`Unsupported release asset: ${relative}`);
      continue;
    }
    if (stat.isDirectory()) {
      entries.push(...webFingerprint(file, `${relative}/`));
    } else if (stat.isFile()) {
      entries.push(`${relative}\0${sha256(file)}\n`);
    } else {
      throw new Error(`Unsupported release asset: ${relative}`);
    }
  }
  return entries;
}

const archives = [
  ['nodeSha256', 'backend/lambda/lambda.zip', 'node.zip'],
  ['javaSha256', 'backend/build/lambda/transaction-command-lambda.zip', 'java.zip'],
  ['apkSha256', 'frontend/build/app/outputs/flutter-apk/app-debug.apk', 'app-debug.apk'],
];
function webSha256(directory) {
  return createHash('sha256').update(webFingerprint(directory).join('')).digest('hex');
}

function readiness(root, group) {
  if (group === 'web') return { webSha256: webSha256(path.join(root, 'frontend/build/web')) };
  if (group === 'lambda') {
    return Object.fromEntries(archives.slice(0, 2).map(([key, source]) => [key, sha256(path.join(root, source))]));
  }
  throw new Error('Unknown readiness artifact group');
}

function checkReadiness(root, group) {
  const recorded = JSON.parse(fs.readFileSync(path.join(root, 'dev_builds/readiness', `${group}.json`), 'utf8'));
  if (JSON.stringify(recorded) !== JSON.stringify(readiness(root, group))) {
    throw new Error(`Checked ${group} artifact changed since readiness`);
  }
}

if (['snapshot', 'check-readiness'].includes(process.argv[2])) {
  const [command, root, group] = process.argv.slice(2);
  if (command === 'snapshot') {
    const directory = path.join(root, 'dev_builds/readiness');
    fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
    fs.writeFileSync(path.join(directory, `${group}.json`), JSON.stringify(readiness(root, group)), { mode: 0o600 });
  } else {
    checkReadiness(root, group);
  }
  process.exit(0);
}

if (process.argv[2] === 'verify-artifacts') {
  const [root, directory] = process.argv.slice(3);
  const marker = JSON.parse(fs.readFileSync(path.join(directory, 'manifest.json'), 'utf8'));
  for (const [key, source, destination] of archives) {
    if (marker[key] !== sha256(path.join(root, source))
      || marker[key] !== sha256(path.join(directory, destination))) {
      throw new Error(`Candidate artifact changed: ${destination}`);
    }
  }
  if (marker.webSha256 !== webSha256(path.join(root, 'frontend/build/web'))
    || marker.webSha256 !== webSha256(path.join(directory, 'web'))
    || fs.readFileSync(path.join(directory, 'manifest.json'), 'utf8')
      !== fs.readFileSync(path.join(directory, 'web/deployment-version.json'), 'utf8')) {
    throw new Error('Candidate web artifact changed');
  }
  process.exit(0);
}

if (process.argv[2] === 'verify-version') {
  const expected = JSON.parse(fs.readFileSync(path.join(process.argv[3], 'manifest.json'), 'utf8'));
  let actual;
  try {
    actual = JSON.parse(fs.readFileSync(0, 'utf8'));
  } catch (error) {
    if (error instanceof SyntaxError) throw new Error('Published release marker is not valid JSON');
    throw error;
  }
  if (!actual || typeof actual !== 'object'
    || Object.entries(expected).some(([key, value]) => actual[key] !== value)) {
    throw new Error('Published release marker does not match the candidate artifacts');
  }
  process.exit(0);
}

const [rootArgument, commit, preparedDirectory] = process.argv.slice(2);
if (!rootArgument || !/^[a-f0-9]{40}$/.test(commit || '')) {
  throw new Error('Release artifacts require a source root and full Git commit SHA');
}
const root = fs.realpathSync(rootArgument);
checkReadiness(root, 'lambda');
checkReadiness(root, 'web');
const webSource = path.join(root, 'frontend/build/web');
if (!fs.statSync(path.join(webSource, 'index.html')).isFile()) {
  throw new Error('The candidate web build must contain index.html');
}
const releases = path.join(root, 'dev_builds/releases');
fs.mkdirSync(releases, { recursive: true, mode: 0o700 });
const directory = preparedDirectory || fs.mkdtempSync(path.join(releases, `${commit}-`));
const marker = {
  schemaVersion: 1,
  commit,
  releaseId: path.basename(directory),
};
for (const [key, source, destination] of archives) {
  const archived = path.join(directory, destination);
  fs.copyFileSync(path.join(root, source), archived, fs.constants.COPYFILE_EXCL);
  marker[key] = sha256(archived);
}
const web = path.join(directory, 'web');
fs.cpSync(webSource, web, { recursive: true });
marker.webSha256 = webSha256(web);
for (const group of ['lambda', 'web']) {
  const recorded = JSON.parse(fs.readFileSync(path.join(root, 'dev_builds/readiness', `${group}.json`), 'utf8'));
  if (Object.entries(recorded).some(([key, value]) => marker[key] !== value)) {
    throw new Error(`Checked ${group} artifact changed during archival`);
  }
}
const json = `${JSON.stringify(marker, null, 2)}\n`;
fs.writeFileSync(path.join(directory, 'manifest.json'), json, { flag: 'wx', mode: 0o600 });
fs.writeFileSync(path.join(web, 'deployment-version.json'), json, { mode: 0o600 });
process.stdout.write(directory);
