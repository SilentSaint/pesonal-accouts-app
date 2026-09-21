# Hosted CI decommission allowlist

Snapshot taken on 2026-09-21 in account `727118420276`, region
`ap-south-2`. This is an owner-review record, not an apply plan. No AWS
resources were deleted by the local migration work.

## Findings

The hosted validation resources are not managed by this repository's
Terraform. A search of `terraform/` found application runtime roles and
resources, but no CodeBuild, CodeCommit, CodePipeline, or hosted-CI IAM
resources. The following inventory was obtained from the live AWS account:

- Four CodeBuild projects, all sourced from the CodeCommit repository
  `arn:aws:codecommit:ap-south-2:727118420276:pesonal-accouts-app`:
  - `automatic-expense-tracker-pr-validation`
  - `automatic-expense-tracker-pr-validation-batch-canary`
  - `automatic-expense-tracker-toolchain-builder`
  - `automatic-expense-tracker-post-merge-release`
- Four CloudWatch log groups, each with 14-day retention:
  - `/aws/codebuild/automatic-expense-tracker-pr-validation`
  - `/aws/codebuild/automatic-expense-tracker-pr-validation-batch-canary`
  - `/aws/codebuild/automatic-expense-tracker-toolchain-builder`
  - `/aws/codebuild/automatic-expense-tracker-post-merge-release`
- One dedicated ECR repository:
  `arn:aws:ecr:ap-south-2:727118420276:repository/automatic-expense-tracker-toolchain`.
  Its active image is about 2.75 GB and was pulled on 2026-09-21.
- The CodeCommit repository has 92 branches and one open pull request (`112`).
  Its `main` commit is `f97dcd85e88d649167aa0ba557b62052f86ae706`.

The latest observed builds were terminal: the post-merge release was
`FAILED`, while PR validation, the batch canary, and the toolchain builder were
`SUCCEEDED`. A final `IN_PROGRESS` check is still required immediately before
any deletion.

## Candidate deletion set: validation-only resources

Delete only after the local gate is accepted and no hosted validation run is
needed for the remaining CodeCommit PR/branch reconciliation:

1. CodeBuild projects:
   - `automatic-expense-tracker-pr-validation`
   - `automatic-expense-tracker-pr-validation-batch-canary`
   - `automatic-expense-tracker-toolchain-builder`
2. Their CodeBuild roles and only their policies:
   - `automatic-expense-tracker-codebuild-toolchain`
     - inline `CodeCommitLogsAndEcrPull`
   - `automatic-expense-tracker-codebuild-toolchain-builder`
     - inline `CodeCommitLogsAndEcrPush`
   - `automatic-expense-tracker-codebuild-batch-validation-canonical`
     - inline `RunOnlyCanonicalValidationChildBuilds`
   - `automatic-expense-tracker-codebuild-batch-validation`
     - inline `RunOnlyCanaryChildBuilds`
   - legacy role `automatic-expense-tracker-codebuild-validation`
     - inline `CodeCommitReadAndBuildLogs`
3. The three corresponding CodeBuild log groups.
4. The dedicated toolchain ECR repository and its image, only after all
   CodeBuild project references are removed.

The managed policy
`arn:aws:iam::727118420276:policy/automatic-expense-tracker-post-merge-release-e2e-secret`
is not in this validation-only set; it belongs to the release role below.

## Candidate deletion set: hosted release resources

This is a separate, higher-risk cutover because it disables automatic
production delivery and the associated failure notification:

1. CodeBuild project `automatic-expense-tracker-post-merge-release`.
2. EventBridge rule
   `automatic-expense-tracker-post-merge-release-main-update` and its target
   `post-merge-release-codebuild`.
3. EventBridge role
   `automatic-expense-tracker-post-merge-release-eventbridge` and inline
   policy `automatic-expense-tracker-post-merge-release-start-build`.
4. CodeBuild role
   `automatic-expense-tracker-post-merge-release`, its inline policies
   `automatic-expense-tracker-post-merge-release-e2e-secret` and
   `PostMergeReleaseExecution`, and its uniquely attached managed policy
   `automatic-expense-tracker-post-merge-release-e2e-secret`.
5. The post-merge CodeBuild log group.
6. EventBridge rule `automatic-expense-tracker-failure-notifications`.

Do not delete the SNS topic `budget-spending-alerts-dev`: the failure rule
targets it, but the topic may be shared with budget notifications.

## Explicitly retained

Retain the CodeCommit repository, its branches, and PR `112` until the source
reconciliation is complete. Deleting the repository now would destroy 92
branches and an open change that has not been migrated to the local/GitHub
workflow.

Retain role
`automatic-expense-tracker-terraform-release` and managed policy
`arn:aws:iam::727118420276:policy/AutomaticExpenseTrackerTerraformE2EPolicy`.
The role is trusted only by the post-merge role and carries owner-controlled
Terraform deployment capability; a replacement manual deployment path must be
validated before changing it.

## Required deletion preflight

Before any AWS mutation, re-read the live inventory and verify:

1. no CodeBuild execution for a candidate project is `IN_PROGRESS`;
2. no EventBridge target still references a retained project;
3. no IAM policy in the candidate set is attached to a non-candidate role;
4. the CodeCommit PR/branch migration decision is recorded; and
5. the exact deletion order is reviewed: event targets/rules, projects,
   log groups/ECR, then IAM policies and roles.

The local verification path is
[local-verification.md](local-verification.md). It is non-mutating and does
not replace the owner-controlled production deployment decision.
