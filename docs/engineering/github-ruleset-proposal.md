# Proposed GitHub ruleset and deployment guardrails

Do not activate these settings until the baseline-reconciliation owner confirms
that the reconciled `main` is clean and all intended checks are green.

## Ruleset for `main`

Create a branch ruleset targeting `refs/heads/main` with:

- Require a pull request before merging; require at least one approval if another
  maintainer is available.
- Require the `Pull request validation` checks that are green on the reconciled
  baseline. Initially exclude Lambda and Playwright until their sources exist.
- Require the branch to be up to date before merging.
- Require all review conversations to be resolved.
- Block force pushes and branch deletion.
- Enable a merge queue or serialize merges when the repository plan supports it.
- Configure the repository owner as the only documented emergency bypass actor;
  log and immediately review every bypass.

Avoid policies that prevent the owner from recovering a solo-owner repository.
Do not require unavailable checks and do not enable a deployment workflow as a
required PR check.

## Manual owner checklist

1. Confirm the baseline branch has been reconciled, merged, and tested from a
   clean checkout.
2. Confirm every required check has completed successfully on that exact `main`
   SHA.
3. Create the ruleset above in **Settings → Rules → Rulesets** and apply it only
   to `main`.
4. Add the repository owner to the documented bypass list; do not enable a broad
   administrator bypass.
5. Create a protected `production` environment. Require the owner (or designated
   release reviewer) to approve deployments and scope its secrets to that
   environment.
6. Configure an AWS IAM role trusted by GitHub Actions OIDC for this repository,
   branch, and production environment. Grant only deployment permissions needed
   by the final deployment design.
7. After a trial deployment, verify that the release record contains the deployed
   Git SHA and a post-deployment smoke-test result.

## Future deployment workflow design

The deployment workflow should trigger only after a commit has landed on `main`
or through a manually approved rollback SHA that is already contained in `main`.
It checks out that immutable SHA, builds it from scratch, obtains short-lived AWS
credentials through OIDC, and uses a `production` concurrency group with no
parallel execution. It records the SHA in the GitHub deployment metadata and
the release log, then runs production smoke tests.

For rollback, the owner selects a previously verified SHA. The workflow proves
that SHA is reachable from `main`, redeploys it through the same environment and
OIDC controls, and records both the rollback SHA and smoke-test outcome. No PR,
local checkout, long-lived access key, or Terraform state file may initiate a
production deployment.
