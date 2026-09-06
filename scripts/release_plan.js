const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');

const [directory, ...targets] = process.argv.slice(2);
const root = path.resolve(directory, '../../..');
const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'manifest.json'), 'utf8'));
function refuse(reason) {
  throw new Error(`Unsafe release plan: ${reason}. Stop for a separately reviewed owner decision.`);
}
let plan;
try {
  plan = JSON.parse(fs.readFileSync(path.join(directory, 'terraform-plan.json'), 'utf8'));
} catch (error) {
  if (error instanceof SyntaxError) refuse('invalid private plan JSON; inspect the private evidence');
  throw error;
}
if (!plan.format_version?.startsWith('1.') || plan.errored || plan.complete === false) {
  refuse('unsupported, errored or incomplete plan');
}
if (plan.variables?.aws_region?.value !== 'ap-south-2' || plan.variables?.environment?.value !== 'dev') {
  refuse('region/environment must remain ap-south-2/dev for the existing production-used stack');
}
const outputs = Object.fromEntries([
  'api_gateway_url', 'websocket_sync_url', 's3_web_bucket_name',
  'cloudfront_distribution_id', 'cloudfront_web_url',
].map((name, index) => [name, targets[index]]));
for (const [name, expected] of Object.entries(outputs)) {
  if (!expected || plan.planned_values?.outputs?.[name]?.value !== expected
    || plan.output_changes?.[name]?.after_unknown === true) {
    refuse(`deployment target ${name} changed, is missing or unknown`);
  }
}
const changes = [];
if (!Array.isArray(plan.resource_changes)) refuse('resource changes are unavailable');
for (const resource of plan.resource_changes) {
  const { actions, before, after } = resource.change;
  if (actions.length !== 1 || !['no-op', 'read', 'create', 'update'].includes(actions[0])) {
    refuse(`destructive or replacement action for ${resource.address}`);
  }
  if (resource.type.startsWith('aws_cloudwatch_') && resource.type.endsWith('_alarm')
    && actions.includes('create')) refuse(`new alarm ${resource.address}`);
  if (!actions.includes('no-op')) {
    const fields = [...new Set([...Object.keys(before || {}), ...Object.keys(after || {})])]
      .filter((key) => JSON.stringify(before?.[key]) !== JSON.stringify(after?.[key])).sort();
    changes.push({ address: resource.address, actions, fields });
    console.log(`${resource.address}: ${actions.join(', ')}; changed fields: ${fields.join(', ')}`);
  }
}
function resources(module) {
  return [...(module?.resources || []), ...(module?.child_modules || []).flatMap(resources)];
}
const archives = new Map([
  [path.join(root, 'backend/lambda/lambda.zip'), manifest.nodeSha256],
  [path.join(root, 'backend/build/lambda/transaction-command-lambda.zip'), manifest.javaSha256],
]);
const lambdas = resources(plan.planned_values?.root_module)
  .filter((resource) => resource.mode === 'managed' && resource.type === 'aws_lambda_function')
  .map((resource) => {
    const values = resource.values;
    const hash = typeof values?.filename === 'string'
      && archives.get(path.resolve(root, 'terraform', values.filename));
    if (!hash || values.source_code_hash !== Buffer.from(hash, 'hex').toString('base64')
      || !/^[A-Za-z0-9_-]{1,64}$/.test(values.function_name || '')) {
      refuse(`Lambda ${resource.address} is not bound to a checked candidate archive`);
    }
    return { name: values.function_name, sha256: hash };
  });
if (![manifest.nodeSha256, manifest.javaSha256].every((hash) => lambdas.some((lambda) => lambda.sha256 === hash))) {
  refuse('both checked Lambda archives must be represented in the planned deployment');
}
const review = {
  planSha256: createHash('sha256').update(fs.readFileSync(path.join(directory, 'terraform.plan'))).digest('hex'),
  outputs,
  changes,
  lambdas,
};
fs.writeFileSync(path.join(directory, 'plan-review.json'), `${JSON.stringify(review, null, 2)}\n`, {
  flag: 'wx', mode: 0o600,
});
console.log('Saved plan passed the non-destructive, stable-target release policy (values redacted).');
