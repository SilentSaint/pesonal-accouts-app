# Hosted CI retirement record

This file is retained as a historical record for the AWS-hosted validation
experiment described in issue #135. That experiment is no longer the active
verification path. The repository no longer contains a CodeBuild buildspec,
GitHub Actions workflows, or a hosted `scripts/ci/verify` entry point.

The active path is documented in
[`local-verification.md`](local-verification.md). It runs the complete Java,
Node Lambda, Terraform, Flutter, and Playwright checks on the developer machine
or inside the pinned local Docker toolchain. It does not require CodeCommit,
CodeBuild, GitHub Actions, or AWS credentials.

Production deployment remains a separate, explicitly invoked AWS operation. A
local validation run must not apply Terraform, publish S3 objects, update
Lambda code, or invalidate CloudFront. Hosted AWS resources are retired only
after a live inventory and an owner-reviewed deletion allowlist; removing these
source files does not delete those resources by itself.
