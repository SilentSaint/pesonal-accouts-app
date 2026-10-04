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
scripts/ci/verify-local-docker --pull \
  --cache-dir /path/to/persistent/aet-local-verification-cache
```

After the first successful build, reuse the image during iteration:

```bash
scripts/ci/verify-local-docker --no-build \
  --cache-dir /path/to/persistent/aet-local-verification-cache \
  --log-file /path/to/aet-local-ci-verify.log
```

Run the cheap preflight before an expensive lane when setting up a new host:

```bash
scripts/ci/verify-local-docker --preflight-only \
  --cache-dir /path/to/persistent/aet-local-verification-cache
```

The wrapper uses `ci/local-verification/Dockerfile` and runs as the invoking
user. After preflight it captures `HEAD` and creates a detached Git worktree at
that exact revision. Docker builds from this snapshot and mounts it at
`/workspace`; the invoking checkout itself is never mounted. Build/test output
is isolated in the temporary snapshot, which is removed when the verifier
exits. At launch, the wrapper clears inherited Git repository-selection
variables (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR`, and `GIT_INDEX_FILE`)
so revision discovery and cleanliness checks always refer to the checkout
containing the script. The wrapper resolves the snapshot's Git directory and
common directory, mounts the common directory read-only at its original
absolute path, and does not export a global `GIT_DIR`, so tools that inspect
their own checkout retain normal Git discovery.
The wrapper is Git worktree-safe and forwards the invoking user's
non-primary supplementary groups so group-owned cache mounts remain writable
inside the container.
After a successful container run, it rejects tracked changes or non-ignored
untracked files left in the detached snapshot before reporting the revision as
validated.

The host-side preflight also requires `curl` and checks HTTPS reachability for
the runtime dependency sources: Gradle, Maven Central, Terraform Registry and
releases, pub.dev, and npm Registry. When building the image, it additionally
checks the image/toolchain sources and at least one pinned Playwright Chromium
CDN mirror. With `--no-build`, image-only sources and the browser CDN are
skipped, while runtime dependency sources remain checked. This catches common
DNS, proxy, and outbound-network setup problems early; it is only a host
reachability check, so downloads inside Docker can still fail and use the
bounded retry policy below.

Before building or running a container, the wrapper verifies that the checkout
has no tracked changes or non-ignored untracked files, the Dockerfile exists,
the cache directory and mounted cache children are writable and searchable,
their resolved paths remain beneath the selected cache directory, the cache
filesystem has at least 2 GB free by default, and `docker info` succeeds.
Cache-child symlinks that escape the selected cache directory are rejected
before Docker access. Ignored generated build output is allowed;
source, test, Terraform, and other non-ignored untracked files are rejected so
the reported revision matches the mounted checkout. If the account belongs to
`docker` but the current process does not
yet have that membership, it attempts one `sg docker` re-exec; if that cannot
be acquired, it stops before any image build and tells the operator to start a
new login session or use a process with Docker group membership. This does not
add a user to the group or grant a new account privilege.
The gate reports the captured `HEAD` revision. Changes to the invoking checkout
after preflight cannot change the bytes being validated, because the image build
and container use the detached snapshot. Log destinations must also resolve
outside the checkout so opening a log cannot make the checkout dirty before the
clean-worktree check.

The default cache is a sibling directory next to the checkout, rather than
the small `/tmp` filesystem. The cache volume persists Gradle, Terraform
provider/data, Flutter pub, and npm downloads across clean-checkout runs. Use
`--cache-dir` when the checkout is on a small or quota-limited filesystem. The
relative cache paths resolve beside the checkout, never inside it; an absolute
path inside the checkout is rejected before the cache is created. The wrapper
reports the selected path and free space in its log. Terraform working
directory data uses a unique per-run directory under the persistent cache at
`/cache/terraform/data` and is removed when the container exits, so it does not
consume the container's quota-limited `/tmp`. The persistent provider cache is
protected by a lock held only during `terraform init`; concurrent verifier runs
can execute the other validation lanes in parallel without racing on
Terraform's non-concurrency-safe provider cache. Preflight creates and checks
each mounted cache directory, including the Terraform data parent and detached-
worktree parent, and the lock file before Docker builds or starts a container.

The wrapper records elapsed time from before host preflight through container
completion, including failures and `--preflight-only` runs.

Dependency acquisition has three bounded attempts with a two-second linear
backoff by default. The retry helper normalizes decimal environment values,
allows at most 10 attempts, and caps the delay at
`922337203685477580` seconds so backoff multiplication remains safe. Override
these for a controlled diagnostic with `LOCAL_VERIFIER_RETRY_ATTEMPTS` and
`LOCAL_VERIFIER_RETRY_DELAY_SECONDS`. The Docker wrapper validates the same
bounds during preflight, before it starts a container. Gradle distribution and dependency
resolution are retried before the test and packaging commands. A test dry run
also resolves test runtime artifacts under the retry policy; actual test
execution remains single-shot.
The wrapper also records the final verification status and duration.

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
lookup by AWS SDK/CLI credential providers using
AWS_EC2_METADATA_DISABLED=true. No host credential directory is mounted.
The Docker environment does not add a network-level block: raw HTTP requests
to IMDS are not filtered, and outbound network access remains available for
dependency acquisition. Do not treat the container as an isolation boundary
for untrusted code. Terraform is limited to
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
