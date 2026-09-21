# Local verification contract

The local Docker gate is the reproducible validation path for this personal
project. It uses the same public verifier as the hosted validation build, but
provides the pinned toolchain in a clean image:

- Java 21
- Node 20.20.2
- Flutter 3.44.0
- Terraform 1.5.7
- Playwright 1.47.2

## Run it

From a clean checkout, build the image and run the full lane:

```bash
scripts/ci/verify-local-docker --pull
```

After the first successful build, reuse the image during iteration:

```bash
scripts/ci/verify-local-docker --no-build
```

The repository is mounted at `/workspace`, so test and build output remains in
the checkout. The image itself contains the expensive toolchain setup. Native
commands such as `./backend/gradlew -p backend test`, `flutter test`, and
`terraform validate` remain appropriate for fast inner-loop iteration; the
Docker command is the clean-environment gate before a push or release.

The wrapper is Git worktree-safe. Before starting the container, it resolves the
worktree's Git directory and common directory, mounts the common directory
read-only at its original absolute path. The container keeps Git's normal
checkout discovery instead of exporting a global `GIT_DIR`, so project Git
commands work while tools that inspect their own Git checkout (such as Flutter)
continue to see their own repository metadata.

The image makes only Flutter's SDK tool and cache directories writable during
the image build. Flutter may lazily rebuild its tool on the first validation
run, while the verifier itself runs as the invoking host user; repository files
remain owned by that user and the rest of the SDK stays unchanged at runtime.

`--pull` is intentionally opt-in so normal local runs reuse the cached base
image. `--no-build` fails if the named image is not already available. A
Docker build failure or a verifier failure exits non-zero and prevents the
container from being reported as successful; the wrapper does not retry,
publish artifacts, or continue to a deployment step.

## Safety boundary

The wrapper explicitly supplies empty AWS credential variables, points the AWS
config and credentials files at `/dev/null`, and disables EC2 metadata lookup.
The mounted checkout is used only for validation. The verifier runs Terraform
`init -backend=false` and `validate`; it does not run `terraform apply`, publish
to S3, update Lambda code, or invalidate CloudFront. The Docker image has no
production credentials and no release role.

The container needs ordinary outbound network access for dependency resolution
when a project cache is cold. That is dependency access, not authenticated
access to the project’s AWS resources. No host credential directory is mounted.

The wrapper also handles a common long-lived-session problem after Docker is
installed. It compares the account's supplementary groups with the current
process groups. When the account is already a member of `docker` but the
process predates that membership, it re-executes itself once through `sg docker`
with the original arguments preserved. This does not grant privileges or add a
user to the group; the one-time host setup remains `sudo usermod -aG docker
"$USER"`, followed by a new login session when needed. The recovery path is
reported by `--print-config` and is guarded against recursion.

## D1 hosted baseline parity

D1 found that the active hosted validation projects in `ap-south-2` converge on
`scripts/ci/verify`. The local contract therefore covers the same validation
lanes:

1. Java tests and Lambda packaging.
2. Lambda build/parity checks and Node tests.
3. Terraform formatting, backend-free initialization, and validation.
4. Flutter version check, dependency resolution, analysis, tests, and web build.
5. Browser end-to-end verification with Playwright.

The following differences are deliberate and belong to later roadmap issues:

- Local execution does not set `CODEBUILD_RESOLVED_SOURCE_VERSION`, so exact
  revision comparison remains D4’s same-revision comparator.
- Local execution does not emit CodeBuild reports or invoke EventBridge,
  auto-merge, failure-notification, or post-merge release consumers.
- The D3 owner-approved local release wrapper now runs this complete contract before
  any Terraform apply or artifact publication. The hosted release workflow remains
  available as a separate path until the D4/D5 hosted-comparator decisions.
- D1 found no DynamoDB local lane in the active CodeBuild baseline. If a
  disposable DynamoDB local integration lane is introduced, it must be added
  to `scripts/ci/verify` first so this Docker contract inherits it.
- CodeBuild’s remote cache and report storage are not reproduced locally. The
  image caches the toolchain; repository build output is retained by the
  mounted checkout, while transient container-home caches may be recreated.

No CodeBuild trigger, EventBridge rule, Lambda consumer, or production release
resource is changed by this contract.
