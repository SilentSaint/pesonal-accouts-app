# AWS development authentication

Use the refreshable profile bridge when working locally or when an agent needs
to call AWS services.

## One-time setup

From the repository root, run:

```bash
scripts/aws-dev-auth.sh install
```

This creates an `agent-login` profile whose `credential_process` asks the AWS
CLI for credentials from the existing `default` `aws login` session. It also
adds the helper to the current user's shell startup file. Open a new terminal
after setup, or source the startup file in the current one.

The AWS CLI must be version 2.32.0 or newer. The login source profile remains
`default`; renew it with:

```bash
aws_dev_login
```

Do not export the output of `aws configure export-credentials --format env`.
Those environment variables are a point-in-time snapshot and can expire while
an agent is still working. `credential_process` lets each CLI or SDK invocation
obtain fresh credentials from the AWS CLI cache.

## Verification

After signing in once, verify the active identity without printing credentials:

```bash
aws sts get-caller-identity
```

The short-lived credentials refresh automatically while the AWS login session
is valid. AWS documents that the overall session can last up to 12 hours,
subject to the IAM principal's configured session duration; therefore this
meets the six-hour development target when the initial login session is allowed
to run for at least six hours.

If the session itself expires, run `aws_dev_login` again. A new login is not
required merely because the underlying 15-minute credentials were refreshed.
