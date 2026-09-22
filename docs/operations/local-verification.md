# Local verification contract

Local verification is the canonical non-mutating validation path for this
personal project. It uses one pinned Docker toolchain and one local verifier;
it does not require CodeBuild, CodeCommit, GitHub Actions, or AWS credentials.

The image contains:

- Java 21
- Node 20.20.2
- Flutter 3.44.0
- Terraform 1.5.7
- Playwright 1.47.2

## Run it

From the repository root, build the image and run the complete lane:

```bash
scripts/ci/verify-local-docker --pull
```

After the first successful build, reuse the image during iteration:

```bash
scripts/ci/verify-local-docker --no-build \
  --log-file /tmp/aet-local-ci-verify.log
```

The wrapper uses `ci/local-verification/Dockerfile`, mounts the checkout at
`/workspace`, and runs as the invoking user. It resolves the worktree Git
directory and common directory, mounts the common directory read-only at its
original absolute path, and leaves build/test output in the checkout. It does
not export a global `GIT_DIR`, so tools that inspect their own checkout retain
normal Git discovery.
The wrapper is Git worktree-safe.

The wrapper handles a stale Docker supplementary-group session. If the account
belongs to `docker` but the current process does not yet have that membership,
it re-executes itself once through `sg docker` with the original arguments.
This does not add a user to the group or grant a new account privilege.

Use the direct verifier when the pinned tools are already installed locally:

```bash
scripts/ci/verify-local
```

The verifier covers the complete local lane:

1. Java tests and Java Lambda packaging;
2. Node Lambda archive build/parity tests and Node tests;
3. Terraform formatting, backend-free initialization, and validation;
4. Flutter dependency resolution, analysis, tests, and release web build; and
5. Playwright browser verification using an installed Chromium when available.

It also runs the non-mutating production-guard contract test. A non-zero exit
means the local gate is not green; retain the log and fix or triage the
reported test before treating the revision as validated.

## Safety boundary

The Docker wrapper explicitly supplies empty AWS credential variables, points
the AWS config and credential files at `/dev/null`, and disables EC2 metadata
lookup. No host credential directory is mounted. Terraform is limited to
`fmt`, `init -backend=false`, and `validate`; the local gate never runs
`terraform apply`, publishes S3 objects, updates Lambda code, or invalidates
CloudFront.

The local gate is deliberately separate from the owner-approved production
release path. The manual release wrapper runs the complete local gate before
identity checks or deployment, while post-merge release and hosted validation
consumers are not prerequisites for local development.

## Migration boundaries

The D1 comparison preserved the Java, Lambda, Terraform, Flutter, and browser
validation lanes that were previously hosted. Local execution does not emit
CodeBuild reports or invoke EventBridge, auto-merge, failure-notification, or
post-merge release consumers. A disposable DynamoDB Local integration lane is
not part of this verifier; if one becomes part of the local contract, add it to
`scripts/ci/verify-local` and its contract tests together.

D2 is the local Docker parity gate. D3 is the owner-approved local release
parity boundary. Neither changes deployed AWS resources during validation, and
the decommissioned hosted source files do not by themselves delete any hosted
AWS resource.
